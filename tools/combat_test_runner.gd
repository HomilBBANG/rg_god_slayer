## 보스 전투 자동 검증 (GDD §14). `godot --path . -s tools/combat_test_runner.gd`
## - 실제 키 이벤트(parse_input_event) 를 현실 시간 기준으로 주입해 0.20 s 판단 창을 검사한다.
## - 199 ms / 201 ms 경계는 프레임 간격보다 촘촘하므로 합성 타임스탬프로 FatalReactionController 를 직접 검사한다.
## 환경 변수: RED_PIXEL_SCALE=3 (가벼운 렌더로 FPS 확보), RED_NO_SHAFTS=1, RED_FPS_CAP=30 (30 FPS 재검), RED_VIDEO=1 (F01 프레임 녹화)
extends SceneTree

var main: Node
var player: PlayerController
var boss: BossController
var director: CombatDirector
var fatal: FatalReactionController
var rig: CameraFollow
var results: Array = []
var skipped_log: Array = []
var _video_frames: int = 0
var _video_on: bool = false
## 캡처 모드(풀 품질 + PNG 저장)는 프레임당 수백 ms 라 대기 타임아웃(현실 초)을 늘린다
var _timeout_scale: float = 1.0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/BossTestArena.tscn")
	main = packed.instantiate()
	root.add_child(main)
	player = main.get_node("World/Player")
	boss = main.get_node("World/Boss")
	director = main.get_node("World/CombatDirector")
	rig = main.get_node("World/CameraRig")
	boss.pattern_skipped.connect(func(p, why): skipped_log.append("%s: %s" % [p.id, why]))
	_run()


func _process(_delta: float) -> bool:
	if CombatClock.virtual_enabled:
		CombatClock.virtual_us += 33_333   # --fixed-fps 30 과 짝: 프레임당 1/30 s
	if _video_on:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("user://video/f%04d.png" % _video_frames)
		_video_frames += 1
	return false


# ---------------------------------------------------------------- 도우미

func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _until(pred: Callable, timeout_s: float = 6.0) -> bool:
	var t0 := Time.get_ticks_usec()
	while not pred.call():
		if Time.get_ticks_usec() - t0 > int(timeout_s * _timeout_scale * 1_000_000.0):
			return false
		await process_frame
	return true


