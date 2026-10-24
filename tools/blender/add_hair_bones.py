"""
리깅된 캐릭터에 머리카락 뼈 추가 — Blender 헤드리스
    blender -b -P tools/blender/add_hair_bones.py -- <입력.glb> <출력 폴더>

입력: Mixamo 뼈대가 들어 있는 Tripo 캐릭터 glb (18.7k tri, 정면 +X, 왼쪽 +Y).
      ※ 이 파일의 스킨 가중치는 거의 모든 정점이 Hips 에 0.99 로 묶여 있어 그대로 쓰면 메시가 찢어진다.
        뼈 위치/이름은 유지하고 가중치만 다시 계산한다.
처리:
  1. 포즈 리셋, 정면을 +Y (Godot −Z) 로 회전, 1.70 m 스케일, 발바닥 z=0, 'mixamorig:' 접두어 제거
  2. 손가락 뼈 제거 (절차 애니메이션에 불필요, 가중치 단순화)
  3. 머리카락 뼈 체인 추가: HairBack1~4 (뒤통수→허리), HairL1~2 / HairR1~2 (양옆 앞 가닥). 부모 = Head
  4. 가중치: 뼈 선분 거리 기반 역거리 가중(최대 3본). 뒷머리 영역(등 뒤)은 체인 z 보간으로 덮어쓰기
  5. 베이스컬러 1024 PNG 분리, 스킨 포함 glb 내보내기
"""
import bpy, bmesh, sys, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
TARGET_H = 1.70

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
mesh_ob = [o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm][0]
# 불필요 오브젝트 제거 (Icosphere, 끝점 엠프티)
for o in list(bpy.data.objects):
    if o not in (arm, mesh_ob):
        bpy.data.objects.remove(o, do_unlink=True)
mesh_ob.name = "PlayerMesh"
arm.name = "Armature"

# ---- 1. 포즈 리셋 + 정렬 (오브젝트 변환이 아니라 데이터 자체를 변환, 1.70 m, 발 z=0)
#   메시는 Blender 표준 정면(-Y)을 보고 있고, 이 파일의 Mixamo 뼈대는 메시와 90° 어긋난 프레임(정면 +X, 왼쪽 +Y)에 있다.
#   → 메시 Rz(180°): -Y → +Y,  뼈 Rz(90°): +X → +Y. 둘 다 정면 +Y (= Godot -Z) 로 맞춘다.
from mathutils import Matrix
# 주의: matrix_basis.identity() 는 복사본만 바꾸는 no-op → 속성에 직접 대입
for pb in arm.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
    pb.location = (0.0, 0.0, 0.0)
    pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    pb.rotation_euler = (0.0, 0.0, 0.0)
    pb.scale = (1.0, 1.0, 1.0)
arm.matrix_world = Matrix.Identity(4)
mesh_ob.matrix_parent_inverse = Matrix.Identity(4)
mesh_ob.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
zs = [v.co.z for v in mesh_ob.data.vertices]
s = TARGET_H / (max(zs) - min(zs))
TS = Matrix.Translation((0, 0, -min(zs) * s)) @ Matrix.Scale(s, 4)
M_mesh = TS @ Matrix.Rotation(math.radians(180), 4, "Z")
M = TS @ Matrix.Rotation(math.radians(90), 4, "Z")
for v in mesh_ob.data.vertices:
    v.co = M_mesh @ v.co
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for b in arm.data.edit_bones:
    b.transform(M, scale=True, roll=True)
bpy.ops.object.mode_set(mode="OBJECT")
H = max(v.co.z for v in mesh_ob.data.vertices)
print("[hair] height", round(H, 3), "facing +Y check: toe tail", tuple(round(v, 3) for v in arm.data.bones["mixamorig:LeftToeBase"].tail_local))

# ---- 2. 이름 정리 + 손가락 제거
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
for b in list(eb):
    b.name = b.name.replace("mixamorig:", "")
for b in list(eb):
    if any(k in b.name for k in ("HandIndex", "HandMiddle", "HandRing", "HandPinky", "HandThumb", "Toe_End", "HeadTop")):
        eb.remove(b)
# ---- 2b. 뼈 위치를 메시에 피팅 (이 파일의 뼈대는 메시와 이동/기울기가 어긋나 있음)
#   이름·계층은 Mixamo 그대로, head/tail 만 메시 단면 통계로 다시 잡는다. 정면 +Y, 왼쪽 -X.
mesh_pts = [v.co.copy() for v in mesh_ob.data.vertices]


