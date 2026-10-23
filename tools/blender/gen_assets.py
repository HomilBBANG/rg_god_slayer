"""
RED 환경 에셋 생성 — Blender 헤드리스 스크립트
    blender -b -P tools/blender/gen_assets.py -- assets/environment

레퍼런스(t3ssel8r 풍 3D 픽셀아트)에 맞춘 저폴리 에셋을 절차적으로 만들어 glTF(.glb)로 내보낸다.
  tree_a/b.glb      줄기 + 구형 볼륨 표면에 뿌린 잎 카드(카드 노멀 = 볼륨 노멀 → 덩어리 하나처럼 2톤 음영)
  rock_a/b/c/d.glb  노이즈 변위 이코스피어, 플랫 셰이딩, 바닥 평평
  bush_a/b.glb      납작한 둔덕 + 가장자리 풀 카드
  pillar_a/b.glb    깎인 돌 블록을 쌓은 폐허 기둥
  block_a/b.glb     흩어진 돌 블록
카드는 카메라가 고정(고도 52°, 방위 45°)이므로 카메라를 향하도록 미리 회전해 둔다.
glTF 머티리얼 이름(Leaf/Bark/Rock/Stone/GrassCard/Bush)을 Godot 쪽에서 셰이더 머티리얼로 치환한다.
"""
import bpy, bmesh, sys, math, random
from mathutils import Vector, Matrix, noise

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/environment"

# Godot 카메라 시선 (x, y-up, z) = (-0.435, -0.788, -0.435) → Blender(z-up): (x, -z, y)
CAM_DIR = Vector((-0.435, 0.435, -0.788)).normalized()
CARD_NORMAL = -CAM_DIR  # 카드가 카메라를 마주보는 방향


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
    return m


def mesh_object(name, verts, faces, mat_name, uvs=None, custom_normals=None, smooth=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    me.materials.append(material(mat_name))
    for p in me.polygons:
        p.use_smooth = smooth
    if uvs is not None:
        uv = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            for li in poly.loop_indices:
                vi = me.loops[li].vertex_index
                uv.data[li].uv = uvs[vi]
    if custom_normals is not None:
        me.use_auto_smooth = True
        me.normals_split_custom_set_from_vertices([Vector(n).normalized() for n in custom_normals])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def card_basis(roll, tilt):
    """카메라를 향하는 쿼드의 (right, up) 축. roll: 카드 평면 내 회전, tilt: 법선 흔들림."""
    n = CARD_NORMAL.copy()
    # 임의 축으로 살짝 기울임
    axis = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))).normalized()
    n = (Matrix.Rotation(tilt, 4, axis) @ n).normalized()
    up0 = Vector((0, 0, 1))
    right = up0.cross(n).normalized()
    up = n.cross(right).normalized()
    rot = Matrix.Rotation(roll, 4, n)
    return (rot @ right).normalized(), (rot @ up).normalized()


def add_cards(verts, faces, uvs, normals, center, size, normal, roll=None, tilt=0.35, aspect=1.0, roll_range=math.pi):
    """center 에 size 크기의 카메라향 쿼드 1장 추가. normal = 조명용 커스텀 노멀."""
    if roll is None:
        roll = random.uniform(-roll_range, roll_range)
    r, u = card_basis(roll, random.uniform(-tilt, tilt))
    hw, hh = size * 0.5, size * 0.5 * aspect
    i = len(verts)
    verts += [center - r * hw - u * hh, center + r * hw - u * hh, center + r * hw + u * hh, center - r * hw + u * hh]
    faces.append((i, i + 1, i + 2, i + 3))
    uvs += [(0, 1), (1, 1), (1, 0), (0, 0)]
    normals += [normal] * 4


