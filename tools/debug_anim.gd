## 개발용: 애니메이션 포즈에서 주요 뼈의 전역 위치 확인.  godot --headless --path . -s tools/debug_anim.gd
extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/Player.tscn")
	var p := packed.instantiate()
	root.add_child(p)
	await process_frame
	await process_frame
	var skel: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = p.get_node("AnimationPlayer")
	var names := ["Hips", "Spine", "Spine2", "Head", "LeftArm", "LeftForeArm", "LeftUpLeg", "LeftLeg", "LeftFoot"]
	for anim in ["Idle", "Walk", "Attack"]:
		for t in [0.0, 0.25, 0.5, 0.75]:
			ap.playback_default_blend_time = 0.0
			ap.play(anim, 0.0)
			ap.seek(t * ap.get_animation(anim).length, true)
			await process_frame
			var line := "[%s t=%.2f] " % [anim, t]
			for n in names:
				var i := skel.find_bone(n)
				var o := skel.get_bone_global_pose(i).origin
				line += "%s=(%.2f,%.2f,%.2f) " % [n, o.x, o.y, o.z]
			print(line)
	var line := "[REST] "
	for n in names:
		var i := skel.find_bone(n)
		var o := skel.get_bone_global_rest(i).origin
		line += "%s=(%.2f,%.2f,%.2f) " % [n, o.x, o.y, o.z]
	print(line)
	quit(0)
