#!/usr/bin/env python3
"""Makes a pretend Steam folder full of made-up games with original cover art, for README screenshots.

    python3 tools/demo_games.py <home folder>     then run tools/ui-test.sh with HOMESEED=<home folder>
                                                  and the printed "home_pinned" list in PRESEED

Every game and picture is invented here (no real game art). The games are written into Steam's list of non-Steam
games (userdata/<id>/config/shortcuts.vdf) with their covers in config/grid, the way Steam stores custom art.
"""
import math, os, random, struct, sys, zlib
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTS = os.path.join(os.path.dirname(__file__), "..", "shell", "tephra-shell", "assets", "fonts")

# title, font, sky top, sky bottom, sun colour, hill colours (far to near), extra
GAMES = [
    ("Ashfall", "cinzel.ttf", "#1a0604", "#d2451c", "#ffd27a", ["#5a1408", "#2c0904", "#120302"], "embers"),
    ("Neon Drift", "bungee.ttf", "#12002b", "#ff2f8e", "#ffe14f", [], "synth"),
    ("Hollow Tide", "lora.ttf", "#03111f", "#1d6f8f", "#e9f6ff", [], "sea"),
    ("Orbitals", "exo2.ttf", "#05010f", "#3b1d7a", "#9be7ff", [], "planet"),
    ("Pixel Knights", "pressstart.ttf", "#0c2a4a", "#59b4e8", "#fff3b0", ["#2f7d3c", "#1e5a2a", "#0f3418"], "pixel"),
    ("Verdant", "pacifico.ttf", "#1e5f8a", "#f6c97f", "#fff6d8", ["#4e8f4a", "#2f6b33", "#173f1d"], "birds"),
    ("Iron Circuit", "rubikmono.ttf", "#0b1416", "#2c6e6a", "#7ff7e1", [], "city"),
    ("Last Lantern", "elite.ttf", "#07060a", "#3a2a18", "#ffbf4a", ["#1f170d"], "pines"),
]


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def scene(w, h, g, seed):
    title, font, top, bottom, sun, hills, extra = g
    rnd = random.Random(seed)
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    a, b = hexc(top), hexc(bottom)
    horizon = 0.62
    for y in range(h):
        d.line([(0, y), (w, y)], fill=mix(a, b, min(1.0, (y / h) / horizon) ** 1.4))
    if extra in ("stars", "planet", "grid", "synth", "city", "sea", "pines"):
        for _ in range(int(w * h / 2500)):
            x, y = rnd.randrange(w), rnd.randrange(int(h * horizon))
            v = rnd.randint(120, 255)
            d.point((x, y), fill=(v, v, v))
    # sun or moon, with a soft glow
    cx, cy, r = w * rnd.uniform(0.3, 0.7), h * horizon * rnd.uniform(0.55, 0.8), min(w, h) * 0.16
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse([cx - r * 2.2, cy - r * 2.2, cx + r * 2.2, cy + r * 2.2], fill=mix(hexc(sun), (0, 0, 0), 0.55))
    img = Image.composite(glow.filter(ImageFilter.GaussianBlur(r * 0.9)), img, glow.convert("L").filter(ImageFilter.GaussianBlur(r)).point(lambda v: v // 2))
    d = ImageDraw.Draw(img)
    if extra == "planet":
        cx, cy, r = w * 0.5, h * 0.95, min(w, h) * 0.55
        for k in range(30):  # banded gas giant
            t = k / 30
            d.chord([cx - r, cy - r, cx + r, cy + r], 180 + t * 180, 360 - t * 180 + 0.01, fill=mix(hexc(sun), hexc("#3b1d7a"), t * 0.8))
        d.ellipse([cx - r * 1.7, cy - r * 0.42, cx + r * 1.7, cy + r * 0.42], outline=hexc("#e8f8ff"), width=max(3, w // 160))
        d.ellipse([w * 0.78, h * 0.2, w * 0.78 + r * 0.18, h * 0.2 + r * 0.18], fill=hexc("#d9c8ff"))
    elif extra == "synth":
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=hexc(sun))
        for k in range(8):  # striped sun
            yy = cy + r * (k / 8 * 2 - 1)
            if k > 3:
                d.rectangle([cx - r, yy, cx + r, yy + r * 0.06 * (k - 3)], fill=hexc(bottom))
    else:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=hexc(sun))
    if extra == "synth":
        d.rectangle([0, int(h * horizon), w, h], fill=hexc("#140026"))
        extra = "grid"
    if extra == "grid":
        base = int(h * horizon)
        col = mix(hexc(sun), hexc(bottom), 0.3)
        for i in range(-20, 21):
            d.line([(w / 2 + i * w * 0.02, base), (w / 2 + i * w * 0.25, h)], fill=col, width=max(1, w // 400))
        y, step = base, 4.0
        while y < h:
            d.line([(0, y), (w, y)], fill=col, width=max(1, w // 400))
            step *= 1.35
            y += int(step)
    # layers of hills, far to near
    for li, hc in enumerate(hills):
        base = h * (horizon + li * 0.08)
        amp = h * (0.10 + li * 0.03)
        ph, fq = rnd.uniform(0, 6.28), rnd.uniform(1.5, 3.5)
        pts = [(0, h)]
        for x in range(0, w + 8, 8):
            t = x / w
            y = base - amp * (0.5 + 0.35 * math.sin(t * fq * math.pi + ph) + 0.15 * math.sin(t * fq * 3.1 * math.pi + ph * 2))
            if extra == "pixel":
                y = round(y / (h / 40)) * (h / 40)
            pts.append((x, y))
        pts.append((w, h))
        d.polygon(pts, fill=hexc(hc))
    if extra == "city":
        x = 0
        while x < w:
            bw2, bh = rnd.uniform(0.06, 0.14) * w, rnd.uniform(0.15, 0.55) * h
            d.rectangle([x, h - bh, x + bw2, h], fill=hexc("#0a1617"))
            for wy in range(int(h - bh + 10), h - 6, max(8, h // 60)):
                for wx in range(int(x + 6), int(x + bw2 - 6), max(8, w // 60)):
                    if rnd.random() < 0.3:
                        d.rectangle([wx, wy, wx + w // 160 + 1, wy + h // 220 + 1], fill=hexc(sun))
            x += bw2 + rnd.uniform(0, 0.02) * w
    if extra == "sea":
        base = int(h * horizon)
        d.rectangle([0, base, w, h], fill=hexc("#041826"))
        for yy in range(base, h, max(3, h // 120)):
            t = (yy - base) / (h - base)
            half = r * (0.4 + t * 1.4) * rnd.uniform(0.6, 1.0)
            d.line([(cx - half, yy), (cx + half, yy)], fill=mix(hexc(sun), hexc("#041826"), 0.35 + t * 0.4), width=max(1, h // 300))
    if extra == "pines":
        for li, col in enumerate(["#140f08", "#090604"]):
            for _ in range(int(w / 25)):
                x, ph = rnd.uniform(-0.05, 1.05) * w, rnd.uniform(0.18, 0.35) * h * (1 + li * 0.4)
                bot = h * (0.82 + li * 0.1)
                d.polygon([(x, bot - ph), (x - ph * 0.22, bot), (x + ph * 0.22, bot)], fill=hexc(col))
            d.rectangle([0, h * (0.82 + li * 0.1), w, h], fill=hexc(col))
        lx, ly = w * 0.62, h * 0.8
        gl = Image.new("L", (w, h), 0)
        ImageDraw.Draw(gl).ellipse([lx - w * 0.12, ly - w * 0.12, lx + w * 0.12, ly + w * 0.12], fill=200)
        img = Image.composite(Image.new("RGB", (w, h), hexc(sun)), img, gl.filter(ImageFilter.GaussianBlur(w * 0.05)).point(lambda v: v // 2))
        d = ImageDraw.Draw(img)
        d.rectangle([lx - w * 0.012, ly - w * 0.02, lx + w * 0.012, ly + w * 0.02], fill=hexc("#fff0c0"))
    if extra == "embers":
        for _ in range(int(w * h / 1800)):
            x, y = rnd.randrange(w), rnd.randrange(h)
            s = rnd.choice([1, 1, 2, 3])
            d.ellipse([x, y, x + s, y + s], fill=(255, rnd.randint(120, 210), 60))
    if extra == "birds":
        for _ in range(9):
            x, y, s = rnd.uniform(0.1, 0.9) * w, rnd.uniform(0.1, 0.4) * h, rnd.uniform(0.01, 0.02) * w
            d.line([(x - s, y - s * 0.4), (x, y), (x + s, y - s * 0.4)], fill=(30, 40, 50), width=max(2, w // 300))
    if extra == "pixel":
        img = img.resize((w // 12, h // 12), Image.NEAREST).resize((w, h), Image.NEAREST)
    return img


def title_text(img, g, size_frac, y_frac, shadow=True):
    w, h = img.size
    f = ImageFont.truetype(os.path.join(FONTS, g[1]), int(min(w, h * 1.4) * size_frac))
    d = ImageDraw.Draw(img)
    words = g[0].split() if w < h else [g[0]]
    lines = words
    ys = y_frac * h
    for line in lines:
        bw = d.textbbox((0, 0), line, font=f)
        while bw[2] - bw[0] > w * 0.88:
            f = ImageFont.truetype(os.path.join(FONTS, g[1]), int(f.size * 0.92))
            bw = d.textbbox((0, 0), line, font=f)
        tw, th = bw[2] - bw[0], bw[3] - bw[1]
        x = (w - tw) / 2 - bw[0]
        if shadow:
            sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
            ImageDraw.Draw(sh).text((x + 4, ys + 6), line, font=f, fill=(0, 0, 0, 170))
            img.paste(sh.filter(ImageFilter.GaussianBlur(6)), (0, 0), sh.filter(ImageFilter.GaussianBlur(6)))
        d.text((x, ys), line, font=f, fill=(255, 250, 240))
        ys += th * 1.25
    return img


def logo(g, w=800, h=300):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    f = ImageFont.truetype(os.path.join(FONTS, g[1]), int(h * 0.42))
    d = ImageDraw.Draw(img)
    bw = d.textbbox((0, 0), g[0], font=f)
    while bw[2] - bw[0] > w * 0.95:
        f = ImageFont.truetype(os.path.join(FONTS, g[1]), int(f.size * 0.9))
        bw = d.textbbox((0, 0), g[0], font=f)
    x, y = (w - (bw[2] - bw[0])) / 2 - bw[0], (h - (bw[3] - bw[1])) / 2 - bw[1]
    d.text((x + 3, y + 4), g[0], font=f, fill=(0, 0, 0, 160))
    d.text((x, y), g[0], font=f, fill=(255, 250, 240, 255))
    return img


def vdf(games):
    def s(k, v):
        return b"\x01" + k.encode() + b"\x00" + v.encode() + b"\x00"

    def i(k, v):
        return b"\x02" + k.encode() + b"\x00" + struct.pack("<I", v & 0xFFFFFFFF)

    out = b"\x00shortcuts\x00"
    for n, (appid, title, exe, last) in enumerate(games):
        out += b"\x00" + str(n).encode() + b"\x00"
        out += i("appid", appid) + s("AppName", title) + s("Exe", exe) + s("StartDir", "/") + s("LaunchOptions", "")
        out += i("LastPlayTime", last) + b"\x00tags\x00\x08" + b"\x08"
    return out + b"\x08\x08"


def main(home):
    steam = os.path.join(home, ".local/share/Steam")
    grid = os.path.join(steam, "userdata/10000001/config/grid")
    os.makedirs(grid, exist_ok=True)
    os.makedirs(os.path.join(steam, "steamapps"), exist_ok=True)
    entries = []
    now = 1798000000
    for n, g in enumerate(GAMES):
        exe = '"/opt/games/%s/run"' % g[0].lower().replace(" ", "-")
        appid = (zlib.crc32((exe + g[0]).encode()) | 0x80000000) & 0xFFFFFFFF
        entries.append((appid, g[0], exe, now - n * 86400 * 3))
        title_text(scene(600, 900, g, n), g, 0.16, 0.08).save(os.path.join(grid, "%dp.png" % appid))
        scene(1920, 620, g, n).save(os.path.join(grid, "%d_hero.png" % appid))
        title_text(scene(920, 430, g, n), g, 0.11, 0.08).save(os.path.join(grid, "%d.png" % appid))
        logo(g).save(os.path.join(grid, "%d_logo.png" % appid))
    with open(os.path.join(steam, "userdata/10000001/config/shortcuts.vdf"), "wb") as f:
        f.write(vdf(entries))
    # Non-Steam games show on Home only when pinned: put this in the PRESEED settings.
    print('"home_pinned": ' + str([str(e[0]) for e in entries]).replace("'", '"'))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "demo-home")