def poisson_thin(points, min_dist):
    kept = []
    cell = min_dist
    grid = {}
    for p in points:
        key = (int(p.x // cell), int(p.y // cell), int(p.z // cell))
        ok = True
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for q in grid.get((key[0] + dx, key[1] + dy, key[2] + dz), ()):
                        if (p - q).length < min_dist:
                            ok = False
                            break
                    if not ok:
                        break
                if not ok:
                    break
            if not ok:
                break
        if ok:
            kept.append(p)
            grid.setdefault(key, []).append(p)
    return kept


# ------------------------------------------------------------------ 나무

def canopy_sdf(p, spheres):
    """smooth-min 구 합집합 SDF 와 그 그래디언트 근사 노멀"""
    k = 0.6
    d = 1e9
    for c, r in spheres:
        di = (p - c).length - r
        # polynomial smooth min
        h = max(k - abs(d - di), 0.0) / k
        d = min(d, di) - h * h * k * 0.25
    return d


def canopy_normal(p, spheres):
    e = 0.05
    dx = canopy_sdf(p + Vector((e, 0, 0)), spheres) - canopy_sdf(p - Vector((e, 0, 0)), spheres)
    dy = canopy_sdf(p + Vector((0, e, 0)), spheres) - canopy_sdf(p - Vector((0, e, 0)), spheres)
    dz = canopy_sdf(p + Vector((0, 0, e)), spheres) - canopy_sdf(p - Vector((0, 0, e)), spheres)
    n = Vector((dx, dy, dz))
    return n.normalized() if n.length > 1e-6 else Vector((0, 0, 1))


def make_tree(name, seed, height=1.7, spheres=None, card_size=(0.95, 1.3), shell=(-0.55, 0.05), min_dist=0.5, inner=70, roll_range=0.45):
    random.seed(seed)
    # 줄기: 7각 테이퍼 실린더, 살짝 기울임
    bm = bmesh.new()
    segs = 7
    r0, r1 = 0.26, 0.16
    lean = Vector((random.uniform(-0.15, 0.15), random.uniform(-0.15, 0.15), 0))
    ring0 = [bm.verts.new((math.cos(a) * r0, math.sin(a) * r0, 0.0)) for a in [i / segs * math.tau for i in range(segs)]]
    ring1 = [bm.verts.new((math.cos(a) * r1 + lean.x, math.sin(a) * r1 + lean.y, height)) for a in [i / segs * math.tau for i in range(segs)]]
    for i in range(segs):
        bm.faces.new((ring0[i], ring0[(i + 1) % segs], ring1[(i + 1) % segs], ring1[i]))
    bm.faces.new(ring1)
    # 뿌리 혹 2개
    for _ in range(2):
        a = random.uniform(0, math.tau)
        base = Vector((math.cos(a) * r0 * 0.9, math.sin(a) * r0 * 0.9, 0.0))
        bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.16, radius2=0.05, depth=0.5,
                              matrix=Matrix.Translation(base + Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, 0.12))) @ Matrix.Rotation(math.radians(70), 4, Vector((-math.sin(a), math.cos(a), 0))))
    me = bpy.data.meshes.new(name + "_trunk")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material("Bark"))
    trunk = bpy.data.objects.new(name + "_trunk", me)
    bpy.context.scene.collection.objects.link(trunk)

    # 잎 카드
    if spheres is None:
        # 원뿔형: 위로 갈수록 작은 구를 쌓아 뾰족한 실루엣 (삼각형 카드와 어울림)
        top = height + 1.5
        spheres = [
            (Vector((0.0, 0.0, top)), 1.7),
            (Vector((0.55, 0.25, top - 0.2)), 1.25),
            (Vector((-0.6, -0.3, top - 0.1)), 1.2),
            (Vector((0.1, 0.0, top + 1.3)), 1.15),
            (Vector((-0.1, 0.1, top + 2.4)), 0.75),
            (Vector((0.0, 0.0, top + 3.1)), 0.4),
        ]
    verts, faces, uvs, normals = [], [], [], []
    cand = []
    for _ in range(9000):
        p = Vector((random.uniform(-3.4, 3.4), random.uniform(-3.4, 3.4), random.uniform(height - 0.3, height + 5.4)))
        d = canopy_sdf(p, spheres)
        if shell[0] <= d <= shell[1]:
            cand.append(p)
    pts = poisson_thin(cand, min_dist)
    for p in pts:
        n = canopy_normal(p, spheres)
        add_cards(verts, faces, uvs, normals, p, random.uniform(*card_size), n, roll_range=roll_range)
    # 안쪽 채움 카드 (실루엣 구멍 방지)
    inner_pts = [p for p in cand if canopy_sdf(p, spheres) < shell[0] + 0.1][:inner]
    for p in inner_pts:
        add_cards(verts, faces, uvs, normals, p, random.uniform(*card_size), canopy_normal(p, spheres), roll_range=roll_range)
    leaves = mesh_object(name + "_leaves", verts, faces, "Leaf", uvs, normals)
    leaves.parent = trunk
    return trunk


