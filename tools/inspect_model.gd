## 개발용: glb 임포트 결과(뼈 이름, 방향, 크기) 확인.  godot --headless --path . -s tools/inspect_model.gd
extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://assets/character/player_src.glb")
	var inst := packed.instantiate()
	root.add_child(inst)
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	print("[inspect] skeletons: ", skels.size())
	if skels.size() > 0:
		var sk: Skeleton3D = skels[0]
		print("[inspect] bones: ", sk.get_bone_count())
		for i in sk.get_bone_count():
			if i < 12 or "Foot" in sk.get_bone_name(i) or "Toe" in sk.get_bone_name(i) or "Head" in sk.get_bone_name(i):
				var g := sk.get_bone_global_rest(i)
				print("  %2d %-26s parent=%2d pos=%s" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), g.origin])
		print("[inspect] skeleton xform: ", sk.global_transform)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		print("[inspect] mesh ", m.name, " aabb=", m.get_aabb(), " xform=", m.global_transform, " skin=", m.skin != null, " surfaces=", m.mesh.get_surface_count(), " mat=", m.mesh.surface_get_material(0).resource_name if m.mesh.surface_get_material(0) else "none")
	quit(0)