def band(z0, z1, cond=lambda p: True):
    return [p for p in mesh_pts if z0 <= p.z < z1 and cond(p)]


def center(pts, fallback):
    if len(pts) < 5:
        return fallback.copy()
    return Vector((sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts), sum(p.z for p in pts) / len(pts)))


waist = center(band(0.55 * H, 0.60 * H), Vector((0, 0, 0.575 * H)))
cx, cy = waist.x, waist.y
# 몸통 중심선 (머리카락 제외를 위해 중심 근처 |x-cx|<0.12H 만)
def torso_center(z0, z1):
    return center(band(z0, z1, lambda p: abs(p.x - cx) < 0.12 * H and p.y > cy - 0.12 * H), Vector((cx, cy, (z0 + z1) * 0.5)))


spine0 = Vector((cx, cy, 0.575 * H))
spine1 = torso_center(0.62 * H, 0.66 * H); spine1.z = 0.64 * H
spine2 = torso_center(0.70 * H, 0.74 * H); spine2.z = 0.72 * H
chest = torso_center(0.77 * H, 0.81 * H); chest.z = 0.79 * H
neck = torso_center(0.82 * H, 0.85 * H); neck.z = 0.835 * H
# 얼굴은 앞쪽(+Y) 정점으로
face = center(band(0.86 * H, 0.94 * H, lambda p: abs(p.x - cx) < 0.10 * H and p.y > cy), Vector((cx, cy + 0.03 * H, 0.9 * H)))
head_b = Vector((face.x, face.y - 0.03 * H, 0.86 * H))
head_t = Vector((face.x, face.y - 0.03 * H, 0.94 * H))


def side_center(z0, z1, side, min_off, fallback):
    sx = -1 if side == "L" else 1
    pts = band(z0, z1, lambda p: sx * (p.x - cx) > min_off * H and abs(p.y - cy) < 0.15 * H)
    return center(pts, fallback)


fit = {"Hips": (spine0, Vector((cx, cy, 0.61 * H))), "Spine": (Vector((cx, cy, 0.61 * H)), spine1), "Spine1": (spine1, spine2), "Spine2": (spine2, chest),
       "Neck": (neck, Vector((neck.x, neck.y, 0.86 * H))), "Head": (head_b, head_t)}
# 사람 비율: 대전자(고관절) ≈ 0.53H, 무릎 ≈ 0.285H, 발목 ≈ 0.045H
for side, sx in (("L", -1), ("R", 1)):
    hip = Vector((cx + sx * 0.052 * H, cy + 0.01 * H, 0.53 * H))
    knee = side_center(0.26 * H, 0.31 * H, side, 0.0, Vector((cx + sx * 0.06 * H, cy, 0.285 * H))); knee.z = 0.285 * H
    # 무릎은 발목·고관절보다 살짝 앞 (자연스러운 굽힘 방향), 통바지 폭에 끌리지 않게 x 는 고관절과 발목 사이로 제한
    ankle = side_center(0.03 * H, 0.08 * H, side, 0.0, Vector((cx + sx * 0.07 * H, cy, 0.055 * H))); ankle.z = 0.045 * H
    knee.x = (hip.x + ankle.x) * 0.5 + (knee.x - (hip.x + ankle.x) * 0.5) * 0.3
    knee.y = (hip.y + ankle.y) * 0.5 + 0.015 * H
    toe = Vector((ankle.x, ankle.y + 0.09 * H, 0.012 * H))
    fit[side_name := ("Left" if side == "L" else "Right") + "UpLeg"] = (hip, knee)
    fit[("Left" if side == "L" else "Right") + "Leg"] = (knee, ankle)
    fit[("Left" if side == "L" else "Right") + "Foot"] = (ankle, toe)
    fit[("Left" if side == "L" else "Right") + "ToeBase"] = (toe, toe + Vector((0, 0.04 * H, 0)))
    # 팔: 어깨(몸통 폭 바깥), 팔꿈치, 손 — 옆으로 뻗은 정점 군집의 중심
    shoulder_in = Vector((chest.x + sx * 0.03 * H, chest.y, 0.80 * H))
    shoulder = side_center(0.76 * H, 0.80 * H, side, 0.09, Vector((cx + sx * 0.12 * H, cy, 0.78 * H))); shoulder.z = 0.78 * H
    elbow = side_center(0.60 * H, 0.66 * H, side, 0.11, Vector((cx + sx * 0.15 * H, cy, 0.63 * H))); elbow.z = 0.63 * H
    hand = side_center(0.46 * H, 0.52 * H, side, 0.12, Vector((cx + sx * 0.17 * H, cy, 0.49 * H))); hand.z = 0.49 * H
    fit[("Left" if side == "L" else "Right") + "Shoulder"] = (shoulder_in, shoulder)
    fit[("Left" if side == "L" else "Right") + "Arm"] = (shoulder, elbow)
    fit[("Left" if side == "L" else "Right") + "ForeArm"] = (elbow, hand)
    fit[("Left" if side == "L" else "Right") + "Hand"] = (hand, hand + Vector((sx * 0.01 * H, 0, -0.05 * H)))