# ------------------------------------------------------------------ 바위

def make_rock(name, seed, scale=(1.0, 0.8, 0.7), subdiv=2, amp=0.28, freq=1.6):
    random.seed(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    off = Vector((random.uniform(0, 50), random.uniform(0, 50), random.uniform(0, 50)))
    for v in bm.verts:
        n = noise.noise((v.co * freq) + off)
        n2 = noise.noise((v.co * freq * 2.3) + off * 1.7) * 0.4
        v.co = v.co * (1.0 + amp * (n + n2))
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    # 바닥 평평하게 + 약간 묻힘
    zmin = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z = max(v.co.z, zmin * 0.55) - zmin * 0.55 - 0.08
    # 큰 면만 남도록 약간 디시메이트 느낌: dissolve 작은 각도
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(14), verts=bm.verts, edges=bm.edges)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(material("Rock"))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ------------------------------------------------------------------ 덤불 둔덕

def make_bush(name, seed, radius=1.1, height=0.55, cards=52):
    random.seed(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    off = Vector((random.uniform(0, 50), random.uniform(0, 50), 0))
    for v in bm.verts:
        n = noise.noise(v.co * 1.8 + off)
        v.co = v.co * (1.0 + 0.16 * n)
        v.co.x *= radius
        v.co.y *= radius * random.uniform(0.95, 1.05)
        v.co.z = v.co.z * height
    for v in bm.verts:
        v.co.z = max(v.co.z, -0.05)
    me = bpy.data.meshes.new(name + "_mound")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(material("Bush"))
    mound = bpy.data.objects.new(name + "_mound", me)
    bpy.context.scene.collection.objects.link(mound)
    # 가장자리 풀 카드: 둔덕 테두리를 따라, 노멀은 위
    verts, faces, uvs, normals = [], [], [], []
    for i in range(cards):
        a = i / cards * math.tau + random.uniform(-0.1, 0.1)
        rr = radius * random.uniform(0.75, 1.05)
        p = Vector((math.cos(a) * rr, math.sin(a) * rr, height * 0.35 * random.uniform(0.4, 1.0)))
        add_cards(verts, faces, uvs, normals, p, random.uniform(0.6, 0.9), Vector((0, 0, 1)), roll=random.uniform(-0.15, 0.15), tilt=0.15, aspect=0.55)
    rim = mesh_object(name + "_rim", verts, faces, "GrassCard", uvs, normals)
    rim.parent = mound
    return mound


# ------------------------------------------------------------------ 돌 기둥 / 블록

def chipped_block(bm, size, center, chip=0.12):
    """베벨 느낌의 깎인 육면체: 꼭짓점을 안쪽으로 랜덤 이동"""
    ret = bmesh.ops.create_cube(bm, size=1.0)
    vs = ret["verts"]
    for v in vs:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if random.random() < 0.35:
            v.co.x -= math.copysign(random.uniform(0, chip), v.co.x)
            v.co.y -= math.copysign(random.uniform(0, chip), v.co.y)
            v.co.z -= math.copysign(random.uniform(0, chip * 0.7), v.co.z)
        v.co += center
    return vs


def make_pillar(name, seed, blocks=5, broken_top=True):
    random.seed(seed)
    bm = bmesh.new()
    chipped_block(bm, (1.1, 1.1, 0.3), Vector((0, 0, 0.15)), chip=0.08)
    z = 0.3
    for i in range(blocks):
        h = random.uniform(0.42, 0.58)
        w = 0.72 - i * 0.02
        jitter = Vector((random.uniform(-0.05, 0.05), random.uniform(-0.05, 0.05), 0))
        if broken_top and i == blocks - 1:
            # 마지막 블록은 반쯤 부서짐
            chipped_block(bm, (w, w * random.uniform(0.5, 0.8), h * 0.6), Vector((random.uniform(-0.1, 0.1), random.uniform(-0.15, 0.15), z + h * 0.3)) + jitter, chip=0.2)
        else:
            chipped_block(bm, (w, w, h), Vector((0, 0, z + h * 0.5)) + jitter, chip=0.1)
        z += h
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(material("Stone"))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def make_block(name, seed, size=(1.2, 0.8, 0.6)):
    random.seed(seed)
    bm = bmesh.new()
    chipped_block(bm, size, Vector((0, 0, size[2] * 0.45)), chip=0.16)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(material("Stone"))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ------------------------------------------------------------------ 돌담 모듈 (길이 2 m, x ∈ [-1, 1], 두께 0.6)

def make_wall(name, seed, rows=2, row_h=0.55, length=2.0, thick=0.6, missing=0.15):
    """깎인 돌 블록을 엇갈려 쌓은 담 한 토막. 윗줄 블록은 일부 빠져 폐허 느낌."""
    random.seed(seed)
    bm = bmesh.new()
    x0 = -length * 0.5
    for r in range(rows):
        z = r * row_h
        offset = 0.0 if r % 2 == 0 else 0.45
        x = x0 - offset
        while x < length * 0.5 - 0.05:
            w = random.uniform(0.6, 1.0)
            x1 = min(x + w, length * 0.5)
            if x1 - x > 0.2:
                top_row = r == rows - 1
                if not (top_row and random.random() < missing):
                    h = row_h * (random.uniform(0.75, 1.0) if top_row else 1.0)
                    chipped_block(bm, (x1 - x, thick, h), Vector(((x + x1) * 0.5, 0.0, z + h * 0.5)), chip=0.07)
            x = x1 + 0.02
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(material("Stone"))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ------------------------------------------------------------------ 주인공 (로우폴리, 이목구비 없음)
#
# 원화: 긴 붉은 직모, 검은 셔츠(소매 걷음, 칼라), 벨트+버클, 와이드 팬츠, 검은 구두, 창백한 피부. 1.70 m, 6등신.
# 절차 애니메이션 피벗(Body / HipL / HipR / Torso / ShoulderL / ShoulderR)을 엠프티로 만들고
# 각 부위 메시를 그 아래에 둔다 → Godot 이 같은 이름의 Node3D 계층으로 가져온다.
# 정면은 Blender +Y (= Godot -Z).

def _prism(bm, center, r_bottom, r_top, height, mat, segs=8, sx=1.0, sy=1.0, rot=None):
    """타원 단면 테이퍼 프리즘. center 는 밑면 중심."""
    ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r_bottom, radius2=r_top, depth=height)
    vs = ret["verts"]
    m = Matrix.Translation(center + Vector((0, 0, height * 0.5))) @ (rot if rot else Matrix.Identity(4)) @ Matrix.Diagonal((sx, sy, 1.0, 1.0))
    for v in vs:
        v.co = m @ v.co
    return vs


