"""Drawn national flags for the SNI tray (ARGB32 network byte order)."""
# Canvas: 41x16 (21x14 inner flag + 10pt side pad + 1px top/bottom).
WIDTH, HEIGHT = 41, 16
FLAG_W, FLAG_H = 21, 14
PAD_X, PAD_Y = 10, 1

WHITE = (255, 255, 255, 255)
RED = (255, 200, 16, 46)          # US stripes / RU bottom
BLUE = (255, 0, 51, 153)          # RU middle
NAVY = (255, 0, 40, 104)          # US canton
CLEAR = (0, 0, 0, 0)


def _pixel(color):
    a, r, g, b = color
    return bytes((a, r, g, b))


def _fill(buf, x0, y0, x1, y1, color):
    row = _pixel(color) * max(0, x1 - x0)
    for y in range(max(0, y0), min(HEIGHT, y1)):
        start = (y * WIDTH + max(0, x0)) * 4
        buf[start:start + len(row)] = row


def _draw_us(buf):
    x0, y0 = PAD_X, PAD_Y
    # 7 red bands on white (13 stripes simplified to fit 14px).
    for i in range(7):
        top = y0 + i * 2
        _fill(buf, x0, top, x0 + FLAG_W, top + 2, RED if i % 2 == 0 else WHITE)
    # Canton covers left 42% x top 50%.
    cw = max(1, FLAG_W * 42 // 100)
    ch = max(1, FLAG_H * 50 // 100)
    _fill(buf, x0, y0, x0 + cw, y0 + ch, NAVY)
    # 3x4 white dots in the canton.
    for row in range(4):
        for col in range(3):
            px = x0 + 1 + col * max(1, (cw - 2) // 3)
            py = y0 + 1 + row * max(1, (ch - 2) // 4)
            _fill(buf, px, py, px + 1, py + 1, WHITE)


def _draw_ru(buf):
    x0, y0 = PAD_X, PAD_Y
    band = FLAG_H // 3
    _fill(buf, x0, y0, x0 + FLAG_W, y0 + band, WHITE)
    _fill(buf, x0, y0 + band, x0 + FLAG_W, y0 + 2 * band, BLUE)
    _fill(buf, x0, y0 + 2 * band, x0 + FLAG_W, y0 + FLAG_H, RED)


def label(source_id):
    """ISO-ish flag id from a GNOME source_id."""
    if source_id in ('us', 'en'):
        return 'us'
    if source_id in ('ru',):
        return 'ru'
    return '?'


def pixmap(flag):
    """ARGB32 big-endian bytes for the status item, or None for unknown."""
    buf = bytearray(WIDTH * HEIGHT * 4)
    if flag == 'us':
        _draw_us(buf)
    elif flag == 'ru':
        _draw_ru(buf)
    else:
        return None
    return [(WIDTH, HEIGHT, bytes(buf))]


def menu_pixmap(flag):
    """Scaled-up badge for the menu header icon-data."""
    base = pixmap(flag)
    if base is None:
        return None
    w, h, data = base[0]
    scale = 2
    out = bytearray(w * h * scale * scale * 4)
    out_w = w * scale
    for y in range(h):
        for x in range(w):
            pixel = data[(y * w + x) * 4:(y * w + x + 1) * 4]
            block = pixel * scale
            for dy in range(scale):
                start = ((y * scale + dy) * out_w + x * scale) * 4
                out[start:start + len(block)] = block
    return [(out_w, h * scale, bytes(out))]


def status_title(flag, display_layout_flag, running):
    """Text fallback when the pixmap is hidden or unknown."""
    if not running:
        return '✕'
    if not display_layout_flag:
        return '•'
    return {'us': '🇺🇸', 'ru': '🇷🇺'}.get(flag, '?')
