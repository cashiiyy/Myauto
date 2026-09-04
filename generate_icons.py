import os
from PIL import Image, ImageDraw, ImageFilter

SOURCE_IMAGE = r"C:\Users\Kasinathan P S\.gemini\antigravity-ide\brain\d7a774e9-9350-4a25-bff6-939b873b1832\.user_uploaded\media_1788532973006.jpg"
WORKSPACE = r"k:\PROJECTS\MyAuto"

def make_icons():
    # 1. Open source image
    src = Image.open(SOURCE_IMAGE).convert("RGBA")
    w, h = src.size

    # The teal background of the icon
    TEAL_COLOR = (50, 185, 188, 255) # #32B9BC

    # Make in-app icon: detect background white and make transparent mask for squircle
    # We can create a mask where near-white corner pixels become transparent
    # The squircle starts around x in [45, 977], y in [64, 995]
    squircle_bbox = (44, 64, 977, 995)
    sw = squircle_bbox[2] - squircle_bbox[0]
    sh = squircle_bbox[3] - squircle_bbox[1]
    
    # Crop to squircle
    cropped = src.crop(squircle_bbox)
    
    # Create smooth rounded rectangle mask
    radius = int(min(sw, sh) * 0.22) # squircle radius
    mask = Image.new("L", (sw, sh), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (sw, sh)], radius=radius, fill=255)
    
    # Apply mask
    icon_transparent = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    icon_transparent.paste(cropped, (0, 0), mask)
    
    # Square 1024x1024 canvas
    app_icon_1024 = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    # Center the squircle
    pad_x = (1024 - sw) // 2
    pad_y = (1024 - sh) // 2
    app_icon_1024.paste(icon_transparent, (pad_x, pad_y), icon_transparent)

    # Also make a full-bleed square icon (for iOS app store / launchers that mask automatically)
    full_bleed_1024 = Image.new("RGBA", (1024, 1024), TEAL_COLOR)
    # Resize cropped so it fills the icon nicely (safe zone 80%)
    inner_size = int(1024 * 0.88)
    inner_icon = icon_transparent.resize((inner_size, inner_size), Image.Resampling.LANCZOS)
    full_bleed_1024.paste(inner_icon, ((1024 - inner_size) // 2, (1024 - inner_size) // 2), inner_icon)

    # Also make adaptive icon foreground (centered in 108dp canvas, safe zone is middle 66%)
    adaptive_foreground_1024 = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    fore_size = int(1024 * 0.68)
    fore_icon = icon_transparent.resize((fore_size, fore_size), Image.Resampling.LANCZOS)
    adaptive_foreground_1024.paste(fore_icon, ((1024 - fore_size) // 2, (1024 - fore_size) // 2), fore_icon)

    # Save flutter in-app asset
    os.makedirs(os.path.join(WORKSPACE, "assets", "images"), exist_ok=True)
    in_app_path = os.path.join(WORKSPACE, "assets", "images", "app_icon.png")
    app_icon_1024.save(in_app_path, "PNG")
    print(f"Saved {in_app_path}")

    # Android mipmaps
    android_res = os.path.join(WORKSPACE, "android", "app", "src", "main", "res")
    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }

    for folder, size in android_sizes.items():
        dir_path = os.path.join(android_res, folder)
        os.makedirs(dir_path, exist_ok=True)

        # Standard launcher
        std_icon = app_icon_1024.resize((size, size), Image.Resampling.LANCZOS)
        std_icon.save(os.path.join(dir_path, "ic_launcher.png"), "PNG")
        std_icon.save(os.path.join(dir_path, "ic_launcher.webp"), "WEBP")

        # Round launcher
        round_mask = Image.new("L", (size, size), 0)
        round_draw = ImageDraw.Draw(round_mask)
        round_draw.ellipse([(0, 0), (size, size)], fill=255)
        round_icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        round_icon.paste(std_icon, (0, 0), round_mask)
        round_icon.save(os.path.join(dir_path, "ic_launcher_round.png"), "PNG")
        round_icon.save(os.path.join(dir_path, "ic_launcher_round.webp"), "WEBP")

        # Adaptive foreground
        fore_scaled = adaptive_foreground_1024.resize((size, size), Image.Resampling.LANCZOS)
        fore_scaled.save(os.path.join(dir_path, "ic_launcher_foreground.png"), "PNG")
        fore_scaled.save(os.path.join(dir_path, "ic_launcher_foreground.webp"), "WEBP")
        print(f"Generated Android {folder} icons ({size}x{size})")

    # iOS AppIcon.appiconset
    ios_dir = os.path.join(WORKSPACE, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    if os.path.exists(ios_dir):
        ios_icons = {
            "Icon-App-1024x1024@1x.png": 1024,
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
        }
        for name, size in ios_icons.items():
            # iOS requires non-transparent images
            resized = full_bleed_1024.convert("RGB").resize((size, size), Image.Resampling.LANCZOS)
            resized.save(os.path.join(ios_dir, name), "PNG")
        print("Generated iOS icons")

    # Web icons
    web_icons_dir = os.path.join(WORKSPACE, "web", "icons")
    os.makedirs(web_icons_dir, exist_ok=True)
    web_sizes = {
        "Icon-192.png": 192,
        "Icon-512.png": 512,
        "Icon-maskable-192.png": 192,
        "Icon-maskable-512.png": 512,
    }
    for name, size in web_sizes.items():
        if "maskable" in name:
            scaled = full_bleed_1024.resize((size, size), Image.Resampling.LANCZOS)
        else:
            scaled = app_icon_1024.resize((size, size), Image.Resampling.LANCZOS)
        scaled.save(os.path.join(web_icons_dir, name), "PNG")
    
    # Favicon
    favicon = app_icon_1024.resize((64, 64), Image.Resampling.LANCZOS)
    favicon.save(os.path.join(WORKSPACE, "web", "favicon.png"), "PNG")
    print("Generated Web icons")

    # Windows icon (.ico)
    windows_res_dir = os.path.join(WORKSPACE, "windows", "runner", "resources")
    os.makedirs(windows_res_dir, exist_ok=True)
    ico_path = os.path.join(windows_res_dir, "app_icon.ico")
    app_icon_1024.save(ico_path, format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print(f"Generated Windows icon {ico_path}")

if __name__ == "__main__":
    make_icons()
