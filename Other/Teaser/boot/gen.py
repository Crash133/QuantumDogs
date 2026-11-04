
import argparse
import json
import random
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


DEFAULTS = {
    "output": "linux_boot.mp4",
    "width": 1920,
    "height": 1080,
    "fps": 30,
    "duration": 20,
    "seed": 42,

    "background": "#050408",
    "text_color": "#e7e4f2",
    "ok_color": "#36d653",
    "warn_color": "#ffc857",
    "error_color": "#ff5263",

    "font_path": "",  # Empty = automatically find a font
    "font_size": 25,
    "margin_x": 32,
    "margin_y": 30,
    "line_spacing": 7,

    "line_interval": 0.20,
    "startup_delay": 0.4,
    "scroll": True,
    "cursor": True,
    "cursor_blink_hz": 1.4,

    "flicker": 0.015,
    "scanlines": 0.025,
    "vignette": 0.12,

    "timeout_at": 15.5,
    "timeout_enabled": True,
    "timeout_text": (
        r"Job dev-disk-by\x2duuid-CEF9\x2dE89C.device/"
        r"start running (42s / 1min 30s)"
    ),

    "messages": [
        ["OK", "Reached target swap.target - Swaps."],
        ["START", "Starting systemd-backlight@leds:dell::kbd_backlight.service - Load/Save Screen Backlight Brightness..."],
        ["OK", "Finished systemd-backlight@leds:dell::kbd_backlight.service - Load/Save Screen Backlight Brightness."],
        ["START", "Starting systemd-rfkill.service - Load/Save RF Kill Switch Status..."],
        ["OK", "Started systemd-rfkill.service - Load/Save RF Kill Switch Status."],
        ["START", "Starting modprobe@dm_mod.service - Load Kernel Module dm_mod..."],
        ["START", "Starting modprobe@efi_pstore.service - Load Kernel Module efi_pstore..."],
        ["START", "Starting modprobe@loop.service - Load Kernel Module loop..."],
        ["OK", "Finished modprobe@dm_mod.service - Load Kernel Module dm_mod."],
        ["OK", "Finished modprobe@efi_pstore.service - Load Kernel Module efi_pstore."],
        ["OK", "Finished modprobe@loop.service - Load Kernel Module loop."],
        ["START", "Starting systemd-backlight@backlight:intel_backlight.service - Load/Save Screen Brightness..."],
        ["OK", "Finished systemd-backlight@backlight:intel_backlight.service - Load/Save Screen Brightness."],
        ["START", "Starting systemd-udev-settle.service - Wait for udev To Complete Device Initialization..."],
        ["OK", "Finished systemd-udev-settle.service - Wait for udev To Complete Device Initialization."],
        ["START", "Starting zfs-load-module.service - Install ZFS kernel module..."],
        ["OK", "Finished zfs-load-module.service - Install ZFS kernel module."],
        ["OK", "Reached target zfs-import.target - ZFS pool import target."],
        ["START", "Starting zfs-mount.service - Mount ZFS filesystems..."],
        ["START", "Starting zfs-volume-wait.service - Wait for ZFS Volume links in /dev..."],
        ["OK", "Finished zfs-mount.service - Mount ZFS filesystems."],
        ["OK", "Finished zfs-volume-wait.service - Wait for ZFS Volume links in /dev."],
        ["OK", "Reached target zfs-volumes.target - ZFS volumes are ready."],
    ],
}


