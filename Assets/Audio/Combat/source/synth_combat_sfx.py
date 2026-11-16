"""Project-authored combat SFX for Quantum Dogs (E.O.L.).

Pure procedural synthesis (Python stdlib only, fixed seeds): no recordings,
samples or third-party audio are used, so every output is original project
work. Re-running this script reproduces the files byte-for-byte and rewrites
../manifest.json with SHA-256 lineage.

    python synth_combat_sfx.py
"""
import hashlib
import json
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent
TAU = math.tau


def env(t, attack, decay, sustain_end=None):
    """Linear attack, exponential decay envelope."""
    if t < attack:
        return t / attack
    t -= attack
    return math.exp(-t / max(1e-4, decay))


class Biquad:
    """RBJ band-pass (constant peak gain) / low-pass, updated per call."""
    def __init__(self):
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def run(self, x, freq, q, kind="bp"):
        freq = min(max(freq, 20.0), RATE * 0.45)
        w = TAU * freq / RATE
        alpha = math.sin(w) / (2 * q)
        cw = math.cos(w)
        if kind == "bp":
            b0, b1, b2 = alpha, 0.0, -alpha
        else:  # low-pass
            b0 = b2 = (1 - cw) / 2
            b1 = 1 - cw
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
        y = (b0 * x + b1 * self.x1 + b2 * self.x2 - a1 * self.y1 - a2 * self.y2) / a0
        self.x2, self.x1, self.y2, self.y1 = self.x1, x, self.y1, y
        return y


def render(seconds, fn, seed):
    rng = random.Random(seed)
    return [fn(i / RATE, rng) for i in range(int(seconds * RATE))]


def whoosh(length, f0, f1, q, attack, decay, gain=1.0, seed=1):
    bp = Biquad()

    def fn(t, rng):
        k = t / length
        f = f0 * (f1 / f0) ** k
        return bp.run(rng.uniform(-1, 1), f, q) * env(t, attack, decay) * gain * 3.0
    return render(length, fn, seed)


def tone(length, f0, f1, attack, decay, wave_kind="sine", gain=1.0, seed=1):
    phase = [0.0]
    lp = Biquad()  # Tames naive saw/square aliasing (keeps ~8 harmonics).

    def fn(t, rng):
        k = t / length
        f = f0 * (f1 / f0) ** k
        phase[0] += TAU * f / RATE
        p = phase[0]
        if wave_kind == "saw":
            s = 2 * ((p / TAU) % 1.0) - 1
        elif wave_kind == "square":
            s = 1.0 if math.sin(p) >= 0 else -1.0
        else:
            s = math.sin(p)
        if wave_kind != "sine":
            s = lp.run(s, min(8.0 * f, 6000.0), 0.7, "lp")
        return s * env(t, attack, decay) * gain
    return render(length, fn, seed)


def noise_burst(length, cutoff, attack, decay, gain=1.0, seed=1):
    lp = Biquad()

    def fn(t, rng):
        return lp.run(rng.uniform(-1, 1), cutoff, 0.7, "lp") * env(t, attack, decay) * gain
    return render(length, fn, seed)


def mix(*parts, offsets=None):
    offsets = offsets or [0.0] * len(parts)
    n = max(len(p) + int(o * RATE) for p, o in zip(parts, offsets))
    out = [0.0] * n
    for p, o in zip(parts, offsets):
        start = int(o * RATE)
        for i, s in enumerate(p):
            out[start + i] += s
    return out


def finish(samples, peak=0.89, fade_ms=8):
    """Normalise to `peak`, short fade-out, soft clip."""
    m = max(1e-9, max(abs(s) for s in samples))
    fade = int(RATE * fade_ms / 1000)
    out = []
    for i, s in enumerate(samples):
        v = math.tanh(1.2 * s / m) / math.tanh(1.2) * peak
        if i >= len(samples) - fade:
            v *= (len(samples) - i) / fade
        out.append(v)
    return out


def write(name, samples):
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))
    return path