for n, (hd, tl) in fit.items():
    if n in eb:
        eb[n].head = hd
        eb[n].tail = tl
        eb[n].roll = 0.0
    else:
        print("[hair] WARN bone not in armature:", n)
head = eb["Head"]
head_pos = head.head.copy()
print("[hair] fitted: waist", tuple(round(v, 3) for v in waist), "head", tuple(round(v, 3) for v in head_pos), "L hand", tuple(round(v, 3) for v in fit["LeftHand"][0]), "R hand", tuple(round(v, 3) for v in fit["RightHand"][0]))

# ---- 3. 머리카락 정점 판별: 베이스컬러 텍스처의 붉은색 (UV 샘플링)
img_src = None
for i in bpy.data.images:
    if "basecolor" in i.name.lower():
        img_src = i
small = img_src.copy()
small.scale(256, 256)
px = small.pixels[:]
W = 256
print("[hair] tex sample ok:", small.has_data, "mean rgb", round(sum(px[0::4]) / (W * W), 3), round(sum(px[1::4]) / (W * W), 3), round(sum(px[2::4]) / (W * W), 3))
me = mesh_ob.data
uv_layer = me.uv_layers.active.data
vert_uv = {}
for poly in me.polygons:
    for li in poly.loop_indices:
        vi = me.loops[li].vertex_index
        if vi not in vert_uv:
            vert_uv[vi] = uv_layer[li].uv.copy()


def sample(uv):
    u = int((uv.x % 1.0) * (W - 1))
    v = int((uv.y % 1.0) * (W - 1))
    k = (v * W + u) * 4
    return px[k], px[k + 1], px[k + 2]


is_hair = [False] * len(me.vertices)
limb_segs = []
for b in eb:
    if any(k in b.name for k in ("Hand", "ForeArm", "Leg", "Foot", "Toe")):
        limb_segs.append((b.head.copy(), b.tail.copy()))


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


band_count = {}
for v in me.vertices:
    uv = vert_uv.get(v.index)
    if uv is None:
        continue
    r, g, b = sample(uv)
    # 붉은 갈색 머리: R 우세. (피부는 R≈G, 옷은 어두운 무채색)
    red = r > 0.18 and r > g * 1.6 and r > b * 1.6
    if not red:
        continue
    band_count[int(v.co.z / H * 10)] = band_count.get(int(v.co.z / H * 10), 0) + 1
    # 기하 제약: 허리 아래(바지/신발)와 손·팔뚝·다리 뼈 근처는 머리카락이 아님
    if v.co.z < 0.52 * H:
        continue
    if min(seg_dist(v.co, a, b) for a, b in limb_segs) < 0.04 * H:
        continue
    is_hair[v.index] = True
hair_pts = [v.co.copy() for v in me.vertices if is_hair[v.index]]
print("[hair] red verts per 10% z band:", dict(sorted(band_count.items())))
print("[hair] hair verts (color + geometry):", len(hair_pts), "of", len(me.vertices))
# 머리 중심은 두피(머리 위쪽) 머리카락 정점 평균으로
scalp = [p for p in hair_pts if p.z > head_pos.z + 0.03 * H]
if scalp:
    head_cx = sum(p.x for p in scalp) / len(scalp)
    head_cy = sum(p.y for p in scalp) / len(scalp)
else:
    head_cx, head_cy = head_pos.x, head_pos.y