def color(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def get_font(cfg):
    size = cfg["font_size"]
    candidates = [
        cfg["font_path"],
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
        r"C:\Windows\Fonts\consola.ttf",
        r"C:\Windows\Fonts\lucon.ttf",
        "/System/Library/Fonts/Menlo.ttc",
    ]

    for path in candidates:
        if path and Path(path).is_file():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass

    print("Warning: using Pillow's fallback font.")
    return ImageFont.load_default()


def make_events(cfg):
    rng = random.Random(cfg["seed"])
    events = []
    t = cfg["startup_delay"]

    for status, message in cfg["messages"]:
        events.append((t, status, message))
        t += cfg["line_interval"] * rng.uniform(0.75, 1.3)

    if cfg["timeout_enabled"]:
        events.append((
            cfg["timeout_at"],
            "ERROR",
            cfg["timeout_text"],
        ))

    events.sort(key=lambda event: event[0])
    return events


def add_vignette(image, strength):
    if strength <= 0:
        return image

    width, height = image.size
    pixels = image.load()

    for y in range(height):
        ny = (2 * y / max(1, height - 1)) - 1

        for x in range(width):
            nx = (2 * x / max(1, width - 1)) - 1
            distance = min(1.0, (nx * nx + ny * ny) ** 0.5 / 1.4142)
            factor = 1.0 - strength * distance

            r, g, b = pixels[x, y]
            pixels[x, y] = (
                int(r * factor),
                int(g * factor),
                int(b * factor),
            )

    return image


def render_frame(cfg, font, events, t, rng):
    width = cfg["width"]
    height = cfg["height"]

    image = Image.new(
        "RGB",
        (width, height),
        color(cfg["background"]),
    )
    draw = ImageDraw.Draw(image)

    bbox = font.getbbox("Ag")
    line_height = bbox[3] - bbox[1] + cfg["line_spacing"]

    max_lines = max(
        1,
        (height - 2 * cfg["margin_y"]) // line_height,
    )

    visible = [
        event for event in events
        if event[0] <= t
    ]

    if cfg["scroll"]:
        visible = visible[-max_lines:]
    else:
        visible = visible[:max_lines]

    x = cfg["margin_x"]
    y = cfg["margin_y"]

    for _, status, message in visible:
        if status == "OK":
            marker = "[  OK  ]"
            marker_color = color(cfg["ok_color"])
        elif status == "WARN":
            marker = "[ WARN ]"
            marker_color = color(cfg["warn_color"])
        elif status == "ERROR":
            marker = "[ ** ]"
            marker_color = color(cfg["error_color"])
        else:
            marker = ""
            marker_color = color(cfg["text_color"])

        prefix = marker + " " if marker else "    "

        # Separate colored status indicator and white service message.
        draw.text((x, y), prefix, font=font, fill=marker_color)

        text_x = x + int(draw.textlength(prefix, font=font))
        available_width = width - text_x - cfg["margin_x"]

        # Clip lines that exceed the frame width.
        while message and draw.textlength(message, font=font) > available_width:
            message = message[:-1]

        draw.text(
            (text_x, y),
            message,
            font=font,
            fill=color(cfg["text_color"]),
        )

        y += line_height

    # A blinking block cursor at the next terminal line.
    if cfg["cursor"] and y + line_height < height:
        blink = int(t * cfg["cursor_blink_hz"] * 2) % 2 == 0

        if blink:
            cursor_width = max(4, cfg["font_size"] // 2)
            cursor_height = max(8, cfg["font_size"])
            draw.rectangle(
                (x, y, x + cursor_width, y + cursor_height),
                fill=color(cfg["text_color"]),
            )

    # Alternating darker rows, resembling a photographed screen.
    scanlines = cfg["scanlines"]

    if scanlines > 0:
        pixels = image.load()
        factor = 1 - min(0.5, scanlines)

        for sy in range(1, height, 2):
            for sx in range(width):
                r, g, b = pixels[sx, sy]
                pixels[sx, sy] = (
                    int(r * factor),
                    int(g * factor),
                    int(b * factor),
                )

    image = add_vignette(image, cfg["vignette"])

    # Small brightness fluctuations, deterministic for a given seed.
    flicker = cfg["flicker"]

    if flicker > 0:
        factor = 1 + rng.uniform(-flicker, flicker)
        image = image.point(
            lambda p: max(0, min(255, int(p * factor)))
        )

    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=None)
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    cfg = DEFAULTS.copy()

    if args.config:
        with open(args.config, encoding="utf-8") as f:
            cfg.update(json.load(f))

    if args.output:
        cfg["output"] = args.output

    if not shutil.which("ffmpeg"):
        raise RuntimeError(
            "FFmpeg is missing. Install it and ensure it is on PATH."
        )

    if cfg["width"] < 320 or cfg["height"] < 180:
        raise ValueError("Resolution must be at least 320x180.")

    if cfg["fps"] < 1 or cfg["duration"] <= 0:
        raise ValueError("FPS and duration must be positive.")

    font = get_font(cfg)
    events = make_events(cfg)
    rng = random.Random(cfg["seed"] + 1)

    output = Path(cfg["output"])
    output.parent.mkdir(parents=True, exist_ok=True)

    command = [
        "ffmpeg",
        "-y",
        "-loglevel", "error",
        "-f", "rawvideo",
        "-pix_fmt", "rgb24",
        "-s", f'{cfg["width"]}x{cfg["height"]}',
        "-r", str(cfg["fps"]),
        "-i", "-",
        "-an",
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "18",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        str(output),
    ]

    total_frames = round(cfg["duration"] * cfg["fps"])

    with subprocess.Popen(command, stdin=subprocess.PIPE) as ffmpeg:
        assert ffmpeg.stdin is not None

        try:
            for frame_index in range(total_frames):
                t = frame_index / cfg["fps"]

                frame = render_frame(
                    cfg, font, events, t, rng
                )

                ffmpeg.stdin.write(frame.tobytes())

                if frame_index % cfg["fps"] == 0:
                    progress = 100 * frame_index / total_frames
                    print(
                        f"\rRendering: {progress:5.1f}%",
                        end="",
                        flush=True,
                    )

        finally:
            ffmpeg.stdin.close()

        result = ffmpeg.wait()

    print()

    if result != 0:
        raise RuntimeError(f"FFmpeg exited with code {result}.")

    print(f"Video generated: {output.resolve()}")


if __name__ == "__main__":
    main()
