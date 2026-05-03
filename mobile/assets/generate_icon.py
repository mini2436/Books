from PIL import Image, ImageDraw

SIZE = 1024
RADIUS = int(SIZE * 0.22)
BG_COLOR = "#7A4A24"
COVER_COLOR = "#F5F0E6"
SPINE_COLOR = "#6B3F1F"
PAGE_TOP = "#FFFDF8"
PAGE_SIDE = "#E8E0D0"
ACCENT = "#C8A882"

def draw_book(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s = size / 1024.0

    # Background shadow
    so = int(26 * s)
    for i in range(10, 0, -1):
        a = int(12 * (1 - i / 10))
        off = so + i
        draw.rounded_rectangle(
            [off, off, size - off + so, size - off + so],
            radius=int(RADIUS * s), fill=(0, 0, 0, a)
        )
    draw.rounded_rectangle([0, 0, size, size], radius=int(RADIUS * s), fill=BG_COLOR)

    # Book dimensions (more elongated, realistic book ratio)
    bw = int(340 * s)
    bh = int(480 * s)
    cx, cy = size // 2, size // 2
    x1 = cx - bw // 2
    y1 = cy - bh // 2
    x2 = cx + bw // 2
    y2 = cy + bh // 2
    spine = int(36 * s)
    page_h = int(28 * s)
    corner = int(8 * s)

    # Book shadow
    sd = int(18 * s)
    draw.rounded_rectangle(
        [x1 + sd, y1 + sd, x2 + sd, y2 + sd],
        radius=corner, fill="#5A3518"
    )

    # Spine
    draw.rounded_rectangle(
        [x1, y1, x1 + spine, y2],
        radius=corner, fill=SPINE_COLOR
    )

    # Cover
    draw.rounded_rectangle(
        [x1 + spine, y1, x2, y2],
        radius=corner, fill=COVER_COLOR
    )

    # Top pages
    draw.rectangle([x1 + spine, y1, x2, y1 + page_h], fill=PAGE_TOP)

    # Right page edge
    edge = int(8 * s)
    draw.rectangle([x2 - edge, y1 + page_h, x2, y2], fill=PAGE_SIDE)

    # Bottom thickness
    draw.rectangle(
        [x1 + spine, y2 - page_h, x2 - edge, y2],
        fill="#DDD5C5"
    )

    # Spine highlight
    draw.line(
        [(x1 + int(spine * 0.35), y1 + int(bh * 0.10)),
         (x1 + int(spine * 0.35), y2 - int(bh * 0.10))],
        fill=(255, 255, 255, 30), width=int(6 * s)
    )

    # Title lines
    lw = int(200 * s)
    lh = max(2, int(10 * s))
    lx = x1 + spine + int(40 * s)
    ly1 = y1 + int(bh * 0.32)
    lg = int(50 * s)
    for i in range(3):
        y = ly1 + i * lg
        draw.rounded_rectangle([lx, y, lx + lw, y + lh], radius=lh // 2, fill=ACCENT)
    # Shorter second line
    draw.rounded_rectangle(
        [lx, ly1 + lg, lx + int(lw * 0.60), ly1 + lg + lh],
        radius=lh // 2, fill=ACCENT
    )

    return img

def main():
    # Generate source icon
    icon = draw_book(1024)
    icon.save("mobile/assets/icon.png")
    print("Saved mobile/assets/icon.png")

    # Generate iOS icons
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
    ios_dir = "mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, sz in ios_sizes.items():
        img = draw_book(sz)
        img.save(f"{ios_dir}/{name}")
        print(f"Saved {ios_dir}/{name}")

    # Generate Android icons
    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    android_dir = "mobile/android/app/src/main/res"
    for folder, sz in android_sizes.items():
        img = draw_book(sz)
        img.save(f"{android_dir}/{folder}/ic_launcher.png")
        print(f"Saved {android_dir}/{folder}/ic_launcher.png")

if __name__ == "__main__":
    main()