def _box(bm, center, size, taper_front=1.0, taper_bottom=1.0):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    for v in ret["verts"]:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if v.co.y > 0 and taper_front != 1.0:   # 앞쪽(+Y) 폭 줄이기 (구두 코)
            v.co.x *= taper_front
        if v.co.z < 0 and taper_bottom != 1.0:  # 아래쪽 폭 (머리카락 끝)
            v.co.x *= taper_bottom
        v.co += center
    return ret["verts"]


def _part(name, bm_fill, mat_name, parent, parent_world):
    bm = bmesh.new()
    bm_fill(bm)
    # 부모 엠프티 기준 로컬 좌표로 변환
    for v in bm.verts:
        v.co = v.co - parent_world
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(material(mat_name))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    return ob


def _empty(name, world_pos, parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.location = world_pos - Vector(parent.matrix_world.translation)
    else:
        e.location = world_pos
    bpy.context.view_layer.update()
    return e


def make_player(name="player_red"):
    random.seed(0)
    Z = Vector((0, 0, 0))
    body = _empty("Body", Z)
    hip_l_w = Vector((-0.10, 0.0, 0.93))
    hip_r_w = Vector((0.10, 0.0, 0.93))
    torso_w = Vector((0.0, 0.0, 0.93))
    sh_l_w = Vector((-0.225, 0.0, 1.42))
    sh_r_w = Vector((0.225, 0.0, 1.42))
    hip_l = _empty("HipL", hip_l_w, body)
    hip_r = _empty("HipR", hip_r_w, body)
    torso = _empty("Torso", torso_w, body)
    sh_l = _empty("ShoulderL", sh_l_w, torso)
    sh_r = _empty("ShoulderR", sh_r_w, torso)

    # 골반(바지 허리) — 몸통(Body) 소속, 다리 회전과 무관
    _part("Pelvis", lambda bm: _prism(bm, Vector((0, 0, 0.84)), 0.165, 0.155, 0.12, None, sx=1.1, sy=0.72), "Cloth", body, Z)

    # 다리: 와이드 팬츠 — 아래로 갈수록 넓어짐, 구두
    for side, hip, hw in (("L", hip_l, hip_l_w), ("R", hip_r, hip_r_w)):
        sx = -1 if side == "L" else 1
        _part("Leg" + side, lambda bm, hw=hw: _prism(bm, Vector((hw.x, 0, 0.07)), 0.135, 0.095, 0.87, None, sx=1.0, sy=0.9), "Cloth", hip, hw)
        _part("Shoe" + side, lambda bm, hw=hw: _box(bm, Vector((hw.x, 0.07, 0.035)), (0.11, 0.30, 0.07), taper_front=0.45), "Shoe", hip, hw)

    # 몸통: 셔츠(어깨 넓음), 칼라, 벨트, 버클, 목, 머리, 머리카락
    _part("Belt", lambda bm: _prism(bm, Vector((0, 0, 0.94)), 0.16, 0.16, 0.07, None, sx=1.08, sy=0.74), "Belt", torso, torso_w)
    _part("Buckle", lambda bm: _box(bm, Vector((0, 0.125, 0.975)), (0.065, 0.03, 0.05)), "Buckle", torso, torso_w)
    _part("Shirt", lambda bm: _prism(bm, Vector((0, 0, 1.0)), 0.15, 0.20, 0.45, None, sx=1.15, sy=0.72), "Cloth", torso, torso_w)
    _part("Collar", lambda bm: _box(bm, Vector((0, 0.03, 1.465)), (0.21, 0.13, 0.06)), "Cloth", torso, torso_w)
    _part("Neck", lambda bm: _prism(bm, Vector((0, 0, 1.44)), 0.05, 0.05, 0.11, None), "Skin", torso, torso_w)
    _part("Head", lambda bm: _prism(bm, Vector((0, 0, 1.51)), 0.095, 0.085, 0.23, None, sx=1.0, sy=1.1), "Skin", torso, torso_w)
    # 머리카락: 캡 + 앞머리 + 긴 뒷머리(끝이 넓고 뾰족) + 옆머리 두 가닥
    _part("HairCap", lambda bm: _prism(bm, Vector((0, 0, 1.64)), 0.12, 0.085, 0.135, None, sx=1.0, sy=1.12), "Hair", torso, torso_w)
    _part("HairFringe", lambda bm: _box(bm, Vector((0, 0.095, 1.705)), (0.21, 0.06, 0.055)), "Hair", torso, torso_w)
    _part("HairBack", lambda bm: _box(bm, Vector((0, -0.115, 1.22)), (0.24, 0.085, 0.92), taper_bottom=1.25), "Hair", torso, torso_w)
    _part("HairSideL", lambda bm: _box(bm, Vector((-0.125, -0.01, 1.36)), (0.06, 0.10, 0.60)), "Hair", torso, torso_w)
    _part("HairSideR", lambda bm: _box(bm, Vector((0.125, -0.01, 1.36)), (0.06, 0.10, 0.60)), "Hair", torso, torso_w)

    # 팔: 걷어 올린 소매(두꺼운 커프) + 맨 팔뚝 + 손
    for side, sh, sw in (("L", sh_l, sh_l_w), ("R", sh_r, sh_r_w)):
        _part("UpperArm" + side, lambda bm, sw=sw: _prism(bm, Vector((sw.x, 0, 1.15)), 0.06, 0.07, 0.27, None), "Cloth", sh, sw)
        _part("Cuff" + side, lambda bm, sw=sw: _prism(bm, Vector((sw.x, 0, 1.10)), 0.075, 0.072, 0.06, None), "Cloth", sh, sw)
        _part("Forearm" + side, lambda bm, sw=sw: _prism(bm, Vector((sw.x, 0, 0.86)), 0.04, 0.047, 0.25, None), "Skin", sh, sw)
        _part("Hand" + side, lambda bm, sw=sw: _box(bm, Vector((sw.x, 0.0, 0.81)), (0.05, 0.035, 0.10)), "Skin", sh, sw)
    return body


# ------------------------------------------------------------------ 내보내기

def export(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_materials="EXPORT",
                              export_normals=True, export_texcoords=True, export_animations=False)


def build(fn, filename, *args, **kwargs):
    reset()
    fn(*args, **kwargs)
    export(f"{OUT}/{filename}")
    print("[gen_assets] wrote", filename)


build(make_tree, "tree_a.glb", "tree_a", 1)
build(make_tree, "tree_b.glb", "tree_b", 2, height=1.5, card_size=(0.9, 1.3))
build(make_rock, "rock_a.glb", "rock_a", 11, scale=(1.0, 0.85, 0.75))
build(make_rock, "rock_b.glb", "rock_b", 12, scale=(1.3, 0.9, 0.6), amp=0.22)
build(make_rock, "rock_c.glb", "rock_c", 13, scale=(0.8, 0.7, 0.9), amp=0.32)
build(make_rock, "rock_d.glb", "rock_d", 14, scale=(0.55, 0.5, 0.45), subdiv=1, amp=0.3)
build(make_bush, "bush_a.glb", "bush_a", 21)
build(make_bush, "bush_b.glb", "bush_b", 22, radius=1.5, height=0.65, cards=70)
build(make_pillar, "pillar_a.glb", "pillar_a", 31, blocks=5)
build(make_pillar, "pillar_b.glb", "pillar_b", 32, blocks=3, broken_top=True)
build(make_block, "block_a.glb", "block_a", 41)
build(make_block, "block_b.glb", "block_b", 42, size=(0.8, 0.8, 0.8))
build(make_wall, "wall_low_a.glb", "wall_low_a", 51, rows=2)
build(make_wall, "wall_low_b.glb", "wall_low_b", 52, rows=2)
build(make_wall, "wall_low_c.glb", "wall_low_c", 53, rows=2, missing=0.45)
build(make_wall, "wall_tall_a.glb", "wall_tall_a", 61, rows=5, missing=0.1)
build(make_wall, "wall_tall_b.glb", "wall_tall_b", 62, rows=5, missing=0.3)
build(make_player, "player_red.glb")
print("[gen_assets] done")
