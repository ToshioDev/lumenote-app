"""Build transparent Founder splash frames from the Kuromi source artwork.

The glow is derived from the artwork alpha channel, so no rectangular bitmap
background is introduced into the animation.
"""
from pathlib import Path
import math
from PIL import Image, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "branding" / "kurominotes_splash_source.png"
OUT = ROOT / "assets" / "branding" / "kuromi_splash_frames"
GIF = ROOT / "assets" / "branding" / "kurominotes_splash.gif"
COUNT = 144
SIZE = 720


def fit_artwork(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    bbox = image.getchannel("A").getbbox()
    if bbox:
        image = image.crop(bbox)
    image.thumbnail((430, 430), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(image, ((SIZE - image.width) // 2, (SIZE - image.height) // 2))
    return canvas


def frame(base: Image.Image, index: int) -> Image.Image:
    progress = index / (COUNT - 1)
    eased = 1 - (1 - progress) ** 3
    scale = 0.78 + 0.22 * min(1.0, eased * 1.25)
    angle = math.sin(progress * math.pi * 2.2) * 1.15
    transformed = base.resize((int(SIZE * scale), int(SIZE * scale)), Image.Resampling.LANCZOS)
    transformed = transformed.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    alpha = transformed.getchannel("A")
    revealed = alpha.point(lambda value: int(value * min(1.0, eased * 1.35)))
    transformed.putalpha(revealed)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(transformed, ((SIZE - transformed.width) // 2, (SIZE - transformed.height) // 2))

    # A restrained pink aura based only on the visible alpha mask.
    aura = revealed.filter(ImageFilter.GaussianBlur(18))
    aura = ImageEnhance.Brightness(aura).enhance(0.2)
    glow = Image.new("RGBA", aura.size, (255, 89, 174, 0))
    glow.putalpha(aura)
    canvas.alpha_composite(glow, ((SIZE - glow.width) // 2, (SIZE - glow.height) // 2))
    return canvas


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    base = fit_artwork(Image.open(SOURCE))
    frames = []
    for index in range(COUNT):
        image = frame(base, index)
        target = OUT / f"frame-{index + 1:03d}.png"
        image.save(target, optimize=True)
        frames.append(image)
    frames[0].save(GIF, save_all=True, append_images=frames[1:], duration=28, loop=0, disposal=2, transparency=0, optimize=True)
    print(f"Generated {COUNT} transparent frames and {GIF}")


if __name__ == "__main__":
    main()
