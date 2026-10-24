## 전투 디렉터 (GDD §11, §13): 전투 상태, 패턴 선택(고정 시퀀스 / 수동 테스트 메뉴), 사망·승리·재시작.
## IDLE → APPROACH → COMBAT → VICTORY | DEAD → (R) RETRY
class_name CombatDirector
extends Node

signal battle_state_changed(state: int)
signal event_logged(line: String)

enum BattleState { IDLE, APPROACH, COMBAT, VICTORY, DEAD }

@export var boss_path: NodePath
@export var player_path: NodePath
@export var camera_rig_path: NodePath
@export var patterns_json: String = BossPatternLibrary.DEFAULT_PATH
## true = 고정 시퀀스 자동 진행, false = F5 로 선택한 패턴 1개만 수동 실행
@export var auto_sequence: bool = true
@export var player_start: Vector3 = Vector3(0, 0.3, 4.0)
@export var log_path: String = "user://reaction_log.csv"

var state: BattleState = BattleState.IDLE
var boss: BossController
var player: PlayerController
var camera_rig: CameraFollow
var fatal: FatalReactionController
var resolver: BossHitResolver
var camera: CombatCameraDirector
var router: CombatInputRouter
var result_ui: BattleResultController

var patterns: Dictionary = {}
var sequence: Array = []
var seq_index: int = 0
var selected_index: int = 0
var last_pattern_id: String = "-"
var death_reason: String = ""
var retries: int = 0
var _death_us: int = 0
var _retry_started_us: int = 0
var log_lines: Array[String] = []


func _ready() -> void:
	boss = get_node(boss_path)
	player = get_node(player_path)
	camera_rig = get_node(camera_rig_path)
	var lib := BossPatternLibrary.load_json(patterns_json)
	patterns = lib["patterns"]
	sequence = lib["sequence"]
	# 하위 컨트롤러 생성/연결
	resolver = BossHitResolver.new()
	resolver.name = "BossHitResolver"
	resolver.director = self
	resolver.player = player
	add_child(resolver)
	camera = CombatCameraDirector.new()
	camera.name = "CombatCameraDirector"
	add_child(camera)
	camera.setup(camera_rig, boss, player)
	fatal = FatalReactionController.new()
	fatal.name = "FatalReactionController"
	fatal.player = player
	fatal.camera = camera
	fatal.camera_rig = camera_rig
	fatal.resolver = resolver
	add_child(fatal)
	# 입력 라우터는 루트 뷰포트에 둔다 (World 는 SubViewport 라 _input 이 오지 않는다)
	router = CombatInputRouter.new()
	router.name = "CombatInputRouter"
	get_tree().root.add_child.call_deferred(router)
	router.new_action.connect(fatal.on_new_action)
	router.command.connect(_on_command)
	fatal.resolved.connect(_on_fatal_resolved)
	fatal.finished.connect(_on_fatal_finished)
	boss.player = player
	boss.camera_rig = camera_rig
	boss.resolver = resolver
	boss.fatal = fatal
	boss.pattern_started.connect(_on_pattern_started)
	boss.pattern_finished.connect(_on_pattern_finished)
	boss.pattern_skipped.connect(_on_pattern_skipped)
	boss.died.connect(boss_died)
	player.combat_director = self
	result_ui = get_node_or_null("../../BattleResult") as BattleResultController
	if not FileAccess.file_exists(log_path):
		var f := FileAccess.open(log_path, FileAccess.WRITE)
		if f:
			f.store_line("unix_time,pattern,action,reaction_ms,result,fps,time_scale")
	print("[Combat] patterns=%s sequence=%s" % [patterns.keys(), sequence])
	reset_battle()


func _physics_process(_delta: float) -> void:
	if state == BattleState.APPROACH and boss.state != BossController.State.APPROACH:
		_set_state(BattleState.COMBAT)
	if state != BattleState.COMBAT and state != BattleState.APPROACH:
		return
	if auto_sequence and boss.state == BossController.State.IDLE and not sequence.is_empty():
		var id: String = sequence[seq_index % sequence.size()]
		seq_index += 1
		boss.request_pattern(patterns[id])


func _exit_tree() -> void:
	if router and is_instance_valid(router):
		router.queue_free()


