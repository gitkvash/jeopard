"""Builds app/assets/sounds/*.wav -- the game's sound effects.

Two sources, both free of any licence obligation:

  * Kenney's "Music Jingles" and "Casino Audio" packs (CC0, kenney.nl) for the
    musical stings and the tactile table sounds;
  * a few cues synthesised here (the buzzers, the ding, the tick, the finale),
    because a quiz show needs exact characters that no stock pack has.

Usage, from app/:

    python tool/build_sounds.py <dir with kenney_music-jingles.zip + kenney_casino-audio.zip>

Needs numpy, scipy and soundfile. Output is 16-bit mono 44.1 kHz WAV: every
browser decodes it, whereas Ogg Vorbis still fails on older Safari, and at these
lengths the size is irrelevant.
"""

import io
import sys
import zipfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"


# ---------------------------------------------------------------- helpers


def load_zip_ogg(zf: zipfile.ZipFile, suffix: str) -> np.ndarray:
    name = next(n for n in zf.namelist() if n.endswith(suffix))
    x, sr = sf.read(io.BytesIO(zf.read(name)))
    if x.ndim > 1:
        x = x.mean(axis=1)
    if sr != SR:
        x = signal.resample_poly(x, SR, sr)
    return x


def trim(x: np.ndarray, floor: float = 0.01) -> np.ndarray:
    """Drops leading silence so the cue starts on the event, not after it."""
    loud = np.flatnonzero(np.abs(x) > floor * np.abs(x).max())
    return x[loud[0] : loud[-1] + 1] if loud.size else x


def fade_out(x: np.ndarray, ms: float = 25) -> np.ndarray:
    n = min(len(x), int(SR * ms / 1000))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n)
    return x


def normalise(x: np.ndarray, rms_db: float, peak_db: float = -1.5) -> np.ndarray:
    """Matches loudness by RMS (what the ear follows), then caps the peak."""
    rms = np.sqrt(np.mean(x**2))
    x = x * (10 ** (rms_db / 20) / rms)
    ceiling = 10 ** (peak_db / 20)
    peak = np.abs(x).max()
    return x * (ceiling / peak) if peak > ceiling else x


def t(seconds: float) -> np.ndarray:
    return np.arange(int(SR * seconds)) / SR


def bell(freq: float, seconds: float, decay: float, gain: float = 1.0) -> np.ndarray:
    """Struck-bell timbre: inharmonic partials, the upper ones dying faster."""
    tt = t(seconds)
    out = np.zeros_like(tt)
    for ratio, amp, speed in [(1, 1.0, 1), (2.76, 0.45, 1.6), (5.4, 0.22, 2.4), (8.93, 0.1, 3.4)]:
        out += amp * np.sin(2 * np.pi * freq * ratio * tt) * np.exp(-decay * speed * tt)
    attack = np.minimum(1, tt / 0.002)
    return gain * out * attack


def place(canvas: np.ndarray, x: np.ndarray, at: float) -> None:
    i = int(SR * at)
    end = min(len(canvas), i + len(x))
    canvas[i:end] += x[: end - i]


def lowpass(x: np.ndarray, hz: float) -> np.ndarray:
    return signal.sosfilt(signal.butter(4, hz, fs=SR, output="sos"), x)


# ---------------------------------------------------------------- synthesised cues


def synth_buzz_open() -> np.ndarray:
    """Bright rising pair -- the "go" cue: the buzzer is live right now."""
    out = np.zeros(int(SR * 0.7))
    place(out, bell(784.0, 0.6, 7), 0.0)  # G5
    place(out, bell(1174.7, 0.55, 7), 0.11)  # D6
    return out


def synth_buzz_in() -> np.ndarray:
    """A team has the floor: a short, dry, lower 'bonk' that is not a bell."""
    tt = t(0.34)
    freq = 330 * (1 + 0.18 * np.exp(-tt * 40))  # tiny downward pitch settle
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = signal.sawtooth(phase, 0.5) * 0.6 + np.sin(phase * 1.5) * 0.4
    return lowpass(tone, 2400) * np.exp(-tt * 9) * np.minimum(1, tt / 0.003)


def synth_wrong() -> np.ndarray:
    """The classic game-show raspberry: low, flat, held, then cut dead."""
    tt = t(0.72)
    x = np.zeros_like(tt)
    for f, a in [(98.0, 1.0), (103.5, 0.9), (196.0, 0.45), (207.0, 0.4)]:
        x += a * signal.square(2 * np.pi * f * tt, 0.5 + 0.12 * np.sin(2 * np.pi * 7 * tt))
    x = lowpass(x, 1700)
    env = np.minimum(1, tt / 0.004) * np.minimum(1, (tt[-1] - tt) / 0.03)
    return x * env


def synth_tick() -> np.ndarray:
    tt = t(0.07)
    return (np.sin(2 * np.pi * 2300 * tt) + 0.5 * np.sin(2 * np.pi * 4600 * tt)) * np.exp(-tt * 110)


def synth_finale() -> np.ndarray:
    """Rising major arpeggio in bell tone, ending on a held chord."""
    out = np.zeros(int(SR * 3.2))
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):  # C5 E5 G5 C6
        place(out, bell(f, 1.2, 4.5), 0.13 * i)
    for f in [523.25, 659.25, 783.99, 1046.5, 1318.5]:  # C major, with the 3rd up top
        place(out, bell(f, 2.6, 1.8, 0.55), 0.55)
    return out


# ---------------------------------------------------------------- build


def main(pack_dir: Path) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    jingles = zipfile.ZipFile(pack_dir / "kenney_music-jingles.zip")
    casino = zipfile.ZipFile(pack_dir / "kenney_casino-audio.zip")

    # name -> (samples, target RMS dBFS). Peak-capped at -1.5 dBFS regardless.
    cues = {
        # Kenney: contour chosen from pitch analysis, not by ear.
        "correct": (load_zip_ogg(jingles, "jingles_STEEL10.ogg"), -17),  # D E F# G, rising
        "no_answer": (load_zip_ogg(jingles, "jingles_SAX11.ogg"), -20),  # G F# E D, falling
        "round_start": (load_zip_ogg(jingles, "jingles_STEEL02.ogg"), -19),  # whole-tone run up
        "final_intro": (load_zip_ogg(jingles, "jingles_STEEL03.ogg"), -19),  # hovering minor 2nd
        "clue_pick": (load_zip_ogg(casino, "card-slide-3.ogg"), -19),
        "tap": (load_zip_ogg(casino, "chip-lay-1.ogg"), -21),
        # Synthesised.
        "buzz_open": (synth_buzz_open(), -17),
        "buzz_in": (synth_buzz_in(), -16),
        "wrong": (synth_wrong(), -17),
        "tick": (synth_tick(), -21),
        "finale": (synth_finale(), -19),
    }

    total = 0
    for name, (x, rms_db) in cues.items():
        x = fade_out(normalise(trim(x), rms_db))
        path = OUT / f"{name}.wav"
        sf.write(path, x, SR, subtype="PCM_16")
        size = path.stat().st_size
        total += size
        print(f"{name:12s} {len(x) / SR:5.2f}s  {size / 1024:6.1f} KB")
    print(f"{'total':12s} {'':6s}  {total / 1024:6.1f} KB")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]))
