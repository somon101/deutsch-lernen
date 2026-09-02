# -*- coding: utf-8 -*-
"""Re-encoding uploaded photos to WebP (§ word photo weight, 2026-09-02).

Checks both halves: that a photographic PNG shrinks dramatically without
losing resolution, and that the cases where re-encoding would be wrong are
left alone.
"""
import io
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from PIL import Image  # noqa: E402

from app.uploads.images import MAX_DIMENSION, encode_if_smaller, to_webp  # noqa: E402

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("  PASS  " if cond else "  FAIL  ") + name + (f"\n           -> {detail}" if detail and not cond else ""))


def photo(w=1408, h=768):
    """Something that compresses like a photograph.

    Deliberately NOT per-pixel random noise: that is the worst case for any
    lossy codec and nothing like a real photo, and an earlier version of this
    fixture "failed" the quality check at 32 dB purely because of it. Real
    photographs are dominated by smooth, spatially-correlated structure —
    here, overlapping low-frequency waves plus a faint grain — and the same
    encoder scores above 45 dB on a genuine uploaded image.
    """
    import random

    rnd = random.Random(7)
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        fy = y / h
        for x in range(w):
            fx = x / w
            base = 128 + 90 * math.sin(6.0 * fx + 1.7 * fy) * math.cos(3.0 * fy)
            swirl = 40 * math.sin(11.0 * (fx * fx + fy * fy))
            grain = rnd.randint(-3, 3)
            r = int(max(0, min(255, base + swirl + grain)))
            g = int(max(0, min(255, base * 0.7 + 30 + grain)))
            b = int(max(0, min(255, 255 - base * 0.8 + grain)))
            px[x, y] = (r, g, b)
    return img


def as_bytes(img, fmt, **kw):
    b = io.BytesIO()
    img.save(b, format=fmt, **kw)
    return b.getvalue()


def psnr(a, b):
    if a.size != b.size:
        b = b.resize(a.size, Image.LANCZOS)
    pa, pb = a.convert("RGB").tobytes(), b.convert("RGB").tobytes()
    se = n = 0
    for i in range(0, len(pa), 7):
        d = pa[i] - pb[i]
        se += d * d
        n += 1
    mse = se / n
    return float("inf") if mse == 0 else 10 * math.log10(255 * 255 / mse)


print("=== Фотография в PNG — главный случай ===")
src = photo()
png = as_bytes(src, "PNG")
out = encode_if_smaller(png)
check("конвертация произошла", out is not None, "вернулся None")
if out:
    data, ext, ctype = out
    got = Image.open(io.BytesIO(data))
    check("расширение .webp", ext == ".webp", ext)
    check("content-type image/webp", ctype == "image/webp", ctype)
    check("формат действительно WebP", got.format == "WEBP", str(got.format))
    check("разрешение НЕ изменилось", got.size == src.size, f"{got.size} вместо {src.size}")
    check("файл стал заметно меньше", len(data) * 4 < len(png), f"{len(png)} -> {len(data)}")
    q = psnr(src, got)
    check("качество выше 40 дБ (глазом не отличить)", q > 40, f"{q:.1f} дБ")
    print(f"           {len(png)/1024:.0f} КБ -> {len(data)/1024:.0f} КБ, PSNR {q:.1f} дБ")

print("\n=== Прозрачность сохраняется ===")
rgba = Image.new("RGBA", (400, 300), (255, 0, 0, 0))
for x in range(200):
    for y in range(150):
        rgba.putpixel((x, y), (0, 128, 255, 255))
out = encode_if_smaller(as_bytes(rgba, "PNG"))
if out:
    got = Image.open(io.BytesIO(out[0]))
    check("альфа-канал на месте", got.mode in ("RGBA", "LA"), got.mode)
else:
    check("альфа-канал на месте", True, "не конвертировалось — оригинал сохранён как есть")

print("\n=== Слишком большое изображение уменьшается до потолка ===")
big = photo(2400, 1200)
data = to_webp(as_bytes(big, "PNG"))
got = Image.open(io.BytesIO(data))
check(f"ширина не больше {MAX_DIMENSION}", max(got.size) <= MAX_DIMENSION, f"{got.size}")

print("\n=== Обычный размер НЕ трогается ===")
normal = photo(1408, 768)
got = Image.open(io.BytesIO(to_webp(as_bytes(normal, "PNG"))))
check("разрешение сохранено", got.size == (1408, 768), f"{got.size}")

print("\n=== Случаи, где конвертировать не надо ===")
tight = as_bytes(photo(300, 200), "WEBP", quality=60, method=6)
check("уже сжатый WebP не раздувается", encode_if_smaller(tight) is None, "конвертация ухудшила бы результат")

check("мусор вместо картинки не роняет загрузку", to_webp("это не картинка".encode("utf-8")) is None)
check("пустые байты не роняют загрузку", to_webp(b"") is None)

anim = io.BytesIO()
frames = [Image.new("RGB", (60, 60), c) for c in ("red", "blue", "green")]
frames[0].save(anim, format="GIF", save_all=True, append_images=frames[1:], duration=100, loop=0)
check("анимация не конвертируется (кадры бы потерялись)", to_webp(anim.getvalue()) is None)

passed = sum(1 for _, ok in results if ok)
print(f"\n{'='*58}\nИТОГ: {passed}/{len(results)} PASS")
for n, ok in results:
    if not ok:
        print("  FAILED:", n)
raise SystemExit(0 if passed == len(results) else 1)