print("[hair] scalp center", round(head_cx, 3), round(head_cy, 3), "(bone head", round(head_pos.x, 3), round(head_pos.y, 3), ")")

head_z = head_pos.z
center_y = head_cy
center_x = head_cx


def is_back(p):
    return p.y < center_y - 0.04 * H and abs(p.x - center_x) < 0.13 * H


# 뒷머리 = 머리 아래 & 중심보다 뒤(-Y). 옆머리 = 머리 아래 & 그 외
back_pts = [p for p in hair_pts if p.z < head_z and is_back(p)]
side_pts = {"L": [p for p in hair_pts if p.z < head_z and not is_back(p) and p.x < center_x - 0.03 * H],
            "R": [p for p in hair_pts if p.z < head_z and not is_back(p) and p.x > center_x + 0.03 * H]}
print("[hair] back", len(back_pts), "sideL", len(side_pts["L"]), "sideR", len(side_pts["R"]))


def centerline(pts, zs):
    out = []
    for z in zs:
        band = [p for p in pts if abs(p.z - z) < 0.06 * H]
        if len(band) < 5:
            band = sorted(pts, key=lambda p: abs(p.z - z))[:20]
        out.append(Vector((sum(p.x for p in band) / len(band), sum(p.y for p in band) / len(band), z)))
    return out


# (머리카락 전용 뼈 없음 — 머리카락은 높이에 따라 Head/Spine2/Spine 으로 블렌드)
hair_bones = []
segs = {b.name: (b.head.copy(), b.tail.copy()) for b in eb}
bpy.ops.object.mode_set(mode="OBJECT")

# ---- 4. 가중치 재계산
for g in list(mesh_ob.vertex_groups):
    mesh_ob.vertex_groups.remove(g)
for n in segs:
    mesh_ob.vertex_groups.new(name=n)
vg = {g.name: g for g in mesh_ob.vertex_groups}

body_names = [n for n in segs if not n.startswith("Hair")]
radius = {n: 0.08 * H for n in segs}
for n in ("Hips", "Spine", "Spine1", "Spine2"):
    radius[n] = 0.15 * H
radius["Head"] = 0.13 * H
radius["Neck"] = 0.05 * H
for n in ("LeftShoulder", "RightShoulder"):
    radius[n] = 0.06 * H
for n in ("LeftHand", "RightHand"):
    radius[n] = 0.05 * H


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def chain_weights(z, names, zs):
    """z 를 체인 구간으로 보간 → {bone: w}. 뿌리 근처는 Head 와 섞는다."""
    if z >= zs[1]:
        w = {names[0]: 1.0}
    elif z <= zs[-1]:
        w = {names[-1]: 1.0}
    else:
        w = {names[-1]: 1.0}
        for i in range(1, len(zs) - 1):
            if zs[i] >= z > zs[i + 1]:
                t = (zs[i] - z) / (zs[i] - zs[i + 1])
                w = {names[i - 1]: 1.0 - t, names[i]: t}
                break
    blend_top = zs[0] - 0.02 * H
    if z > blend_top - 0.06 * H:
        k = min(1.0, max(0.0, (z - (blend_top - 0.06 * H)) / (0.06 * H)))
        w = {n: ww * (1.0 - k) for n, ww in w.items()}
        w["Head"] = w.get("Head", 0.0) + k
    return w


n_hair = 0
z_head = head_pos.z
z_chest = segs["Spine2"][0].z
z_spine = segs["Spine"][0].z
for v in me.vertices:
    p = v.co
    if is_hair[v.index]:
        # 두피/뒤통수 → Head, 어깨~가슴 → Spine2, 허리 → Spine. 구간 사이는 선형 블렌드 (튀는 경계 없음)
        if p.z >= z_head - 0.02 * H:
            w = {"Head": 1.0}
        elif p.z >= z_chest:
            t = (z_head - 0.02 * H - p.z) / max(z_head - 0.02 * H - z_chest, 1e-6)
            w = {"Head": 1.0 - t, "Spine2": t}
        elif p.z >= z_spine:
            t = (z_chest - p.z) / max(z_chest - z_spine, 1e-6)
            w = {"Spine2": 1.0 - t, "Spine": t}
        else:
            w = {"Spine": 1.0}
        for n, ww in w.items():
            vg[n].add([v.index], ww, "REPLACE")
        n_hair += 1
        continue
    ds = sorted(((seg_dist(p, *segs[n]) / radius[n], n) for n in body_names))
    best = ds[0][0]
    cand = [(d, n) for d, n in ds[:3] if d <= best * 1.8 + 0.15]
    ws = [(1.0 / (d + 0.08)) ** 3 for d, n in cand]
    tot = sum(ws)
    for (d, n), w in zip(cand, ws):
        vg[n].add([v.index], w / tot, "REPLACE")
