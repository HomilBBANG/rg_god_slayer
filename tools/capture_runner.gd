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
	_player = _main.get_node("World/Player")
	print("[runner] main scene loaded")
	if OS.get_environment("RED_ANIMVIEW") != "":
		_step = 30
		print("[runner] anim view mode")
	elif OS.get_environment("RED_QUICK") != "":
		_step = 20
		print("[runner] quick mode")


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
			if not _attack_captured and _player.state == 2 and at >= 0.07:
				_attack_captured = true
				_cap("03_attack.png")
			if _frames - _frames_attack == 30:
				var d = _main.get_node("World/HitDummies/HitDummy01")
				print("[runner] dummy01 hit_count=%d  dummy02 hit_count=%d" % [d.hit_count, _main.get_node("World/HitDummies/HitDummy02").hit_count])
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
			# 회피 테스트 1: 입력 없이 Shift → 시선 반대 방향으로 이동, 시선 유지
			_player.global_position = Vector3(0.0, 0.3, 0.0)
			_player.velocity = Vector3.ZERO
			_player.facing = Vector3(0, 0, -1)
			_step = 17; _frames_attack = _frames
		17:
			if _frames - _frames_attack == 5:
				Input.action_press("dodge")
			elif _frames - _frames_attack == 6:
				Input.action_release("dodge")
			if _frames - _frames_attack == 7:
				_cap("09_dodge_back.png")
			if _frames - _frames_attack > 60:
				var p: Vector3 = _player.global_position
				print("[runner] backstep: pos=%s facing=%s (expect z>0 ≈ +2.6, facing still (0,0,-1))" % [p, _player.facing])
				_step = 18; _frames_attack = _frames
		18:
			# 회피 테스트 2: ← 누른 채 Shift → 화면 왼쪽(월드 -x,+z)으로 점프하며 그쪽을 본다
			_player.global_position = Vector3(0.0, 0.3, 0.0)
			_player.velocity = Vector3.ZERO
			Input.action_press("move_left")
			_step = 19; _frames_attack = _frames
		19:
			if _frames - _frames_attack == 3:
				Input.action_press("dodge")
			elif _frames - _frames_attack == 4:
				Input.action_release("dodge"); Input.action_release("move_left")
			if _frames - _frames_attack == 5:
				_cap("10_dodge_left.png")
			if _frames - _frames_attack > 60:
				var p: Vector3 = _player.global_position
				print("[runner] dodge-left: pos=%s facing=%s (expect x<0,z>0 ; facing ≈ (-0.71,0,0.71))" % [p, _player.facing])
				_step = 20
		20:
			# 볼류메트릭/잔디 끈 비교 캡처
			_player.global_position = Vector3(-6.0, 0.3, 4.0)
			_player.velocity = Vector3.ZERO
			_main.get_node("World/LightShafts").visible = false
			_main.get_node("World/GrassField").visible = false
			_step = 21; _frames_attack = _frames
		21:
			if _frames - _frames_attack == 12:
				_cap("11_no_shafts_no_grass.png")
				_main.get_node("World/LightShafts").visible = true
				_main.get_node("World/GrassField").visible = true
			if _frames - _frames_attack == 24:
				_cap("12_shafts_grass.png"); _step = 22
		22:
			# 보행 사이클 확인: 오른쪽으로 걷는 동안 4프레임 간격 캡처 3장
			_player.global_position = Vector3(-9.0, 0.3, 6.0)
			_player.velocity = Vector3.ZERO
			Input.action_press("move_right")
			_step = 23; _frames_attack = _frames
		23:
			if _frames - _frames_attack == 10: _cap("16_walk_a.png")
			if _frames - _frames_attack == 13: _cap("16_walk_b.png")
			if _frames - _frames_attack == 16: _cap("16_walk_c.png")
			if _frames - _frames_attack > 18:
				_release_all(); _step = 24; _frames_attack = _frames
		24:
			if _frames - _frames_attack == 20: _cap("17_idle_a.png")
			if _frames - _frames_attack == 40: _cap("17_idle_b.png"); _step = 25
		25:
			# ---- 무기 테스트: 더미01(-3.5, 3.5) 의 동쪽 4 m 에서 서쪽을 보고 권총 사격
			_release_all()
			_player.global_position = Vector3(0.5, 0.3, 3.5)
			_player.velocity = Vector3.ZERO
			_player.facing = Vector3(-1, 0, 0)
			_dummy_hits0 = _main.get_node("World/HitDummies/HitDummy01").hit_count
			Input.action_press("quick_2")
			_step = 26; _frames_attack = _frames
		26:
			Input.action_release("quick_2")
			if _frames - _frames_attack in [3, 9, 15]:
				Input.action_press("attack")
			elif _frames - _frames_attack in [4, 10, 16]:
				Input.action_release("attack")
			if _frames - _frames_attack == 4:
				for c in _main.get_node("World").get_children():
					if c is Projectile:
						print("[runner] bullet at %s vel=%s" % [c.global_position, c.velocity])
			if _frames - _frames_attack == 6:
				_cap("18_pistol.png")
			if _frames - _frames_attack > 40:
				var d = _main.get_node("World/HitDummies/HitDummy01")
				print("[runner] pistol: dummy01 hits +%d (expect 3), ammo=%s" % [d.hit_count - _dummy_hits0, _player.inventory.ammo])
				_dummy_hits0 = d.hit_count
				Input.action_press("quick_5")
				_step = 27; _frames_attack = _frames
		27:
			Input.action_release("quick_5")
			if _frames - _frames_attack == 4:
				_cap("19_bomb.png")
			if _frames - _frames_attack > 60:
				var d = _main.get_node("World/HitDummies/HitDummy01")
				print("[runner] bomb: dummy01 hits +%d (expect 1), bombs left=%d" % [d.hit_count - _dummy_hits0, _player.inventory.count("bomb")])
				_dummy_hits0 = d.hit_count
				Input.action_press("quick_3")
				_step = 28; _frames_attack = _frames
		28:
			Input.action_release("quick_3")
			if _frames - _frames_attack == 3:
				Input.action_press("attack")
			if _frames - _frames_attack == 20:
				Input.action_release("attack")
			if _frames - _frames_attack == 8:
				_cap("18_rifle.png")
			if _frames - _frames_attack > 50:
				var d = _main.get_node("World/HitDummies/HitDummy01")
				print("[runner] rifle auto: dummy01 hits +%d (expect >3), ammo=%s" % [d.hit_count - _dummy_hits0, _player.inventory.ammo])
				Input.action_press("quick_4")
				_step = 29; _frames_attack = _frames
		29:
			Input.action_release("quick_4")
			if _frames - _frames_attack > 30:
				print("[runner] dagger: daggers left=%d (expect 9)" % _player.inventory.count("dagger"))
				_key(KEY_I)
				_step = 33; _frames_attack = _frames
		33:
			# 인벤토리 창: 열림 + 일시정지 확인, 2번 항목(단검 아닌 것) 선택 후 5번 키로 퀵슬롯 등록
			if _frames - _frames_attack == 3:
				var w = _main.get_node("InventoryWindow")
				print("[runner] inventory open=%s paused=%s" % [w.visible, _main.get_tree().paused])
				w._list.select(0)   # 정렬된 첫 항목 = bomb
				_key(KEY_1)
			if _frames - _frames_attack == 5:
				print("[runner] quick after assign: %s (expect bomb in slot 1, slot 5 empty)" % [_player.inventory.quick])
				_cap("20_inventory.png")
			if _frames - _frames_attack == 8:
				_key(KEY_I)
			if _frames - _frames_attack == 10:
				print("[runner] inventory closed=%s paused=%s" % [not _main.get_node("InventoryWindow").visible, _main.get_tree().paused])
				_player.inventory.set_quick(0, "sword"); _player.inventory.set_quick(4, "bomb")
				_key(KEY_W)
				_step = 34; _frames_attack = _frames
		34:
			if _frames - _frames_attack == 3:
				var w = _main.get_node("EquipmentWindow")
				print("[runner] equipment open=%s paused=%s" % [w.visible, _main.get_tree().paused])
				_cap("21_equipment.png")
				# 원거리 행의 '권총' 버튼 누르기
				for b in w._rows["ranged"].get_children().slice(1):
					if b.text.begins_with("권총"):
						b.pressed.emit()
			if _frames - _frames_attack == 5:
				print("[runner] equipped after button: %s active=%s" % [_player.inventory.equipped, _player.inventory.active_weapon()])
				_key(KEY_W)
			if _frames - _frames_attack == 8:
				print("[runner] equipment closed=%s paused=%s" % [not _main.get_node("EquipmentWindow").visible, _main.get_tree().paused])
				_step = 40
		40:
			print("[runner] done, frames=%d" % _frames)
			quit(0)
			return true
		30:
			# 임시 카메라: 플레이어 옆(+X)과 앞(-Z)에서 직교, 클립을 직접 seek 해 사이클 프레임 캡처
			if _frames < 5:
				return false
			_player.global_position = Vector3(-8.0, 0.3, 6.0)
			_player.velocity = Vector3.ZERO
			var cam := Camera3D.new()
			cam.name = "AnimViewCam"
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 2.2
			_main.get_node("World").add_child(cam)
			_view_cam = cam
			_anim_player = _player.get_node("AnimationPlayer")
			_anim_player.playback_default_blend_time = 0.0
			_step = 31; _view_i = 0
		31:
			var clip := "Walk"
			var n := 8
			if _view_i >= n * 2:
				_step = 32; _view_i = 0
				return false
			var side := _view_i < n
			var k := _view_i % n
			var base: Vector3 = _player.global_position + Vector3(0, 0.95, 0)
			if side:
				_view_cam.global_position = base + Vector3(4.0, 0.0, 0.0)
			else:
				_view_cam.global_position = base + Vector3(2.5, 0.0, -3.2)
			_view_cam.look_at(base, Vector3.UP)
			_view_cam.current = true
			_anim_player.play(clip, 0.0)
			_anim_player.seek(float(k) / float(n) * _anim_player.get_animation(clip).length, true)
			if _frames % 2 == 0:
				_cap("20_walk_%s_%d.png" % ["side" if side else "front", k])
				_view_i += 1
		32:
			var base: Vector3 = _player.global_position + Vector3(0, 0.95, 0)
			_view_cam.global_position = base + Vector3(2.5, 0.0, -3.2)
			_view_cam.look_at(base, Vector3.UP)
			_anim_player.play("Idle", 0.0)
			_anim_player.seek(float(_view_i) * 1.5, true)
			if _frames % 2 == 0:
				_cap("21_idle_front_%d.png" % _view_i)
				_view_i += 1
			if _view_i >= 4:
				print("[runner] done, frames=%d" % _frames)
				quit(0)
				return true
			quit(0)
			return true
	return false

var _frames_attack: int = 0
var _dummy_hits0: int = 0
var _view_cam: Camera3D
var _anim_player: AnimationPlayer
var _view_i: int = 0
var _attack_captured: bool = false

func _drive_toward(to: Vector3) -> void:
	var rig = _main.get_node("World/CameraRig")
	var r: Vector3 = rig.screen_right()
	var u: Vector3 = rig.screen_up()
	var sx := to.dot(r); var sy := to.dot(u)
	_release_all()
	if sx > 0.2: Input.action_press("move_right")
	elif sx < -0.2: Input.action_press("move_left")
	if sy > 0.2: Input.action_press("move_up")
	elif sy < -0.2: Input.action_press("move_down")

## 실제 키 이벤트 (눌림+뗌) 를 디스패치한다 — _unhandled_input 기반 토글용
func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _release_all() -> void:
	for a in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(a)

func _cap(name: String) -> void:
	var path: String = _main.call("capture_screenshot", name)
	print("[runner] captured %s" % name)