SOUNDS = {
    # cue family -> (description, builder)
    "mantis_swing": ("two fast thin crossing whooshes", lambda: mix(
        whoosh(0.16, 2400, 5200, 6, 0.01, 0.05, seed=11), whoosh(0.16, 2800, 6000, 6, 0.01, 0.05, seed=12), offsets=[0, 0.06])),
    "saber_swing": ("clean whoosh with a bright plasma zing", lambda: mix(
        whoosh(0.28, 900, 3200, 4, 0.02, 0.09, seed=21), tone(0.28, 1400, 900, 0.005, 0.12, gain=0.25, seed=22))),
    "lance_swing": ("forward thrust whoosh with low rocket hiss", lambda: mix(
        whoosh(0.3, 500, 1800, 3, 0.01, 0.1, seed=31), noise_burst(0.3, 900, 0.02, 0.12, gain=0.4, seed=32))),
    "greatsword_swing": ("slow heavy wide whoosh", lambda: whoosh(0.55, 220, 900, 2.5, 0.08, 0.2, seed=41)),
    "saber_plasma": ("charged plasma zap sweeping down", lambda: mix(
        tone(0.45, 2200, 300, 0.01, 0.18, "saw", 0.35, seed=51), whoosh(0.45, 1500, 4000, 5, 0.02, 0.15, seed=52))),
    "lance_fire": ("rocket burst with crackle tail", lambda: mix(
        noise_burst(0.6, 2500, 0.004, 0.18, seed=61), tone(0.6, 110, 60, 0.004, 0.2, "saw", 0.5, seed=62))),
    "lance_stoke": ("whirring drill pull rising", lambda: mix(
        tone(0.7, 180, 420, 0.05, 0.4, "square", 0.25, seed=71), whoosh(0.7, 600, 2400, 8, 0.05, 0.35, 0.6, seed=72))),
    "greatsword_shock": ("delayed low thud and rumble", lambda: mix(
        tone(0.8, 90, 38, 0.003, 0.25, gain=1.0, seed=81), noise_burst(0.8, 400, 0.01, 0.3, 0.6, seed=82))),
    "revolver_shot": ("sharp crack with short metallic tail", lambda: mix(
        noise_burst(0.35, 7000, 0.0008, 0.03, seed=91), tone(0.35, 2600, 2400, 0.001, 0.06, gain=0.2, seed=92), tone(0.35, 120, 70, 0.001, 0.08, gain=0.6, seed=93))),
    "impact_light": ("tight synthetic hit tick", lambda: mix(
        noise_burst(0.14, 4000, 0.001, 0.025, seed=101), tone(0.14, 600, 300, 0.001, 0.03, gain=0.4, seed=102))),
    "impact_heavy": ("heavy compressed hit with sub", lambda: mix(
        noise_burst(0.35, 2200, 0.001, 0.06, seed=111), tone(0.35, 140, 50, 0.001, 0.1, gain=0.9, seed=112))),
    "parry": ("bright metallic ping", lambda: mix(
        tone(0.6, 1760, 1760, 0.001, 0.18, gain=0.7, seed=121), tone(0.6, 2637, 2637, 0.001, 0.12, gain=0.4, seed=122), noise_burst(0.6, 6000, 0.0005, 0.01, 0.5, seed=123))),
    "block": ("dull armoured clank", lambda: mix(
        tone(0.3, 420, 380, 0.001, 0.06, "square", 0.3, seed=131), noise_burst(0.3, 1200, 0.001, 0.04, seed=132))),
    "execution": ("heavy crunch dropping into sub", lambda: mix(
        noise_burst(0.9, 1800, 0.002, 0.15, seed=141), tone(0.9, 160, 35, 0.002, 0.35, gain=1.0, seed=142), tone(0.9, 700, 200, 0.01, 0.2, "saw", 0.2, seed=143))),
    "player_hurt": ("short glitch buzz", lambda: mix(
        tone(0.25, 220, 140, 0.002, 0.08, "square", 0.5, seed=151), noise_burst(0.25, 3000, 0.002, 0.05, 0.5, seed=152))),
    "dash": ("quick air burst", lambda: whoosh(0.22, 1200, 400, 3, 0.005, 0.07, seed=161)),
    "switch": ("mechanical click and short tone", lambda: mix(
        noise_burst(0.2, 5000, 0.0005, 0.008, seed=171), tone(0.2, 880, 1320, 0.004, 0.05, gain=0.35, seed=172), offsets=[0, 0.02])),
    "warning_common": ("soft warm two-note lamp beep", lambda: mix(
        tone(0.3, 520, 520, 0.01, 0.06, gain=0.6, seed=181), tone(0.3, 660, 660, 0.01, 0.07, gain=0.6, seed=182), offsets=[0, 0.11])),
    "warning_drone": ("rising lens-charge chirp", lambda: tone(0.35, 600, 1500, 0.02, 0.2, "sine", 0.7, seed=191)),
    "warning_elite": ("low warm horn swell", lambda: mix(
        tone(0.6, 110, 118, 0.12, 0.35, "saw", 0.4, seed=201), tone(0.6, 165, 170, 0.12, 0.35, "sine", 0.5, seed=202))),
}


def main():
    entries = []
    for name, (description, build) in SOUNDS.items():
        path = write(name, finish(build()))
        entries.append({
            "file": f"res://Assets/Audio/Combat/{path.name}",
            "cue_family": name,
            "description": description,
            "creator": "Quantum Dogs project (Combat Presentation slice, Claude Code agent)",
            "source_or_method": "Procedural synthesis, Assets/Audio/Combat/source/synth_combat_sfx.py (Python stdlib; seeded noise, filters, oscillators). No recordings or third-party samples.",
            "license": "Project-owned original work; commercial redistribution permitted by the project owner.",
            "attribution": "None required.",
            "modifications": "None after generation (44.1 kHz, mono, 16-bit PCM WAV).",
            "status": "generated; awaiting human listening pass",
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })
    (OUT / "manifest.json").write_text(json.dumps({"generated_by": "source/synth_combat_sfx.py", "sounds": entries}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(entries)} sounds")


if __name__ == "__main__":
    main()