func _on_command(cmd: StringName) -> void:
	match cmd:
		&"retry":
			if state == BattleState.DEAD or state == BattleState.VICTORY:
				_retry_started_us = Time.get_ticks_usec()
				retries += 1
				reset_battle()
				print("[Combat] retry #%d in %.1f ms" % [retries, float(Time.get_ticks_usec() - _retry_started_us) / 1000.0])
		&"debug_pattern_mode":
			auto_sequence = not auto_sequence
			log_event("-", "", 0, "mode %s" % ("auto" if auto_sequence else "manual"))
		&"debug_pattern_prev":
			selected_index = (selected_index - 1 + patterns.size()) % patterns.size()
		&"debug_pattern_next":
			selected_index = (selected_index + 1) % patterns.size()
		&"debug_pattern_fire":
			fire_selected()


## 수동 실행 (F5): 선택한 패턴 1개
func fire_selected() -> void:
	if state != BattleState.COMBAT and state != BattleState.APPROACH:
		return
	var p := selected_pattern()
	if p and boss.state == BossController.State.IDLE:
		boss.request_pattern(p)


func fire_pattern(id: String) -> bool:
	if not patterns.has(id) or boss.state != BossController.State.IDLE:
		return false
	boss.request_pattern(patterns[id])
	return true


func selected_pattern() -> BossAttackPattern:
	var ids := patterns.keys()
	ids.sort()
	if ids.is_empty():
		return null
	return patterns[ids[selected_index % ids.size()]]


func _on_pattern_started(p: BossAttackPattern) -> void:
	last_pattern_id = p.id
	if not p.is_fatal():
		# 일반 패턴의 사망 표시에 직전 치명적 패턴의 입력/반응 시간이 섞이지 않게
		fatal.last_action = &""
		fatal.last_reaction_ms = -1.0
		fatal.last_result = ""
	log_event(p.id, "", 0, "start")


func _on_pattern_finished(p: BossAttackPattern) -> void:
	if p:
		log_event(p.id, "", 0, "finished")


func _on_pattern_skipped(p: BossAttackPattern, reason: String) -> void:
	log_event(p.id, "", 0, "skipped: " + reason)


func _on_fatal_resolved(p: BossAttackPattern, success: bool, action: StringName, ms: float, reason: String) -> void:
	log_event(p.id, String(action), ms, reason)


func _on_fatal_finished(_p: BossAttackPattern) -> void:
	pass


## 즉사 (BossHitResolver 전용 진입점)
func player_died(reason: String) -> void:
	if state != BattleState.COMBAT and state != BattleState.APPROACH:
		return
	death_reason = reason
	_death_us = Time.get_ticks_usec()
	fatal.abort()
	Engine.time_scale = 1.0
	camera.reset_immediate()
	boss.stop_all()
	player.die()
	_set_state(BattleState.DEAD)
	if result_ui:
		result_ui.show_death(reason, fatal.last_reaction_ms, fatal.last_action)
	log_event(last_pattern_id, String(fatal.last_action), fatal.last_reaction_ms, "DEAD: " + reason)


func boss_died() -> void:
	if state == BattleState.VICTORY:
		return
	fatal.abort()
	Engine.time_scale = 1.0
	camera.reset_immediate()
	player.end_combat_lock()
	_set_state(BattleState.VICTORY)
	if result_ui:
		result_ui.show_victory()
	log_event(last_pattern_id, "", 0, "VICTORY")


## 전투 초기 상태 (R): 보스/플레이어 위치·HP·콤보·버퍼·무적·타임스케일·카메라 전부 초기화
func reset_battle() -> void:
	fatal.abort()
	Engine.time_scale = 1.0
	camera.reset_immediate()
	boss.reset_boss()
	player.reset_for_retry(player_start, Vector3(0, 0, -1))
	seq_index = 0
	last_pattern_id = "-"
	death_reason = ""
	if result_ui:
		result_ui.hide_all()
	_set_state(BattleState.APPROACH)
	log_event("-", "", 0, "reset")


func _set_state(s: BattleState) -> void:
	state = s
	battle_state_changed.emit(s)


func state_name() -> String:
	return BattleState.keys()[state]


func can_open_menus() -> bool:
	return state == BattleState.COMBAT or state == BattleState.APPROACH


func log_event(pattern_id: String, action: String, ms: float, result: String) -> void:
	var line := "%s  %s  %s  %s" % [pattern_id, action if action != "" else "-", ("%.1f ms" % ms) if ms > 0.0 else "-", result]
	log_lines.append(line)
	if log_lines.size() > 8:
		log_lines.pop_front()
	event_logged.emit(line)
	print("[Combat] " + line)
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line("%d,%s,%s,%.1f,%s,%d,%.2f" % [Time.get_unix_time_from_system(), pattern_id, action, ms, result, Engine.get_frames_per_second(), Engine.time_scale])
