#!/usr/bin/env python3
"""Generate the two ForeverCoach signals as short OGG files, one per volume step.

    python3 tools/make_sounds.py          (needs oggenc from vorbis-tools)

The game's PlaySoundFile() has no volume argument, so every signal is rendered at
10 levels (10%..100%) and the addon plays the file closest to the volume setting.
The sounds are synthesized here from sine waves: original work, released as CC0.

  ready  "Пора нажимать": a soft neutral click, ~40 ms
  proc   instant proc: a bright two-note chime, ~0.5 s, clearly louder than the click
"""
import math
import os
import struct
import subprocess
import tempfile
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "ForeverCoach", "Media", "Sounds")
STEPS = range(10, 101, 10)


def click():
    n = int(RATE * 0.04)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t / 0.006)
        s = 0.7 * math.sin(2 * math.pi * 1900 * t) + 0.3 * math.sin(2 * math.pi * 950 * t)
        out.append(0.45 * env * s)
    return out


def chime():
    n = int(RATE * 0.55)
    notes = [(0.0, 1318.5), (0.08, 1975.5)]  # E6, then B6
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for start, freq in notes:
            if t >= start:
                u = t - start
                env = math.exp(-u / 0.14) * min(1.0, u / 0.003)
                s += env * (math.sin(2 * math.pi * freq * u) + 0.3 * math.sin(2 * math.pi * 2 * freq * u))
        out.append(0.42 * s)
    return out


def write_ogg(samples, gain, path):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name
    try:
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x * gain)) * 32767)) for x in samples)
            w.writeframes(frames)
        subprocess.run(["oggenc", "-Q", "-q", "4", "-o", path, wav_path], check=True)
    finally:
        os.remove(wav_path)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, samples in (("ready", click()), ("proc", chime())):
        for step in STEPS:
            gain = (step / 100.0) ** 1.7  # roughly even loudness steps
            write_ogg(samples, gain, os.path.join(OUT, "%s_%d.ogg" % (name, step)))
    print("written to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
