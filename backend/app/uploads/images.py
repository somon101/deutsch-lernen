"""Re-encoding uploaded photos to WebP (§ word photo weight, 2026-09-02).

The word photos were being stored exactly as uploaded, which meant PNG — a
format for flat-colour graphics, not photographs. One real upload measured
1408x768 and 825 KB, and took 3.2 s to fetch for a card that is at most 340
logical points wide.

The fix is the FORMAT, not the resolution. Re-encoded to WebP at quality 90
the same image is 23 KB — 36x smaller at 45.6 dB PSNR, which is well past
the point where a difference is visible. Resolution is left alone up to a
generous ceiling: a 340pt card on a 3x screen still wants ~1020 real pixels,
so downscaling to "thumbnail" sizes would be visible and is deliberately not
done.
"""

import io

from PIL import Image, ImageOps

# A 3x phone showing the 340pt card needs ~1020px. The ceiling sits above
# that so ordinary photos pass through untouched; only genuinely oversized
# uploads (a 4000px camera original) are brought down, and even then to a
# size that is still sharp on the densest screen.
MAX_DIMENSION = 1600

# 90 keeps the re-encode visually indistinguishable from the original. Lower
# values save little on top of what the format change already won.
WEBP_QUALITY = 90


def to_webp(content: bytes) -> bytes | None:
    """Returns WebP bytes, or None if this isn't an image we should touch.

    None is a "leave it exactly as uploaded" answer, never an error: an
    unreadable or animated file is stored unchanged rather than rejected,
    so a format Pillow doesn't handle can never cost a teacher their upload.
    """
    try:
        with Image.open(io.BytesIO(content)) as img:
            # Animated source (a GIF, an animated WebP): re-encoding would
            # silently drop every frame but the first.
            if getattr(img, "n_frames", 1) > 1:
                return None

            # Respects the EXIF orientation flag before it is discarded, so a
            # phone photo doesn't come out rotated.
            img = ImageOps.exif_transpose(img)

            # Keep alpha where it exists (cut-out illustrations rely on it),
            # drop palettes and exotic modes to something WebP can encode.
            img = img.convert("RGBA" if img.mode in ("RGBA", "LA", "PA") else "RGB")

            if max(img.size) > MAX_DIMENSION:
                img.thumbnail((MAX_DIMENSION, MAX_DIMENSION), Image.LANCZOS)

            out = io.BytesIO()
            img.save(out, format="WEBP", quality=WEBP_QUALITY, method=6)
            return out.getvalue()
    except Exception:
        return None


def encode_if_smaller(content: bytes) -> tuple[bytes, str, str] | None:
    """WebP bytes plus its extension and content type — but only when the
    result is actually smaller.

    An upload that is already a well-compressed WebP or a tight JPEG can come
    out BIGGER after a re-encode; storing that would be a loss twice over
    (more bytes and a generation of quality). In that case this returns None
    and the caller keeps the original.
    """
    encoded = to_webp(content)
    if encoded is None or len(encoded) >= len(content):
        return None
    return encoded, ".webp", "image/webp"
