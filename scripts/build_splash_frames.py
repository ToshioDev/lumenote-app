from pathlib import Path
from PIL import Image, ImageFilter, ImageDraw, ImageChops
import math


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "branding" / "lumenote_isotype_v4.png"
OUT = ROOT / "assets" / "branding" / "splash_frames"
COUNT = 72
SIZE = 512


def make_frame(index: int) -> Image.Image:
    source = Image.open(SOURCE).convert("RGBA")
    alpha = source.getchannel("A")
    bbox = alpha.getbbox()
    source = source.crop(bbox)

    # A small settle at the end makes the mark feel built, not abruptly swapped.
    if index <= 58:
        build = index / 58
        # Start with a real visible fragment so the splash never looks like a blink.
        progress = 0.095 + 0.905 * (build * build * (3 - 2 * build))
    else:
        progress = 1.0
    settle = min(1.0, max(0.0, (index - 58) / 14))
    scale = 0.88 + 0.12 * (settle if index > 58 else min(1.0, index / 50))
    angle = -3.0 * (1.0 - settle) if index > 58 else -3.0 + 3.0 * min(1.0, index / 58)

    mark_size = int(330 * scale)
    source = source.resize((mark_size, mark_size), Image.Resampling.LANCZOS)
    source = source.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    source_alpha = source.getchannel("A")
    mark = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    left = (SIZE - source.width) // 2
    top = (SIZE - source.height) // 2 - 4
    mark.alpha_composite(source, (left, top))

    # Curved construction mask: the visible symbol is revealed along a rising sweep.
    reveal = Image.new("L", (SIZE, SIZE), 0)
    pixels = reveal.load()
    start_x = left - 22
    span = max(1, source.width + 44)
    for y in range(max(0, top - 4), min(SIZE, top + source.height + 4)):
        wave = 18.0 * math.sin((y - top) / max(1, source.height) * math.pi)
        boundary = start_x + span * progress + wave
        for x in range(max(0, left - 26), min(SIZE, left + source.width + 26)):
            distance = boundary - x
            pixels[x, y] = 255 if distance >= 4 else max(0, min(255, int((distance + 4) * 32)))
    reveal = reveal.filter(ImageFilter.GaussianBlur(1.3))

    clipped = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    build_mark = mark
    if progress < 0.30:
        # The first fragment is normally the dark edge of the mark. Lift it
        # temporarily so the construction is legible on the dark splash.
        build_mark = mark.copy()
        pixels = build_mark.load()
        for y in range(SIZE):
            for x in range(SIZE):
                r, g, b, a = pixels[x, y]
                if a:
                    pixels[x, y] = (151, 126, 255, a)
    clipped = Image.composite(build_mark, clipped, reveal)

    # Only the already-built part gets a restrained glow; no isolated blob at frame 1.
    if progress > 0.08:
        # Derive the glow from the logo alpha, never from the rectangular reveal mask.
        visible_alpha = ImageChops.multiply(mark.getchannel("A"), reveal)
        glow_alpha = visible_alpha.filter(ImageFilter.GaussianBlur(16))
        glow_alpha = glow_alpha.point(lambda value: int(value * 0.16 * min(1.0, progress * 1.8)))
        glow = Image.new("RGBA", (SIZE, SIZE), (116, 91, 255, 0))
        glow.putalpha(glow_alpha)
        clipped = Image.alpha_composite(glow, clipped)

    # A fine purple tracer marks the active construction edge.
    if progress < 0.985:
        draw = ImageDraw.Draw(clipped)
        boundary = start_x + span * progress
        tracer = []
        for step in range(0, 25):
            y = top + int(source.height * (0.08 + 0.84 * step / 24))
            x = int(boundary + 18 * math.sin((y - top) / max(1, source.height) * math.pi))
            if 0 <= x < SIZE and 0 <= y < SIZE:
                tracer.append((x, y))
        if len(tracer) > 1:
            draw.line(tracer, fill=(174, 151, 255, 220), width=3, joint="curve")
    return clipped


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    frames = []
    for number in range(COUNT):
        frame = make_frame(number)
        path = OUT / f"frame-{number + 1:02d}.png"
        frame.save(path, "PNG", optimize=True)
        frames.append(frame.convert("RGBA"))
    frames[0].save(
        ROOT / "assets" / "branding" / "lumenote_splash.gif",
        save_all=True,
        append_images=frames[1:],
        duration=40,
        loop=0,
        disposal=2,
        transparency=0,
    )


if __name__ == "__main__":
    main()
