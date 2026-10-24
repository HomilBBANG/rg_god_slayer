## 치명적 패턴 대응 (GDD §4, §13): FOCUS(0.10 s 현실) → DECISION(0.20 s 현실) → RESOLVE → RECOVER.
## 판정 시계는 CombatClock.now_us() 만 쓴다. Engine.time_scale 은 세계만 느리게 하고 반응 창을 늘리지 않는다.
## 결정은 판단 창이 열린 뒤의 **첫 신규 키다운** 하나로만 확정된다 (decision_resolved).
class_name FatalReactionController
extends Node

signal decision_opened(pattern: BossAttackPattern)
signal resolved(pattern: BossAttackPattern, success: bool, action: StringName, reaction_ms: float, reason: String)
signal finished(pattern: BossAttackPattern)

enum Phase { NONE, FOCUS, DECISION, RESOLVE, HOLD, RECOVER }

## 복귀 시간 (현실 초) — GDD 0.16~0.22
@export var recover_real_seconds: float = 0.18
## 패링 성공 임팩트 멈춤 (현실 초, 선택 기능)
@export var parry_hitstop_real_seconds: float = 0.05

var phase: Phase = Phase.NONE
var pattern: BossAttackPattern
var boss: BossController
var player: PlayerController
var camera: CombatCameraDirector
var camera_rig: CameraFollow
var resolver: BossHitResolver
## 스킬: 순발력(판단 창), 판단력(슬로모션 유지)
var skills: PlayerSkills

var pattern_instance_id: int = 0
var decision_started_us: int = 0
var decision_resolved: bool = false
var last_action: StringName = &""
var last_reaction_ms: float = -1.0
var last_result: String = ""
var _phase_start_us: int = 0
var _focus_start_us: int = 0
var _hitstop_until_us: int = 0
var _recover_from_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 보스가 예고(WINDUP)를 마친 순간 호출. 포커스 시작.
func begin(p: BossAttackPattern, b: BossController) -> void:
	pattern = p
	boss = b
	pattern_instance_id += 1
	decision_resolved = false
	last_action = &""
	last_reaction_ms = -1.0
	last_result = ""
	phase = Phase.FOCUS
	_phase_start_us = CombatClock.now_us()
	_focus_start_us = _phase_start_us
	Engine.time_scale = p.time_scale
	camera.focus(p.zoom_size, p.focus_real_seconds)
	player.begin_fatal()


func _process(_delta: float) -> void:
	var now := CombatClock.now_us()
	match phase:
		Phase.FOCUS:
			if now - _phase_start_us >= int(pattern.focus_real_seconds * 1_000_000.0):
				_open_decision()
		Phase.DECISION:
			check_decision_timeout()
		Phase.HOLD:
			# 판단력: 성공 뒤에도 슬로모션을 slow_seconds (포커스 시작 기준) 까지 유지
			if now < _hitstop_until_us:
				return
			if now - _focus_start_us >= int(slow_seconds() * 1_000_000.0):
				_start_recover()
		Phase.RECOVER:
			if now < _hitstop_until_us:
				return
			var dur := int(recover_real_seconds * 1_000_000.0)
			var k := clampf(float(now - _phase_start_us) / float(dur), 0.0, 1.0)
			Engine.time_scale = lerpf(_recover_from_scale, 1.0, k)
			if k >= 1.0:
				Engine.time_scale = 1.0
				phase = Phase.NONE
				finished.emit(pattern)


func _open_decision() -> void:
	phase = Phase.DECISION
	decision_resolved = false
	decision_started_us = CombatClock.now_us()
	boss.on_decision_opened()
	decision_opened.emit(pattern)


## CombatInputRouter.new_action → 여기. 창 밖/중복/다른 단계면 무시.
func on_new_action(action: StringName, usec: int) -> void:
	if phase != Phase.DECISION or decision_resolved:
		return
	var elapsed := usec - decision_started_us
	var limit := int(decision_seconds() * 1_000_000.0)
	if elapsed < 0 or elapsed > limit:
		return   # 타임아웃 검사가 처리
	decision_resolved = true
	last_action = action
	last_reaction_ms = float(elapsed) / 1000.0
	if pattern.allowed_actions.has(String(action)):
		_resolve_success(action)
	else:
		_resolve_death("wrong_action(%s)" % action)


func check_decision_timeout() -> void:
	if phase == Phase.DECISION and not decision_resolved:
		var elapsed := CombatClock.now_us() - decision_started_us
		if elapsed > int(decision_seconds() * 1_000_000.0):
			decision_resolved = true
			last_action = &""
			last_reaction_ms = float(elapsed) / 1000.0
			_resolve_death("timeout")


## 남은 판단 시간 (ms). 판단 중이 아니면 -1
func remaining_ms() -> float:
	if phase != Phase.DECISION:
		return -1.0
	return maxf(0.0, decision_seconds() * 1000.0 - float(CombatClock.now_us() - decision_started_us) / 1000.0)


## 판단 창 길이 (현실 초): 패턴 기본값 + 순발력 보너스
func decision_seconds() -> float:
	var bonus := (skills.decision_seconds() - PlayerSkills.DECISION_BASE) if skills else 0.0
	return pattern.decision_real_seconds + bonus


## 슬로모션 유지 (현실 초, 포커스 시작부터): 판단력
func slow_seconds() -> float:
	return skills.slow_seconds() if skills else PlayerSkills.SLOW_BASE


func _resolve_success(action: StringName) -> void:
	phase = Phase.RESOLVE
	var is_parry := action == &"PARRY_X"
	last_result = "success_parry" if is_parry else "success_dodge"
	if is_parry:
		player.scripted_parry()
		boss.fatal_parried()
		_hitstop_until_us = CombatClock.now_us() + int(parry_hitstop_real_seconds * 1_000_000.0)
	else:
		var dir := screen_dir_world(String(action).trim_prefix("DODGE_"))
		player.scripted_dodge(dir, pattern.reaction_step_meters, 0.12)
		boss.fatal_strike(true)
		_hitstop_until_us = 0
	resolved.emit(pattern, true, action, last_reaction_ms, last_result)
	phase = Phase.HOLD


func _resolve_death(reason: String) -> void:
	phase = Phase.RESOLVE
	last_result = "fail_" + reason
	resolved.emit(pattern, false, last_action, last_reaction_ms, last_result)
	boss.fatal_strike(false)
	resolver.kill_player(pattern, reason)
	# 사망 처리(director)가 time_scale/카메라를 즉시 복구한다
	phase = Phase.NONE


func _start_recover() -> void:
	phase = Phase.RECOVER
	_phase_start_us = CombatClock.now_us()
	_recover_from_scale = Engine.time_scale
	camera.release(recover_real_seconds)


## 외부 강제 종료 (사망/재시작/승리)
func abort() -> void:
	phase = Phase.NONE
	decision_resolved = true
	Engine.time_scale = 1.0


func is_active() -> bool:
	return phase != Phase.NONE


func phase_name() -> String:
	return ["NONE", "FATAL_FOCUS", "FATAL_DECISION", "FATAL_RESOLVE", "FATAL_SLOW_HOLD", "FATAL_RECOVER"][phase]


## 화면 방향 이름 → 월드 XZ 단위 벡터 (최초 일반 카메라의 고정 화면 방향, 카메라 회전 없음)
func screen_dir_world(dir_name: String) -> Vector3:
	match dir_name:
		"RIGHT":
			return camera_rig.screen_right()
		"LEFT":
			return -camera_rig.screen_right()
		"UP":
			return camera_rig.screen_up()
		"DOWN":
			return -camera_rig.screen_up()
	return Vector3.ZERO
