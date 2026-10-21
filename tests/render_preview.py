#!/usr/bin/env python3
"""Compose preview.png: a few effects caught mid-animation beside the panel.
Renders the shipped shaders on a synthetic terminal window, like render_shaders.py,
and lays the stills over a wallpaper. Requires Mesa EGL (surfaceless ES 3.2) and Pillow.

  python3 tests/render_preview.py --wallpaper wall.jpg --panel panel.png --output preview.png
"""
import argparse
import ctypes as C
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
import render_shaders as R

SHADERS = Path(__file__).parents[1] / 'shaders'
W, H = 440, 300
BOX = (46, 34, 394, 266)
# (effect, progress, caption): chosen so each is easy to recognise in a still.
TILES = [('shatter', 0.50, 'Shatter'), ('explode', 0.30, 'Explode'), ('matrix', 0.45, 'Matrix'),
         ('blinds', 0.50, 'Blinds'), ('glitch', 0.60, 'Glitch'), ('build', 0.55, 'Build')]
GREEN, TEXT, MUTED = '#5fd7a0', '#e8eaf6', '#9aa5c9'


def window_texture():
    image = Image.new('RGBA', (W, H))
    d = ImageDraw.Draw(image)
    d.rounded_rectangle(BOX, 8, fill='#15161f', outline='#7aa2f7', width=2)
    d.rectangle((BOX[0] + 2, BOX[1] + 26, BOX[2] - 2, BOX[1] + 27), fill='#2c3047')
    for i, color in enumerate(['#f7768e', '#e0af68', '#9ece6a']):
        d.ellipse((BOX[0] + 12 + i * 16, BOX[1] + 9, BOX[0] + 20 + i * 16, BOX[1] + 17), fill=color)
    colors = ['#7aa2f7', '#9ece6a', '#bb9af7', '#e0af68', '#7dcfff']
    widths = [0.62, 0.8, 0.45, 0.7, 0.55, 0.85, 0.4, 0.66, 0.5, 0.74, 0.58]
    for i, fraction in enumerate(widths):
        y = BOX[1] + 42 + i * 16
        d.rectangle((BOX[0] + 16, y, BOX[0] + 16 + int(300 * fraction), y + 6), fill=colors[i % len(colors)])
    return image


def render(source, window, progress, seed=0.37):
    prog = R.program(source)
    gl, U, I, F = R.gl, R.U, R.I, R.F
    gl('glUseProgram', None, U)(prog)

    def loc(name):
        return gl('glGetUniformLocation', I, U, C.c_char_p)(prog, name.encode())
    gl('glUniform1i', None, I, I)(loc('tex'), 0)
    gl('glUniform1f', None, I, F)(loc('seed'), seed)
    gl('glUniform2f', None, I, F, F)(loc('surface_size'), W, H)
    gl('glUniform4f', None, I, F, F, F, F)(loc('window_rect'), BOX[0] / W, BOX[1] / H,
                                           (BOX[2] - BOX[0]) / W, (BOX[3] - BOX[1]) / H)
    gl('glUniform1f', None, I, F)(loc('progress'), progress)
    gl('glDrawArrays', None, U, I, I)(0x0004, 0, 3)
    pixels = (C.c_ubyte * (W * H * 4))()
    gl('glReadPixels', None, I, I, I, I, U, U, R.P)(0, 0, W, H, 0x1908, 0x1401, pixels)
    return Image.frombytes('RGBA', (W, H), bytes(pixels))


def over(background, premultiplied):
    # The shaders output premultiplied colour: result = colour + background * (1 - alpha).
    out = Image.new('RGB', premultiplied.size)
    out.putdata([(min(255, r + round(br * (1 - a / 255))), min(255, g + round(bg * (1 - a / 255))),
                  min(255, b + round(bb * (1 - a / 255))))
                 for (r, g, b, a), (br, bg, bb) in zip(premultiplied.getdata(), background.getdata())])
    return out


def gradient(size):
    image = Image.new('RGB', size, '#0e0f19')
    d = ImageDraw.Draw(image)
    for x in range(size[0]):
        t = x / size[0]
        d.line((x, 0, x, size[1]), fill=(int(14 + 10 * t), int(15 + 6 * t), int(25 + 14 * t)))
    return image