func _key_event(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _key(code: Key) -> void:
	_key_event(code, true)
	_key_event(code, false)


func _check(name: String, ok: bool, detail: String = "") -> void:
	results.append([name, ok, detail])
	print("[test] %s  %s  %s" % ["PASS" if ok else "FAIL", name, detail])


func _setup(player_pos: Vector3, boss_pos: Vector3 = Vector3(0, 0, -4)) -> void:
	director.auto_sequence = false
	director.reset_battle()
	await _frames(2)
	player.global_position = player_pos
	player.velocity = Vector3.ZERO
	boss.global_position = boss_pos
	await _frames(2)


func _fire_wait_decision(id: String) -> bool:
	var ok := director.fire_pattern(id)
	if not ok:
		return false
	return await _until(func(): return fatal.phase == FatalReactionController.Phase.DECISION, 8.0)


## 판단 창이 열리고 ms 가 지난 뒤 키를 주입한다. 실제 주입 시각(ms) 을 돌려준다.
func _inject_after(ms: float, code: Key) -> float:
	await _until(func(): return Time.get_ticks_usec() - fatal.decision_started_us >= int(ms * 1000.0), 2.0)
	var at := float(Time.get_ticks_usec() - fatal.decision_started_us) / 1000.0
	_key(code)
	return at


func _wait_fatal_done() -> bool:
	return await _until(func(): return not fatal.is_active() and boss.state == BossController.State.IDLE or director.state == CombatDirector.BattleState.DEAD, 8.0)


func _is_dead() -> bool:
	return director.state == CombatDirector.BattleState.DEAD


func _cap(name: String) -> void:
	main.call("capture_screenshot", name)


# ---------------------------------------------------------------- 테스트

func _run() -> void:
	await _frames(3)   # _ready 가 끝난 뒤 하위 컨트롤러를 잡는다
	fatal = director.fatal
	director.auto_sequence = false
	director.reset_battle()
	if OS.get_environment("RED_CAPTURE") != "":
		await _captures()
		quit(0)
		return
	var fps_cap := OS.get_environment("RED_FPS_CAP")
	if fps_cap != "":
		Engine.max_fps = int(fps_cap)
	print("[test] start  fps=%d  pixel_scale=%d  max_fps=%d" % [Engine.get_frames_per_second(), rig.pixel_scale, Engine.max_fps])
	await _frames(30)
	var fps0 := Engine.get_frames_per_second()
	print("[test] measured fps ≈ %d" % fps0)
	var near := Vector3(0, 0.3, -1.6)   # 보스(0,0,-4) 에서 2.4 m: 즉시 패턴 시작

	# 1. F01 → 약 120 ms 에 '→' : 회피 성공
	await _setup(near)
	var ok := await _fire_wait_decision("F01")
	_check("F01 decision opens (focus→decision)", ok, "time_scale=%.2f size=%.1f" % [Engine.time_scale, rig.ortho_size])
	_check("F01 slow-motion & zoom during decision", absf(Engine.time_scale - 0.18) < 0.01 and absf(rig.ortho_size - 9.5) < 0.6, "time_scale=%.2f size=%.2f" % [Engine.time_scale, rig.ortho_size])
	_cap("22_f01_decision.png")
	var at := await _inject_after(110.0, KEY_RIGHT)
	await _frames(2)
	_check("F01 → within window = dodge success", fatal.last_result == "success_dodge" and not _is_dead(), "injected @%.0f ms, judged %.1f ms" % [at, fatal.last_reaction_ms])
	await _frames(3)
	_cap("23_f01_dodge.png")
	await _wait_fatal_done()
	_check("after success: time_scale 1.0, camera size 15", absf(Engine.time_scale - 1.0) < 0.001 and absf(rig.ortho_size - 15.0) < 0.01 and not rig.focus_override, "ts=%.2f size=%.2f" % [Engine.time_scale, rig.ortho_size])

	# 2. F01 → 창 만료 뒤(> 200 ms) 입력: 사망(timeout)
	await _setup(near)
	ok = await _fire_wait_decision("F01")
	at = await _inject_after(215.0, KEY_RIGHT)
	await _frames(2)
	_check("F01 → after 200 ms = death (timeout)", _is_dead() and fatal.last_result == "fail_timeout", "injected @%.0f ms, reason=%s" % [at, director.death_reason])
	_check("death: time_scale 1.0 & camera reset", absf(Engine.time_scale - 1.0) < 0.001 and absf(rig.ortho_size - 15.0) < 0.01, "")
	_cap("24_death.png")

	# 3. F01 ← : 잘못된 방향 → 사망 / F01 X : 패링 불가 → 사망
	await _setup(near)
	ok = await _fire_wait_decision("F01")
	at = await _inject_after(60.0, KEY_LEFT)
	await _frames(2)
	_check("F01 ← (wrong direction) = death", _is_dead() and fatal.last_result.begins_with("fail_wrong_action"), "@%.0f ms %s" % [at, fatal.last_result])
	await _setup(near)
	ok = await _fire_wait_decision("F01")
	at = await _inject_after(60.0, KEY_X)
	await _frames(2)
	_check("F01 X (not parryable) = death", _is_dead() and fatal.last_result.begins_with("fail_wrong_action"), "@%.0f ms %s" % [at, fatal.last_result])

	# 4. F04 X @ ~150 ms : 패링 성공 + 보스 경직 / F04 방향키 : 사망
	await _setup(near)
	ok = await _fire_wait_decision("F04")
	_cap("25_f04_decision.png")
	at = await _inject_after(130.0, KEY_X)
	await _frames(2)
	_check("F04 X = parry success", fatal.last_result == "success_parry" and not _is_dead(), "@%.0f ms judged %.1f ms boss=%s parry_count=%d" % [at, fatal.last_reaction_ms, boss.state_name(), boss.parry_count])
	_check("F04 parry → boss STAGGER", boss.state == BossController.State.STAGGER, boss.state_name())
	await _wait_fatal_done()
	await _setup(near)
	ok = await _fire_wait_decision("F04")
	at = await _inject_after(60.0, KEY_UP)
	await _frames(2)
	_check("F04 ↑ (parry-only) = death", _is_dead() and fatal.last_result.begins_with("fail_wrong_action"), "@%.0f ms" % at)

	# 5. F05 ↓ 와 X 둘 다 성공 (서로 다른 결과)
	await _setup(near)
	ok = await _fire_wait_decision("F05")
	at = await _inject_after(60.0, KEY_DOWN)
	await _frames(2)
	_check("F05 ↓ = dodge success", fatal.last_result == "success_dodge" and not _is_dead(), "@%.0f ms" % at)
	await _wait_fatal_done()
	await _setup(near)
	ok = await _fire_wait_decision("F05")
	at = await _inject_after(60.0, KEY_X)
	await _frames(2)
	_check("F05 X = parry success", fatal.last_result == "success_parry" and not _is_dead(), "@%.0f ms" % at)
	await _wait_fatal_done()

	# 6. F04 에서 X 를 판단 창 전부터 누르고 있음 → 자동 성공 없음 (timeout 사망)
	await _setup(near)
	_key_event(KEY_X, true)
	await _frames(2)
	ok = await _fire_wait_decision("F04")
	await _until(func(): return _is_dead(), 2.0)
	_key_event(KEY_X, false)
	_check("F04 X held before window = no auto success (timeout death)", _is_dead() and fatal.last_result == "fail_timeout", fatal.last_result)

	# 7. Z 3타 중 FATAL 진입 → Z 취소, 방향 입력 정상
	await _setup(near)
	Input.action_press("attack")
	await _frames(2)
	director.fire_pattern("F01")
	await _until(func(): return fatal.phase == FatalReactionController.Phase.DECISION, 8.0)
	var st := player.state_name()
	Input.action_release("attack")
	at = await _inject_after(60.0, KEY_RIGHT)
	await _frames(2)
	_check("Z combo interrupted by FATAL; → still works", st == "FATAL_DECISION" and fatal.last_result == "success_dodge", "player during decision = %s" % st)
	await _wait_fatal_done()

	# 8. Z 3타 연계: 버퍼로 3타까지 이어지고 피해 1+1+2
	await _setup(Vector3(0, 0.3, -2.2))
	var hp0 := boss.hp
	Input.action_press("attack")
	await _frames(1)
	Input.action_release("attack")
	var seen := {}
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 1_400_000:
		seen[player.state_name().substr(0, 6)] = true
		if player.state == PlayerController.State.ATTACK and player._attack_time > 0.14 and not player._combo_buffered:
			Input.action_press("attack")
			await process_frame
			Input.action_release("attack")
		await process_frame
	_check("Z 3-hit combo: boss hp 12 → 8 (1+1+2)", boss.hp == hp0 - 4, "hp %d → %d" % [hp0, boss.hp])

	# 9. 199 / 201 ms 경계 (합성 타임스탬프 — 프레임과 무관)
	await _setup(near)
	ok = await _fire_wait_decision("F01")
	fatal.on_new_action(&"DODGE_RIGHT", fatal.decision_started_us + 199_000)
	_check("boundary: → at 199 ms = success", fatal.last_result == "success_dodge" and absf(fatal.last_reaction_ms - 199.0) < 0.01, "%.1f ms" % fatal.last_reaction_ms)
	await _wait_fatal_done()
	await _setup(near)
	ok = await _fire_wait_decision("F01")
	fatal.on_new_action(&"DODGE_RIGHT", fatal.decision_started_us + 201_000)
	var ignored := not fatal.decision_resolved
	await _until(func(): return _is_dead(), 2.0)
	_check("boundary: → at 201 ms = ignored → timeout death", ignored and _is_dead() and fatal.last_result == "fail_timeout", fatal.last_result)
	await _setup(near)
	ok = await _fire_wait_decision("F01")
	fatal.on_new_action(&"DODGE_LEFT", fatal.decision_started_us + 50_000)
	fatal.on_new_action(&"DODGE_RIGHT", fatal.decision_started_us + 60_000)
	await _frames(2)
	_check("first input decides: ← then → = death (no second chance)", _is_dead() and fatal.last_result.begins_with("fail_wrong"), fatal.last_result)

	# 10. R 재도전: 상태/타임스케일/카메라/위치 초기화
	var r0 := Time.get_ticks_usec()
	_key(KEY_R)
	await _frames(2)
	var rt := float(Time.get_ticks_usec() - r0) / 1000.0
	_check("R retry resets (alive, ts 1, size 15, positions)", not _is_dead() and absf(Engine.time_scale - 1.0) < 0.001 and absf(rig.ortho_size - 15.0) < 0.01 and player.global_position.distance_to(director.player_start) < 0.3 and boss.hp == boss.max_hp and player.state_name() == "IDLE", "retry %.0f ms, player %s" % [rt, player.global_position])

	# 11. 일반 패턴 N01: 범위 안이면 즉사, 범위 밖으로 걸어 나가면 생존
	await _setup(near)
	director.fire_pattern("N01")
	await _until(func(): return boss.state == BossController.State.WINDUP, 4.0)
	_cap("26_n01_windup.png")
	await _until(func(): return _is_dead(), 3.0)
	_check("N01 hit = instant death", _is_dead() and director.death_reason.begins_with("N01"), director.death_reason)
	await _setup(near)
	director.fire_pattern("N01")
	await _until(func(): return boss.state == BossController.State.WINDUP, 4.0)
	Input.action_press("move_down")   # 화면 아래로 걸어 나간다 (보스는 화면 위쪽)
	var fin := await _until(func(): return boss.state == BossController.State.IDLE or _is_dead(), 4.0)
	Input.action_release("move_down")
	_check("N01 avoided by moving out of range", fin and not _is_dead(), "player %s" % player.global_position)

	# 12. 안전 방향 도착점이 돌담에 막힘 → 패턴을 고르지 않음
	skipped_log.clear()
	await _setup(Vector3(7.4, 0.3, 0.0), Vector3(5.2, 0, -1.4))
	director.fire_pattern("F01")
	await _until(func(): return skipped_log.size() > 0 or fatal.is_active(), 4.0)
	_check("F01 skipped when → destination blocked by wall", skipped_log.size() > 0 and not fatal.is_active(), skipped_log[0] if skipped_log.size() > 0 else "not skipped")

	# 13. 30회 반복: 매번 time_scale / 카메라 복구
	var bad := 0
	for i in 30:
		await _setup(near)
		ok = await _fire_wait_decision("F01" if i % 2 == 0 else "F04")
		await _inject_after(40.0, KEY_RIGHT if i % 2 == 0 else KEY_X)
		await _wait_fatal_done()
		if _is_dead() or absf(Engine.time_scale - 1.0) > 0.001 or absf(rig.ortho_size - 15.0) > 0.01 or rig.focus_override:
			bad += 1
	_check("30 fatal cycles: camera/time_scale restored every time", bad == 0, "bad=%d" % bad)


	var fps1 := Engine.get_frames_per_second()
	var passed := 0
	for r in results:
		if r[1]:
			passed += 1
	print("[test] RESULT %d/%d passed   fps≈%d..%d  max_fps=%d" % [passed, results.size(), fps0, fps1, Engine.max_fps])
	var f := FileAccess.open("user://combat_test_results.txt", FileAccess.WRITE)
	if f:
		f.store_line("fps≈%d..%d max_fps=%d pixel_scale=%d" % [fps0, fps1, Engine.max_fps, rig.pixel_scale])
		for r in results:
			f.store_line("%s | %s | %s" % ["PASS" if r[1] else "FAIL", r[0], r[2]])
	quit(0 if passed == results.size() else 1)


# ---------------------------------------------------------------- 캡처 / 영상 (RED_CAPTURE=1, 풀 품질, --fixed-fps 30 + 가상 시계)
## 저사양 소프트웨어 렌더에서도 현실 시간 비율이 맞도록 판정 시계를 프레임당 1/30 s 로 전진시킨다.
## 입력은 합성 타임스탬프(판단 창 열림 + 100 ms)로 넣는다. 로직 검증은 _run() 의 실제 키 경로가 담당.

func _captures() -> void:
	_timeout_scale = 15.0
	CombatClock.virtual_enabled = true
	CombatClock.virtual_us = Time.get_ticks_usec()
	main.get_node("AttackDebugOverlay").visible = true
	var near := Vector3(0, 0.3, -1.6)
	# F01 판단 창 → 성공 회피
	await _setup(near)
	director.fire_pattern("F01")
	await _until(func(): return fatal.phase == FatalReactionController.Phase.DECISION, 10.0)
	await _frames(2)
	_cap("22_f01_decision.png")
	fatal.on_new_action(&"DODGE_RIGHT", fatal.decision_started_us + 100_000)
	await _frames(4)
	_cap("23_f01_dodge.png")
	await _wait_fatal_done()
	# 창 만료 사망
	await _setup(near)
	director.fire_pattern("F01")
	await _until(func(): return _is_dead(), 10.0)
	await _frames(12)
	_cap("24_death.png")
	# F04 판단 창 (반짝임)
	await _setup(near)
	director.fire_pattern("F04")
	await _until(func(): return fatal.phase == FatalReactionController.Phase.DECISION, 10.0)
	await _frames(1)
	_cap("25_f04_decision.png")
	fatal.on_new_action(&"PARRY_X", fatal.decision_started_us + 100_000)
	await _wait_fatal_done()
	# N01 예고
	await _setup(near)
	director.fire_pattern("N01")
	await _until(func(): return boss.state == BossController.State.WINDUP, 6.0)
	await _frames(8)
	_cap("26_n01_windup.png")
	await _until(func(): return _is_dead(), 6.0)
	# 영상: F01 회피 → F04 패링 → N02 돌진 회피 → N01 피격 사망 → R 재도전
	DirAccess.make_dir_recursive_absolute("user://video")
	await _setup(Vector3(0, 0.3, -1.0))
	_video_on = true
	await _frames(15)
	director.fire_pattern("F01")
	await _until(func(): return fatal.phase == FatalReactionController.Phase.DECISION, 10.0)
	await _until(func(): return CombatClock.now_us() - fatal.decision_started_us >= 100_000, 2.0)
	fatal.on_new_action(&"DODGE_RIGHT", CombatClock.now_us())
	await _wait_fatal_done()
	await _frames(20)
	director.fire_pattern("F04")
	await _until(func(): return fatal.phase == FatalReactionController.Phase.DECISION, 10.0)
	await _until(func(): return CombatClock.now_us() - fatal.decision_started_us >= 120_000, 2.0)
	fatal.on_new_action(&"PARRY_X", CombatClock.now_us())
	await _wait_fatal_done()
	await _frames(20)
	director.fire_pattern("N01")
	await _until(func(): return _is_dead(), 6.0)
	await _frames(30)
	_key(KEY_R)
	await _frames(25)
	_video_on = false
	print("[test] video frames=%d" % _video_frames)
