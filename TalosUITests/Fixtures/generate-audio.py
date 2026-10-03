"""Deterministic stereo input for the real Finder -> Redact -> WAV flow."""
import math
import struct
import sys
import wave

rate = 48000
with wave.open(sys.argv[1], 'wb') as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(rate)
    output.writeframes(b''.join(
        struct.pack('<hh', *(round(6000 * math.sin(2 * math.pi * frequency * frame / rate))
                             for frequency in (440, 660)))
        for frame in range(rate * 5)
    ))
