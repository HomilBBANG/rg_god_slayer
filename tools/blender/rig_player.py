"""
플레이어 캐릭터 리깅 — Blender 헤드리스
    blender -b -P tools/blender/rig_player.py -- <입력.glb> <출력 폴더>

입력: Tripo 스타일 고폴리(≈94만 tri) 무리깅 glb, 키 0.98 m, 정면 -Y, 팔은 옆으로 내린 A-포즈.
처리:
  1. 1.70 m 로 스케일, 발바닥 z=0, 정면을 +Y 로 회전 (→ Godot -Z)
  2. Decimate(collapse) 로 ~9k tri 저폴리화 (UV 유지)
  3. 휴머노이드 아마추어 생성 (Hips/Spine/Chest/Neck/Head, Shoulder/UpperArm/LowerArm/Hand .L/.R, UpperLeg/LowerLeg/Foot .L/.R)
     — 뼈 위치는 키(H) 비율 휴리스틱
  4. 정점 가중치: 각 뼈 선분까지의 거리 기반 역거리 가중(최대 3개 뼈) — 비매니폴드 메시에서 Heat 가 실패하는 문제 회피
  5. 베이스컬러 텍스처를 1024 PNG 로 따로 저장, glb 는 스킨 포함 내보내기
"""
import bpy, bmesh, sys, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
TARGET_H = 1.70
TARGET_TRIS = 9000

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
mesh_ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
mesh_ob.name = "PlayerMesh"
bpy.context.view_layer.objects.active = mesh_ob
mesh_ob.select_set(True)

# ---- 1. 스케일/정렬: 정면 -Y → +Y (Z 축 180°), 키 1.70, 발 z=0
h0 = mesh_ob.dimensions.z
s = TARGET_H / h0
mesh_ob.scale = (s, s, s)
mesh_ob.rotation_euler = (0, 0, math.radians(180))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
zmin = min((mesh_ob.matrix_world @ v.co).z for v in mesh_ob.data.vertices)
mesh_ob.location.z -= zmin
bpy.ops.object.transform_apply(location=True)
H = mesh_ob.dimensions.z
print("[rig] height", round(H, 3))

# ---- 2. 저폴리화
tris0 = len(mesh_ob.data.polygons)
mod = mesh_ob.modifiers.new("dec", "DECIMATE")
mod.decimate_type = "COLLAPSE"
mod.ratio = max(0.001, TARGET_TRIS / float(tris0))
mod.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="dec")
print("[rig] tris", tris0, "->", len(mesh_ob.data.polygons))
for p in mesh_ob.data.polygons:
    p.use_smooth = True

# ---- 3. 아마추어 (정면 +Y, 캐릭터 왼쪽 = -X)
B = {  # name: (head, tail, parent)
    "Hips":       ((0, 0, 0.52), (0, 0, 0.60), None),
    "Spine":      ((0, 0, 0.60), (0, 0, 0.72), "Hips"),
    "Chest":      ((0, 0, 0.72), (0, 0, 0.84), "Spine"),
    "Neck":       ((0, 0, 0.84), (0, 0, 0.89), "Chest"),
    "Head":       ((0, 0, 0.89), (0, 0, 1.00), "Neck"),
}
for side, sx in (("L", -1), ("R", 1)):
    B["Shoulder." + side] = ((sx * 0.04, 0, 0.83), (sx * 0.12, 0, 0.83), "Chest")
    B["UpperArm." + side] = ((sx * 0.12, 0, 0.83), (sx * 0.165, 0, 0.63), "Shoulder." + side)
    B["LowerArm." + side] = ((sx * 0.165, 0, 0.63), (sx * 0.19, 0, 0.44), "UpperArm." + side)
    B["Hand." + side] = ((sx * 0.19, 0, 0.44), (sx * 0.20, 0, 0.36), "LowerArm." + side)
    B["UpperLeg." + side] = ((sx * 0.065, 0, 0.52), (sx * 0.07, 0, 0.29), "Hips")
    B["LowerLeg." + side] = ((sx * 0.07, 0, 0.29), (sx * 0.075, 0, 0.06), "UpperLeg." + side)
    B["Foot." + side] = ((sx * 0.075, 0, 0.06), (sx * 0.075, 0.09, 0.02), "LowerLeg." + side)

arm_data = bpy.data.armatures.new("Armature")
arm = bpy.data.objects.new("Armature", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = {}
for name, (hd, tl, parent) in B.items():
    b = arm_data.edit_bones.new(name)
    b.head = Vector(hd) * H
    b.tail = Vector(tl) * H
    b.roll = 0.0
    eb[name] = b
for name, (hd, tl, parent) in B.items():
    if parent:
        eb[name].parent = eb[parent]
        eb[name].use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")

# ---- 4. 거리 기반 가중치
segs = {name: (Vector(hd) * H, Vector(tl) * H) for name, (hd, tl, parent) in B.items()}
# 뼈별 영향 반경(가중 감쇠 스케일): 몸통은 넓게, 팔다리는 좁게
radius = {n: 0.09 * H for n in segs}
for n in ("Hips", "Spine", "Chest"):
    radius[n] = 0.16 * H
radius["Head"] = 0.12 * H
radius["Neck"] = 0.06 * H

def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length

for name in segs:
    mesh_ob.vertex_groups.new(name=name)
vg = {g.name: g for g in mesh_ob.vertex_groups}
names = list(segs.keys())
for v in mesh_ob.data.vertices:
    p = v.co
    ds = []
    for n in names:
        a, b = segs[n]
        d = seg_dist(p, a, b) / radius[n]
        ds.append((d, n))
    ds.sort()
    best = ds[0][0]
    cand = [(d, n) for d, n in ds[:3] if d <= best * 1.8 + 0.15]
    ws = [(1.0 / (d + 0.08)) ** 3 for d, n in cand]
    tot = sum(ws)
    for (d, n), w in zip(cand, ws):
        vg[n].add([v.index], w / tot, "REPLACE")

mesh_ob.parent = arm
amod = mesh_ob.modifiers.new("Armature", "ARMATURE")
amod.object = arm

# ---- 5. 재질/텍스처: 베이스컬러만
img = None
for i in bpy.data.images:
    if "basecolor" in i.name.lower():
        img = i
if img:
    img.scale(1024, 1024)
    img.filepath_raw = OUT + "/player_basecolor.png"
    img.file_format = "PNG"
    img.save()
    print("[rig] basecolor saved")
mat = bpy.data.materials.new("CharTex")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
if img and bsdf:
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
mesh_ob.data.materials.clear()
mesh_ob.data.materials.append(mat)

bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
mesh_ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT + "/player_rigged.glb", export_format="GLB", use_selection=True,
                          export_yup=True, export_apply=False, export_skins=True, export_materials="EXPORT",
                          export_image_format="NONE", export_animations=False, export_normals=True, export_texcoords=True)
print("[rig] exported", OUT + "/player_rigged.glb")
