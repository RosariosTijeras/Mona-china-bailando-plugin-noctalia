#!/usr/bin/env python3
"""
bpm-realtime.py — Detección BPM en tiempo real via PipeWire/PulseAudio + aubio

Captura el audio del sistema (lo que suena por los altavoces) y detecta
el tempo en tiempo real usando aubio.tempo. Imprime el BPM por stdout
cada vez que detecta un beat. Diseñado para correr como proceso persistente
leído desde QML (Noctalia GIF Widget).

Dependencias (Fedora):
  sudo dnf install aubio aubio-python3 python3-pyaudio python3-numpy

Uso: python3 bpm-realtime.py
Salida: líneas con formato "BPM:123.4" en stdout
"""

import sys
import os
import time
import subprocess

# ── Suprimir errores ALSA que pyaudio genera al enumerar dispositivos ──────
try:
    import ctypes
    ERROR_HANDLER_FUNC = ctypes.CFUNCTYPE(
        None, ctypes.c_char_p, ctypes.c_int,
        ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p
    )
    def _alsa_error_handler(filename, line, function, err, fmt):
        pass
    _c_error_handler = ERROR_HANDLER_FUNC(_alsa_error_handler)
    _asound = ctypes.cdll.LoadLibrary('libasound.so.2')
    _asound.snd_lib_error_set_handler(_c_error_handler)
except Exception:
    pass  # Si falla, no pasa nada — solo habrá warnings de ALSA

# ── Importar dependencias ──────────────────────────────────────────────────
try:
    import aubio
    import numpy as np
    import pyaudio
except ImportError as e:
    print(f"ERROR:DEPS:{e}", flush=True)
    sys.exit(1)

# ── Parámetros de audio y detección ───────────────────────────────────────
SAMPLERATE = 44100
WIN_S = 1024       # Ventana más grande = detección más precisa
HOP_S = 512        # Salto entre muestras
CHANNELS = 1


def find_monitor_device(pa):
    """
    Busca el dispositivo monitor de audio del sistema (loopback).
    Prioridad:
      1. Monitor del sink por defecto (via pactl)
      2. Monitor de EasyEffects (común en Fedora)
      3. Cualquier dispositivo con "monitor" en el nombre
      4. Dispositivo de entrada por defecto
    """
    # 1. Obtener el monitor del sink por defecto via pactl
    try:
        result = subprocess.run(
            ['pactl', 'get-default-sink'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            default_sink = result.stdout.strip()
            monitor_name = f"{default_sink}.monitor"
            for i in range(pa.get_device_count()):
                info = pa.get_device_info_by_index(i)
                name = info.get('name', '')
                if monitor_name in name and info.get('maxInputChannels', 0) > 0:
                    return i, name
    except Exception:
        pass

    # 2. Buscar EasyEffects monitor
    for i in range(pa.get_device_count()):
        info = pa.get_device_info_by_index(i)
        name = info.get('name', '')
        if 'easyeffects' in name.lower() and 'monitor' in name.lower():
            if info.get('maxInputChannels', 0) > 0:
                return i, name

    # 3. Buscar cualquier monitor
    for i in range(pa.get_device_count()):
        info = pa.get_device_info_by_index(i)
        name = info.get('name', '')
        if 'monitor' in name.lower() and info.get('maxInputChannels', 0) > 0:
            return i, name

    # 4. Dispositivo de entrada por defecto
    try:
        default_info = pa.get_default_input_device_info()
        return default_info['index'], default_info.get('name', 'default')
    except Exception:
        pass

    return None, None


def main():
    pa = pyaudio.PyAudio()

    try:
        device_index, device_name = find_monitor_device(pa)

        if device_index is None:
            print("ERROR:NODEVICE", flush=True)
            sys.exit(1)

        print(f"DEVICE:{device_name}", flush=True)

        # Abrir stream de captura de audio
        stream = pa.open(
            format=pyaudio.paFloat32,
            channels=CHANNELS,
            rate=SAMPLERATE,
            input=True,
            frames_per_buffer=HOP_S,
            input_device_index=device_index
        )

        # Crear detector de tempo de aubio
        tempo = aubio.tempo("default", WIN_S, HOP_S, SAMPLERATE)

        print("READY", flush=True)

        last_bpm = 0.0
        last_output_time = 0.0

        while True:
            try:
                data = stream.read(HOP_S, exception_on_overflow=False)
                samples = np.frombuffer(data, dtype=np.float32)

                is_beat = tempo(samples)
                if is_beat[0] != 0:
                    bpm = tempo.get_bpm()
                    now = time.time()

                    if bpm > 0:
                        # Normalizar al rango musical (60-200 BPM)
                        while bpm > 200:
                            bpm /= 2
                        while bpm < 60:
                            bpm *= 2

                        # Imprimir si:
                        #   - BPM cambió significativamente (>3 BPM), o
                        #   - Pasó más de 1 segundo desde el último output
                        if abs(bpm - last_bpm) > 3.0 or (now - last_output_time) > 1.0:
                            print(f"BPM:{bpm:.1f}", flush=True)
                            last_bpm = bpm
                            last_output_time = now

            except IOError:
                # Buffer overflow - skip
                continue
            except Exception as e:
                print(f"ERROR:READ:{e}", file=sys.stderr)
                time.sleep(0.1)

    except KeyboardInterrupt:
        pass
    except Exception as e:
        print(f"ERROR:FATAL:{e}", flush=True)
        sys.exit(1)
    finally:
        try:
            stream.stop_stream()
            stream.close()
        except Exception:
            pass
        pa.terminate()


if __name__ == "__main__":
    main()
