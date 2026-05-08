from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = ROOT / "mobile" / "assets"
IOS_ICON_DIR = ROOT / "mobile" / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
MACOS_ICON_DIR = ROOT / "mobile" / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
ANDROID_RES_DIR = ROOT / "mobile" / "android" / "app" / "src" / "main" / "res"
WEB_DIR = ROOT / "mobile" / "web"
WEB_ICON_DIR = WEB_DIR / "icons"
WINDOWS_ICON_PATH = ROOT / "mobile" / "windows" / "runner" / "resources" / "app_icon.ico"

SOURCE_ICON = ASSET_DIR / "icon_master.png"
PRIMARY_ICON = ASSET_DIR / "icon.png"
EDGE_MATTE_THRESHOLD = 96
TRANSPARENT_EDGE_RGB = (246, 232, 211)


def clear_edge_matte(image):
    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()
    matte = Image.new("1", image.size, 0)
    matte_pixels = matte.load()
    queue = deque()

    def is_edge_matte(x, y):
        r, g, b, a = pixels[x, y]
        return (
            a > 0
            and r <= EDGE_MATTE_THRESHOLD
            and g <= EDGE_MATTE_THRESHOLD
            and b <= EDGE_MATTE_THRESHOLD
        )

    def add_seed(x, y):
        if matte_pixels[x, y] == 0 and is_edge_matte(x, y):
            matte_pixels[x, y] = 1
            queue.append((x, y))

    for x in range(width):
        add_seed(x, 0)
        add_seed(x, height - 1)
    for y in range(height):
        add_seed(0, y)
        add_seed(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for next_x, next_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= next_x < width and 0 <= next_y < height:
                add_seed(next_x, next_y)

    result = image.copy()
    result_pixels = result.load()
    for y in range(height):
        for x in range(width):
            if matte_pixels[x, y]:
                result_pixels[x, y] = (*TRANSPARENT_EDGE_RGB, 0)
    return result


def load_master():
    image = Image.open(SOURCE_ICON).convert("RGBA")
    if image.size != (1024, 1024):
        image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
    return clear_edge_matte(image)


def save_icon(image, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    if image.size == (size, size):
        resized = image
    else:
        resized = image.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(path)
    print(f"Saved {path.relative_to(ROOT)}")


def generate_ios_icons(master):
    if not IOS_ICON_DIR.exists():
        print(f"Skipped {IOS_ICON_DIR.relative_to(ROOT)}")
        return

    ios_sizes = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, target_size in ios_sizes.items():
        save_icon(master, IOS_ICON_DIR / name, target_size)


def generate_macos_icons(master):
    macos_sizes = {
        "app_icon_16.png": 16,
        "app_icon_32.png": 32,
        "app_icon_64.png": 64,
        "app_icon_128.png": 128,
        "app_icon_256.png": 256,
        "app_icon_512.png": 512,
        "app_icon_1024.png": 1024,
    }
    for name, target_size in macos_sizes.items():
        save_icon(master, MACOS_ICON_DIR / name, target_size)


def generate_android_icons(master):
    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, target_size in android_sizes.items():
        save_icon(master, ANDROID_RES_DIR / folder / "ic_launcher.png", target_size)


def generate_web_icons(master):
    save_icon(master, WEB_DIR / "favicon.png", 64)
    save_icon(master, WEB_ICON_DIR / "Icon-192.png", 192)
    save_icon(master, WEB_ICON_DIR / "Icon-512.png", 512)
    save_icon(master, WEB_ICON_DIR / "Icon-maskable-192.png", 192)
    save_icon(master, WEB_ICON_DIR / "Icon-maskable-512.png", 512)


def generate_windows_icon(master):
    WINDOWS_ICON_PATH.parent.mkdir(parents=True, exist_ok=True)
    master.save(
        WINDOWS_ICON_PATH,
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(f"Saved {WINDOWS_ICON_PATH.relative_to(ROOT)}")


def main():
    master = load_master()
    save_icon(master, SOURCE_ICON, 1024)
    save_icon(master, PRIMARY_ICON, 1024)
    generate_ios_icons(master)
    generate_macos_icons(master)
    generate_android_icons(master)
    generate_web_icons(master)
    generate_windows_icon(master)


if __name__ == "__main__":
    main()
