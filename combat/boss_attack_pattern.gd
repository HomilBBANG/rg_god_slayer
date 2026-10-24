## 보스 공격 패턴 데이터 (GDD v0.3 §12). JSON(combat/boss_attack_patterns.json) 에서 읽어 Resource 로 만든다.
## 시간 단위: *_game_seconds 는 Engine.time_scale 의 영향을 받는 게임 시간, *_real_seconds 는 현실 시간.
class_name BossAttackPattern
extends Resource

@export var id: String = ""
## "NORMAL" | "FATAL_CINEMATIC"
@export var category: String = "NORMAL"
@export var telegraph_game_seconds: float = 0.4
@export var active_game_seconds: float = 0.1
@export var recovery_game_seconds: float = 0.3
@export var focus_real_seconds: float = 0.1
@export var decision_real_seconds: float = 0.2
@export var time_scale: float = 0.18
@export var zoom_size: float = 9.5
## "DODGE_UP" | "DODGE_DOWN" | "DODGE_LEFT" | "DODGE_RIGHT" | "PARRY_X"
@export var allowed_actions: PackedStringArray = []
@export var parryable: bool = false
## "UP" | "DOWN" | "LEFT" | "RIGHT" (화면 기준)
@export var screen_safe_directions: PackedStringArray = []
@export var reaction_step_meters: float = 1.8
@export var post_success_boss_recovery_game_seconds: float = 0.7
@export var lethal_on_hit: bool = true
@export var visual_cue: String = ""
@export var requires_clear_destination: bool = false


func is_fatal() -> bool:
	return category == "FATAL_CINEMATIC"


static func from_dict(d: Dictionary) -> BossAttackPattern:
	var p := BossAttackPattern.new()
	p.id = String(d.get("id", ""))
	p.category = String(d.get("category", "NORMAL"))
	p.telegraph_game_seconds = float(d.get("telegraph_game_seconds", 0.4))
	p.active_game_seconds = float(d.get("active_game_seconds", 0.1))
	p.recovery_game_seconds = float(d.get("recovery_game_seconds", 0.3))
	p.focus_real_seconds = float(d.get("focus_real_seconds", 0.1))
	p.decision_real_seconds = float(d.get("decision_real_seconds", 0.2))
	p.time_scale = float(d.get("time_scale", 0.18))
	p.zoom_size = float(d.get("zoom_size", 9.5))
	p.allowed_actions = PackedStringArray(d.get("allowed_actions", []))
	p.parryable = bool(d.get("parryable", false))
	p.screen_safe_directions = PackedStringArray(d.get("screen_safe_directions", []))
	p.reaction_step_meters = float(d.get("reaction_step_meters", 1.8))
	p.post_success_boss_recovery_game_seconds = float(d.get("post_success_boss_recovery_game_seconds", 0.7))
	p.lethal_on_hit = bool(d.get("lethal_on_hit", true))
	p.visual_cue = String(d.get("visual_cue", ""))
	p.requires_clear_destination = bool(d.get("requires_clear_destination", false))
	p.resource_name = p.id
	return p


func summary() -> String:
	var s := "%s [%s] tele %.2fs" % [id, "FATAL" if is_fatal() else "NORMAL", telegraph_game_seconds]
	if is_fatal():
		s += "  allow %s  parry %s" % [", ".join(allowed_actions), parryable]
	else:
		s += "  active %.2fs  rec %.2fs" % [active_game_seconds, recovery_game_seconds]
	return s
