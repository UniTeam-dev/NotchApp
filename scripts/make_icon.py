from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageEnhance

S = 2048
PAD = int(S * 0.09)
BOX = S - PAD * 2
R = int(BOX * 0.2237)

CORAL = (255, 132, 68)     # оттенок Claude Code
BLUE = (64, 138, 255)      # цвет состояния «работает»
AMBER = (255, 170, 56)     # «ждёт разрешения»

NW = int(BOX * 0.58)
NH = int(BOX * 0.27)
CX = S // 2
TOP = PAD
TR = int(NH * 0.30)
BR = int(NH * 0.55)


def vertical_gradient(top, bottom):
    g = Image.new("RGB", (1, S))
    for y in range(S):
        t = y / (S - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((S, S))


def diagonal_gradient(c0, c1):
    g = Image.new("RGB", (S, S))
    px = g.load()
    for y in range(0, S, 4):
        for x in range(0, S, 4):
            t = x / S * 0.70 + y / S * 0.30
            c = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
            for dy in range(4):
                for dx in range(4):
                    if x + dx < S and y + dy < S:
                        px[x + dx, y + dy] = c
    return g


def notch_points(cx, top, w, h, top_r, bottom_r):
    """Тот же силуэт, что рисует NotchShape в приложении."""
    x0, x1 = cx - w / 2, cx + w / 2
    y1 = top + h
    pts = []

    def quad(p0, c, p1, steps=40):
        for i in range(steps + 1):
            t = i / steps
            u = 1 - t
            pts.append((u * u * p0[0] + 2 * u * t * c[0] + t * t * p1[0],
                        u * u * p0[1] + 2 * u * t * c[1] + t * t * p1[1]))

    pts.append((x0, top))
    quad((x0, top), (x0 + top_r, top), (x0 + top_r, top + top_r))
    pts.append((x0 + top_r, y1 - bottom_r))
    quad((x0 + top_r, y1 - bottom_r), (x0 + top_r, y1), (x0 + top_r + bottom_r, y1))
    pts.append((x1 - top_r - bottom_r, y1))
    quad((x1 - top_r - bottom_r, y1), (x1 - top_r, y1), (x1 - top_r, y1 - bottom_r))
    pts.append((x1 - top_r, top + top_r))
    quad((x1 - top_r, top + top_r), (x1 - top_r, top), (x1, top))
    return pts


def shape_mask(cx, top, w, h, top_r, bottom_r):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(notch_points(cx, top, w, h, top_r, bottom_r), fill=255)
    return m


base = vertical_gradient((24, 24, 30), (9, 9, 12))
gradient = diagonal_gradient(BLUE, CORAL)


def glow(scale_w, scale_h, drop, blur, strength):
    """Слой свечения. Смешивается экраном: чёрное остаётся чёрным,
    цвет не разбавляется фоном и не уходит в серый."""
    mask = shape_mask(CX, TOP - int(NH * 0.08),
                      int(NW * scale_w), int(NH * scale_h) + drop,
                      int(TR * scale_w), int(BR * scale_w))
    mask = mask.filter(ImageFilter.GaussianBlur(S * blur))
    mask = mask.point(lambda v: int(v * strength))
    layer = Image.new("RGB", (S, S), (0, 0, 0))
    layer.paste(gradient, (0, 0), mask)
    return layer


# Три слоя, от рассеянного к резкому. Широкий держим тусклым: если его
# поднять, он размазывается по всей плитке и цвет уходит в серый.
base = ImageChops.screen(base, glow(1.40, 1.75, int(BOX * 0.07), 0.048, 0.34))
base = ImageChops.screen(base, glow(1.13, 1.20, 0, 0.014, 0.85))
base = ImageChops.screen(base, glow(1.05, 1.08, 0, 0.005, 1.0))

# Мягкие края свечения после экранного смешения выцветают в лавандово-серый.
# Возвращаем насыщенность: чёрное остаётся чёрным, цвет становится цветом.
base = ImageEnhance.Color(base).enhance(1.9)
base = ImageEnhance.Contrast(base).enhance(1.12)

canvas = base.convert("RGBA")

# сам вырез поверх свечения
notch = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(notch).polygon(notch_points(CX, TOP, NW, NH, TR, BR), fill=(6, 6, 8, 255))
canvas = Image.alpha_composite(canvas, notch)

# точка состояния в правом крыле — подпись «кто-то ждёт»
halo = Image.new("RGB", (S, S), (0, 0, 0))
hd = ImageDraw.Draw(halo)
r = int(BOX * 0.024)
dcx = CX + NW / 2 + int(BOX * 0.070)
dcy = TOP + NH * 0.42
hd.ellipse([dcx - r * 2, dcy - r * 2, dcx + r * 2, dcy + r * 2], fill=AMBER)
halo = halo.filter(ImageFilter.GaussianBlur(S * 0.008))
canvas = Image.alpha_composite(
    ImageChops.screen(canvas.convert("RGB"), halo).convert("RGBA"),
    Image.new("RGBA", (S, S), (0, 0, 0, 0))
)
dot = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(dot).ellipse([dcx - r, dcy - r, dcx + r, dcy + r], fill=AMBER + (255,))
canvas = Image.alpha_composite(canvas, dot)

# кант
edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(edge).rounded_rectangle(
    [PAD, PAD, PAD + BOX, PAD + BOX], radius=R,
    outline=(255, 255, 255, 50), width=max(2, S // 400))
canvas = Image.alpha_composite(canvas, edge)

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([PAD, PAD, PAD + BOX, PAD + BOX], radius=R, fill=255)
canvas.putalpha(mask)
canvas.resize((1024, 1024), Image.LANCZOS).save("icon_1024.png")
print("готово")
