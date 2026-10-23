"""픽셀 카드 텍스처 생성 (PIL). 실행: python3 tools/gen_textures.py  → assets/environment/"""
import random, math
from PIL import Image, ImageDraw

OUT = "assets/environment/"
random.seed(11)

def leaf_card(path, size=32, blobs=6):
    """둥근 잎 뭉치 실루엣. 중앙 밝음(255), 아래쪽 약간 어두움(205), 1px 어두운 테두리(150)."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    for i in range(blobs):
        r = random.uniform(size * 0.24, size * 0.32)
        cx = size * 0.5 + random.uniform(-size * 0.14, size * 0.14)
        cy = size * 0.5 + random.uniform(-size * 0.12, size * 0.12)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    px = im.load(); mp = mask.load()
    for y in range(size):
        for x in range(size):
            if mp[x, y] == 0:
                continue
            edge = any(0 <= x + dx < size and 0 <= y + dy < size and mp[x + dx, y + dy] == 0
                       or not (0 <= x + dx < size and 0 <= y + dy < size)
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if edge:
                c = 232
            else:
                c = 255
            px[x, y] = (c, c, c, 255)
    im.save(OUT + path)

def grass_card(path, w=32, h=16, blades=9):
    """풀 잎 여러 가닥, 아래 밝고 끝 약간 어두움."""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    for i in range(blades):
        x0 = random.randint(1, w - 2)
        bh = random.randint(int(h * 0.45), h - 1)
        lean = random.choice((-2, -1, 0, 1, 2))
        for y in range(bh):
            x = x0 + int(round(lean * y / max(bh - 1, 1)))
            yy = h - 1 - y
            if 0 <= x < w:
                c = 255 if y < bh * 0.6 else 210
                px[x, yy] = (c, c, c, 255)
                if y < bh * 0.3 and x + 1 < w:
                    px[x + 1, yy] = (c, c, c, 255)
    im.save(OUT + path)

def flower(path, size=8):
    """작은 꽃 스프라이트: 꽃잎 5점 + 줄기. 흰색 → 셰이더 base_color 로 착색."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    for (x, y) in ((3, 1), (2, 2), (4, 2), (3, 3), (3, 2)):
        px[x, y] = (255, 255, 255, 255)
    px[3, 2] = (235, 225, 120, 255)  # 꽃술
    for y in (4, 5, 6, 7):
        px[3, y] = (120, 170, 90, 255)
    px[2, 5] = (120, 170, 90, 255)
    im.save(OUT + path)

def leaf_tri_card(path, size=32, tris=4):
    """위로 뾰족한 삼각형 잎 뭉치. 가장자리 1px 약간 어둡게."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    for i in range(tris):
        w = random.uniform(size * 0.30, size * 0.46)
        h = random.uniform(size * 0.55, size * 0.85)
        cx = size * 0.5 + random.uniform(-size * 0.16, size * 0.16)
        base_y = size * 0.5 + h * 0.5 + random.uniform(-size * 0.08, size * 0.08)
        lean = random.uniform(-size * 0.08, size * 0.08)
        d.polygon([(cx + lean, base_y - h), (cx - w * 0.5, base_y), (cx + w * 0.5, base_y)], fill=255)
    px = im.load(); mp = mask.load()
    for y in range(size):
        for x in range(size):
            if mp[x, y] == 0:
                continue
            edge = any(not (0 <= x + dx < size and 0 <= y + dy < size) or mp[x + dx, y + dy] == 0
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            c = 228 if edge else 255
            px[x, y] = (c, c, c, 255)
    im.save(OUT + path)

random.seed(3); leaf_tri_card("leaf_card_tri.png")
random.seed(11); leaf_card("leaf_card.png", blobs=4)
random.seed(5); leaf_card("leaf_card_b.png", blobs=3)
random.seed(21); grass_card("grass_card.png")
flower("flower.png")
print("textures written")
