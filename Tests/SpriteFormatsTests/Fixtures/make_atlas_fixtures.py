# Generates libGDX/Spine and Aseprite fixtures: python3 make_atlas_fixtures.py <Fixtures dir>
import zlib, struct, sys, os, json
out = sys.argv[1]

def png(path, w, h, px):
    raw = b''.join(b'\x00' + b''.join(bytes(px[y][x]) for x in range(w)) for y in range(h))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
                          + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))

CLEAR, RED, GREEN, BLUE, YELLOW = [0,0,0,0], [255,0,0,255], [0,255,0,255], [0,0,255,255], [255,255,0,255]

# --- libGDX page (64x32) ---
W, H = 64, 32
page = [[CLEAR] * W for _ in range(H)]
# "arrow" is 8x16: green 2x2 marker top-left, red top half, blue bottom half; packed rotated CCW at (2,2) as 16x8.
def arrow(x, y):
    if x < 2 and y < 2: return GREEN
    return RED if y < 8 else BLUE
AW, AH = 8, 16
for sy in range(AW):
    for sx in range(AH):
        page[2 + sy][2 + sx] = arrow(AW - 1 - sy, sx)
# "trimmed": original 16x12, content 6x4 yellow at left 3, top 2; packed at (20,2) as 6x4.
for y in range(4):
    for x in range(6):
        page[2 + y][20 + x] = YELLOW
# "walk" frames index 0 and 1: 4x4 red at (30,2) and 4x4 blue at (36,2).
for y in range(4):
    for x in range(4):
        page[2 + y][30 + x] = RED
        page[2 + y][36 + x] = BLUE
png(os.path.join(out, 'LibGDX', 'page.png'), W, H, page)

legacy = """
page.png
size: 64,32
format: RGBA8888
filter: Nearest,Nearest
repeat: none
arrow
  rotate: true
  xy: 2, 2
  size: 8, 16
  orig: 8, 16
  offset: 0, 0
  index: -1
trimmed
  rotate: false
  xy: 20, 2
  size: 6, 4
  orig: 16, 12
  offset: 3, 6
  index: -1
walk
  rotate: false
  xy: 30, 2
  size: 4, 4
  orig: 4, 4
  offset: 0, 0
  index: 0
walk
  rotate: false
  xy: 36, 2
  size: 4, 4
  orig: 4, 4
  offset: 0, 0
  index: 1
"""
current = """page.png
\tsize: 64, 32
\tfilter: Nearest, Nearest
arrow
\tbounds: 2, 2, 8, 16
\trotate: 90
trimmed
\tbounds: 20, 2, 6, 4
\toffsets: 3, 6, 16, 12
walk
\tindex: 0
\tbounds: 30, 2, 4, 4
walk
\tindex: 1
\tbounds: 36, 2, 4, 4
"""
open(os.path.join(out, 'LibGDX', 'legacy.atlas'), 'w').write(legacy)
open(os.path.join(out, 'LibGDX', 'current.atlas'), 'w').write(current)

# --- Aseprite sheet (24x8): frames red, green, trimmed blue (4x4 content at 2,2 of 8x8) ---
sheet = [[CLEAR] * 24 for _ in range(8)]
for y in range(8):
    for x in range(8):
        sheet[y][x] = RED
        sheet[y][8 + x] = GREEN
for y in range(4):
    for x in range(4):
        sheet[y][16 + x] = BLUE
png(os.path.join(out, 'Aseprite', 'hero.png'), 24, 8, sheet)

def frame(fx, fy, w, h, sx, sy, dur):
    return {"frame": {"x": fx, "y": fy, "w": w, "h": h}, "rotated": False, "trimmed": (w, h) != (8, 8),
            "spriteSourceSize": {"x": sx, "y": sy, "w": w, "h": h}, "sourceSize": {"w": 8, "h": 8}, "duration": dur}
frames = [("hero 0.aseprite", frame(0, 0, 8, 8, 0, 0, 100)),
          ("hero 1.aseprite", frame(8, 0, 8, 8, 0, 0, 150)),
          ("hero 2.aseprite", frame(16, 0, 4, 4, 2, 2, 200))]
meta = {"app": "https://www.aseprite.org/", "version": "1.3", "image": "hero.png", "format": "RGBA8888",
        "size": {"w": 24, "h": 8}, "scale": "1",
        "frameTags": [{"name": "walk", "from": 0, "to": 2, "direction": "pingpong", "color": "#000000ff"},
                      {"name": "blink", "from": 1, "to": 2, "direction": "reverse", "repeat": "3", "color": "#000000ff"}],
        "layers": [], "slices": [{"name": "panel", "color": "#0000ffff",
                                  "keys": [{"frame": 0, "bounds": {"x": 0, "y": 0, "w": 8, "h": 8},
                                            "center": {"x": 2, "y": 2, "w": 4, "h": 4}, "pivot": {"x": 4, "y": 8}}]}]}
# Hash layout with keys deliberately out of order.
hashed = {"frames": {name: f for name, f in [frames[2], frames[0], frames[1]]}, "meta": meta}
arrayed = {"frames": [dict(f, filename=name) for name, f in frames], "meta": meta}
json.dump(hashed, open(os.path.join(out, 'Aseprite', 'hero-hash.json'), 'w'), indent=1)
json.dump(arrayed, open(os.path.join(out, 'Aseprite', 'hero-array.json'), 'w'), indent=1)
