## 렌더 설정별 FPS 측정 (테스트 환경 튜닝용): 아레나를 띄우고 4초 뒤 FPS 출력
extends SceneTree
var _t0 := 0
var _frames := 0
func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/BossTestArena.tscn")
	root.add_child(packed.instantiate())
	_t0 = Time.get_ticks_msec()
func _process(_d: float) -> bool:
	_frames += 1
	var el := Time.get_ticks_msec() - _t0
	if el > 4000:
		print("[probe] frames=%d in %d ms → %.1f fps (engine says %d)" % [_frames, el, _frames * 1000.0 / el, Engine.get_frames_per_second()])
		quit(0)
		return true
	return false
