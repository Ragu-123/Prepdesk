"""Export platform icon sizes from the supplied square Prepdesk artwork.

Usage: python scripts/prepare_brand_assets.py path/to/prepdesk.png
Requires Pillow. Android builds use the checked-in resources.
"""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'android/app/src/main/res'
ASSETS = ROOT / 'assets/images'
BACKGROUND = '#f6f2fc'


def save_square(image, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(path, optimize=True)


def export(source):
    artwork = Image.open(source).convert('RGB')
    if artwork.width != artwork.height:
        raise ValueError('Expected square Prepdesk artwork')
    artwork = artwork.resize((1254, 1254), Image.Resampling.LANCZOS)
    icon = artwork.crop((127, 127, 1127, 1127))
    save_square(artwork, ASSETS / 'prepdesk.png', 512)
    save_square(icon, ASSETS / 'icon.png', 512)
    save_square(icon, RES.parent / 'ic_launcher-playstore.png', 512)
    save_square(icon, RES / 'drawable/nyro_notification_logo.png', 192)

    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        circle = Image.new('L', (1000, 1000))
        ImageDraw.Draw(circle).ellipse((0, 0, 999, 999), fill=255)
        folder = RES / f'mipmap-{density}'
        save_square(icon, folder / 'ic_launcher.png', size)
        circular = icon.convert('RGBA')
        circular.putalpha(circle)
        save_square(circular, folder / 'ic_launcher_round.png', size)
        save_square(artwork, RES / f'drawable-{density}/prepdesk_legacy_splash.png', size * 4)

    # Alpha-only mark with an open bookmark and check for theme tinting.
    mask = Image.new('L', (240, 240))
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((29, 53, 211, 218), radius=34, fill=255)
    draw.polygon([(123, 48), (176, 48), (176, 106), (150, 88), (123, 106)], fill=0)
    points = [(94, 159), (119, 184), (175, 127)]
    draw.line(points, fill=0, width=19, joint='curve')
    for x, y in points:
        draw.ellipse((x - 9, y - 9, x + 9, y + 9), fill=0)
    draw.line([(23, 166), (23, 81), (40, 55), (106, 29)], fill=255, width=10, joint='curve')
    themed = Image.new('RGBA', mask.size, 'white')
    themed.putalpha(mask)
    save_square(themed, ASSETS / 'prepdesk_mark.png', 192)

    web = ROOT / 'web'
    for file, size in [('favicon.png', 48), ('icons/Icon-192.png', 192), ('icons/Icon-512.png', 512)]:
        save_square(icon, web / file, size)
    icon.save(ROOT / 'windows/runner/resources/app_icon.ico', sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
    ios = ROOT / 'ios/Runner/Assets.xcassets'
    for path in (ios / 'AppIcon.appiconset').glob('*.png'):
        size = Image.open(path).width
        save_square(icon, path, size)
    launch = ios / 'LaunchImage.imageset'
    for scale, suffix in [(1, ''), (2, '@2x'), (3, '@3x')]:
        save_square(artwork, launch / f'LaunchImage{suffix}.png', 168 * scale)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    export(parser.parse_args().source)
