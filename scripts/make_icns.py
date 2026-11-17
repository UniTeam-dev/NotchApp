"""Собирает .icns из одного PNG 1024x1024.

iconutil есть только на macOS, поэтому пишем контейнер руками: формат простой —
заголовок 'icns' с общей длиной, дальше подряд блоки «тип + длина + PNG».
"""
import struct
from PIL import Image

SRC = "icon_1024.png"
OUT = "AppIcon.icns"

# тип блока -> сторона квадрата в пикселях
ENTRIES = [
    (b"icp4", 16),
    (b"icp5", 32),
    (b"ic11", 32),    # 16@2x
    (b"ic12", 64),    # 32@2x
    (b"ic07", 128),
    (b"ic13", 256),   # 128@2x
    (b"ic08", 256),
    (b"ic14", 512),   # 256@2x
    (b"ic09", 512),
    (b"ic10", 1024),  # 512@2x
]

source = Image.open(SRC).convert("RGBA")
blocks = []

for kind, size in ENTRIES:
    import io
    buffer = io.BytesIO()
    source.resize((size, size), Image.LANCZOS).save(buffer, format="PNG")
    data = buffer.getvalue()
    blocks.append(kind + struct.pack(">I", len(data) + 8) + data)

body = b"".join(blocks)
with open(OUT, "wb") as handle:
    handle.write(b"icns" + struct.pack(">I", len(body) + 8) + body)

print(f"{OUT}: {len(body) + 8} байт, {len(ENTRIES)} размеров")