def font(name, size):
    return ImageFont.truetype('/usr/share/fonts/TTF/JetBrainsMonoNerdFont-%s.ttf' % name, size)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--wallpaper', type=Path, required=True)
    parser.add_argument('--panel', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('preview.png'))
    args = parser.parse_args()
    R.context(W, H)
    texture = window_texture()
    tex = R.U()
    R.gl('glGenTextures', None, R.I, C.POINTER(R.U))(1, C.byref(tex))
    R.gl('glBindTexture', None, R.U, R.U)(0x0DE1, tex.value)
    for name, value in [(0x2801, 0x2600), (0x2800, 0x2600), (0x2802, 0x812F), (0x2803, 0x812F)]:
        R.gl('glTexParameteri', None, R.U, R.U, R.I)(0x0DE1, name, value)
    buffer = C.create_string_buffer(texture.tobytes())
    R.gl('glTexImage2D', None, R.U, R.I, R.I, R.I, R.I, R.I, R.U, R.U, R.P)(0x0DE1, 0, 0x1908, W, H, 0, 0x1908, 0x1401, buffer)
    R.gl('glViewport', None, R.I, R.I, R.I, R.I)(0, 0, W, H)
    R.gl('glDisable', None, R.U)(0x0BE2)
    vao = R.U()
    R.gl('glGenVertexArrays', None, R.I, C.POINTER(R.U))(1, C.byref(vao))
    R.gl('glBindVertexArray', None, R.U)(vao)

    wallpaper = Image.open(args.wallpaper).convert('RGB')
    scale = max(W / wallpaper.width, H / wallpaper.height)
    wallpaper = wallpaper.resize((round(wallpaper.width * scale), round(wallpaper.height * scale)), Image.LANCZOS)
    left, top = (wallpaper.width - W) // 2, (wallpaper.height - H) // 2
    wallpaper = wallpaper.crop((left, top, left + W, top + H))

    card = gradient((1280, 720))
    d = ImageDraw.Draw(card)
    left = 48
    d.text((left, 92), 'WinFX', font=font('Bold', 88), fill=TEXT)
    d.text((left + 2, 214), 'Open and close effects\nfor Omarchy windows', font=font('Regular', 24), fill=MUTED, spacing=10)
    d.text((left + 2, 318), '10 EFFECTS', font=font('Bold', 20), fill=GREEN)
    body = font('Regular', 19)
    lines = [('Crumble, Shatter, Dissolve,', ''), ('Pixelate, Explode, Build,', ''), ('Blinds, Glitch, TV, Matrix', ''), None,
             ('Effects sync, ', 'or 1 each way'), ('Opening ', 'plays them in reverse'),
             ('Size, duration, ', 'and test window')]
    y = 358
    for line in lines:
        if line is None:
            y += 14
            continue
        strong, soft = line
        d.text((left + 2, y), strong, font=body, fill=TEXT)
        if soft:
            d.text((left + 2 + d.textlength(strong, font=body), y), soft, font=body, fill=TEXT)
        y += 31

    tile_w, tile_h = 244, 166
    for i, (effect, progress, caption) in enumerate(TILES):
        still = over(wallpaper, render((SHADERS / (effect + '.glsl')).read_text(), texture, progress))
        still = still.resize((tile_w, tile_h), Image.LANCZOS)
        x = 430 + (i % 2) * (tile_w + 16)
        y = 54 + (i // 2) * (tile_h + 52)
        d.text((x, y - 28), caption.upper(), font=font('Bold', 18), fill=GREEN)
        card.paste(still, (x, y))
        d.rounded_rectangle((x - 1, y - 1, x + tile_w, y + tile_h), 4, outline='#2a2d44', width=1)

    panel = Image.open(args.panel).convert('RGB')
    height = 620
    panel = panel.resize((round(panel.width * height / panel.height), height), Image.LANCZOS)
    px = 1280 - panel.width - 36
    d.text((px, 14), 'PANEL', font=font('Bold', 18), fill=GREEN)
    # Round the corners so the screenshot's own backdrop does not show.
    mask = Image.new('L', panel.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, panel.width - 1, panel.height - 1), 14, fill=255)
    card.paste(panel, (px, 52), mask)
    card.save(args.output)
    print('Saved', args.output, card.size)


if __name__ == '__main__':
    main()
