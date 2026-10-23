## 자동 검증/캡처 러너 (개발용). 게임 실행에는 필요 없음.
##   godot --path . -s tools/capture_runner.gd
## Main 씬을 띄우고 입력을 시뮬레이션하며 user://captures/ 에 1080p PNG를 저장한다.
extends SceneTree

var _main: Node
var _player: Node
var _frames: int = 0
var _step: int = 0
var _errors: int = 0

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	current_scene = _main
	_player = _main.get_node("Player")
	print("[runner] main scene loaded")

func _process(_delta: float) -> bool:
	_frames += 1
	var t := _frames / 60.0
	match _step:
		0:
			if t > 1.0:
				_cap("01_idle.png"); _step = 1
		1:
			# ↑ + → 대각선 이동: 시작점에서 3m 이상 벗어나면 캡처 (프레임레이트 무관)
			Input.action_press("move_up"); Input.action_press("move_right")
			if _player.global_position.distance_to(Vector3(0, 0, 2.5)) > 3.0:
				_cap("02_move.png")
				Input.action_release("move_up"); Input.action_release("move_right"); _step = 2
		2:
			var p: Vector3 = _player.global_position
			var v: Vector3 = _player.velocity
			print("[runner] player pos after ↑→: %s  vel=%s (expect world -Z = screen up-right, |v|<=3.4)" % [p, v])
			_step = 3
		3:
			# 더미01 쪽으로 이동: 더미 (-3.5, 0, 3.5). 플레이어 위치 기준으로 ←/↓ 조합
			var p: Vector3 = _player.global_position
			var to: Vector3 = Vector3(-3.5, 0, 3.5) - p
			to.y = 0
			if to.length() < 1.15:
				_release_all(); _step = 4
			else:
				_drive_toward(to)
				if t > 14.0:
					print("[runner] WARN could not reach dummy, dist %.2f" % to.length()); _release_all(); _step = 4
		4:
			_release_all()
			if _frames % 60 == 0:
				Input.action_press("attack"); _step = 5; _frames_attack = _frames
		5:
			Input.action_release("attack")
			var at: float = _player.get("_attack_time")
			if not _attack_captured and _player.state == 2 and at >= 0.10 and at < 0.19:
				_attack_captured = true
				_cap("03_attack.png")
			if _frames - _frames_attack == 30:
				var d = _main.get_node("HitDummies/HitDummy01")
				print("[runner] dummy01 hit_count=%d  dummy02 hit_count=%d" % [d.hit_count, _main.get_node("HitDummies/HitDummy02").hit_count])
				_step = 6
		6:
			_main.get_node("HUD").set_debug_visible(true); _step = 7
		7:
			if _frames % 20 == 0:
				_cap("04_debug_hud.png"); _step = 8
		8:
			_main.get_node("HUD").set_debug_visible(false); _step = 9
		9:
			_main.call("_apply_light_preset", 0)
			if _frames % 10 == 0:
				_cap("05_light_A_default.png"); _step = 10
		10:
			_main.call("_apply_light_preset", 1)
			if _frames % 10 == 0:
				_cap("06_light_B_opposite.png"); _step = 11
		11:
			_main.call("_apply_light_preset", 2)
			if _frames % 10 == 0:
				_cap("07_light_C_low.png"); _main.call("_apply_light_preset", 0); _step = 12
		12:
			# 벽 관통 테스트: 동쪽 통로 북쪽 벽(z=-2.1, x 7..15)에 북쪽으로 계속 밀어붙임
			_player.global_position = Vector3(11.0, 0.3, 0.0)
			_step = 13; _frames_attack = _frames
		13:
			# ↑+→ = 월드 -Z 방향
			Input.action_press("move_up"); Input.action_press("move_right")
			if _frames - _frames_attack > 120:
				_release_all()
				var p: Vector3 = _player.global_position
				print("[runner] wall test: player pos=%s (wall face z=-1.8; z must stay > -1.8)" % p)
				_step = 14; _frames_attack = _frames
		14:
			# 계단 오르기: (13, 0, -3.5) 에서 북쪽으로
			_player.global_position = Vector3(13.0, 0.3, -2.5)
			_step = 15; _frames_attack = _frames
		15:
			Input.action_press("move_up"); Input.action_press("move_right")
			if _frames - _frames_attack == 40:
				_cap("08_stairs.png")
			if _frames - _frames_attack > 100:
				_release_all()
				var p: Vector3 = _player.global_position
				print("[runner] stairs test: player pos=%s (expect y≈1.0 on terrace)" % p)
				_step = 16
		16:
			print("[runner] done, frames=%d" % _frames)
			quit(0)
			return true
	return false

var _frames_attack: int = 0
var _attack_captured: bool = false

func _drive_toward(to: Vector3) -> void:
	var rig = _main.get_node("CameraRig")
	var r: Vector3 = rig.screen_right()
	var u: Vector3 = rig.screen_up()
	var sx := to.dot(r); var sy := to.dot(u)
	_release_all()
	if sx > 0.2: Input.action_press("move_right")
	elif sx < -0.2: Input.action_press("move_left")
	if sy > 0.2: Input.action_press("move_up")
	elif sy < -0.2: Input.action_press("move_down")

func _release_all() -> void:
	for a in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(a)

func _cap(name: String) -> void:
	var path: String = _main.call("capture_screenshot", name)
	print("[runner] captured %s" % name)