print("[hair] hair verts blended Head/Spine2/Spine:", n_hair)

# ---- 4b. 경계 스무딩: 머리카락/몸 경계에서 가중치가 뚝 끊기며 찢어지는 것을 막는다
#   머리카락 정점과 그 2-링 이웃에 대해 이웃 평균과 섞기 (3회)
adj = {}
for e in me.edges:
    a, b = e.vertices
    adj.setdefault(a, []).append(b)
    adj.setdefault(b, []).append(a)
wmap = {}
for v in me.vertices:
    wmap[v.index] = {mesh_ob.vertex_groups[g.group].name: g.weight for g in v.groups}
region = set(i for i in range(len(me.vertices)) if is_hair[i])
for _ in range(2):
    region |= set(n for i in list(region) for n in adj.get(i, ()))
for _ in range(3):
    new = {}
    for i in region:
        nb = adj.get(i, [])
        if not nb:
            continue
        acc = {}
        for n in nb:
            for k, w in wmap[n].items():
                acc[k] = acc.get(k, 0.0) + w / len(nb)
        mix = {}
        for k in set(acc) | set(wmap[i]):
            mix[k] = 0.5 * wmap[i].get(k, 0.0) + 0.5 * acc.get(k, 0.0)
        tot = sum(mix.values()) or 1.0
        new[i] = {k: w / tot for k, w in mix.items() if w > 0.01}
    wmap.update(new)
for i in region:
    for g in mesh_ob.vertex_groups:
        g.remove([i])
    for k, w in wmap[i].items():
        vg[k].add([i], w, "REPLACE")
print("[hair] boundary-smoothed verts:", len(region))
for pg in me.polygons:
    pg.use_smooth = True
bpy.data.images.remove(small)

# ---- 5. 재질/텍스처
img = None
for i in bpy.data.images:
    if "basecolor" in i.name.lower():
        img = i
if img:
    img.scale(1024, 1024)
    img.filepath_raw = OUT + "/player_basecolor.png"
    img.file_format = "PNG"
    img.save()
mat = bpy.data.materials.new("CharTex")
mat.use_nodes = True
me.materials.clear()
me.materials.append(mat)


# ---- 검증 렌더 (export 전): 정면(+Y 에서), 옆, 뒤 — 뒷머리 뼈를 살짝 흔든 포즈로
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
for nm, ang in (("Spine", 6.0), ("Spine2", 6.0), ("Head", 8.0)):
    pb = arm.pose.bones[nm]
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = (math.radians(ang), 0, 0)
bpy.ops.object.mode_set(mode="OBJECT")
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = 500
scene.render.resolution_y = 800
cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam_data.type = "ORTHO"
cam_data.ortho_scale = 2.1
for nm, pos, rot in (("front", (0, 4, 0.85), (math.radians(90), 0, math.radians(180))), ("side", (4, 0, 0.85), (math.radians(90), 0, math.radians(90))), ("back", (0, -4, 0.85), (math.radians(90), 0, 0))):
    cam.location = pos
    cam.rotation_euler = rot
    scene.render.filepath = OUT + "/../../docs/captures/15_rig_check_%s.png" % nm
    bpy.ops.render.render(write_still=True)
print("[hair] check renders written")
# 렌더용 포즈 리셋 후 내보내기 (내보내기는 마지막에: 익스포터가 씬 상태를 건드릴 수 있음)
for pb in arm.pose.bones:
    pb.rotation_euler = (0.0, 0.0, 0.0)
    pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
bpy.data.objects.remove(cam, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
mesh_ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT + "/player_rigged.glb", export_format="GLB", use_selection=True,
                          export_yup=True, export_apply=False, export_skins=True, export_materials="EXPORT",
                          export_image_format="NONE", export_animations=False, export_normals=True, export_texcoords=True)
print("[hair] exported", OUT + "/player_rigged.glb", "bones", len(arm.data.bones))

