## 개발자 오버레이 (GDD §13): 전투/보스 상태, 패턴 ID, 허용 행동, 판단 단계와 남은 ms, 입력/결과, 보스 HP, 로그.
## 판단 창 동안 화면 가장자리에 얇은 방향 힌트(허용 방향만) — 오버레이가 켜져 있을 때만 (F1).
class_name AttackDebugOverlay
extends CanvasLayer

@export var director_path: NodePath
@export var visible_on_start: bool = true

var director: CombatDirector
var _label: Label
var _log: Label
var _edges: Dictionary = {}
var _parry_hint: Label
var _flash: ColorRect
var _flash_until_us: int = 0


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	director = get_node(director_path)
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_right = 1.0
	_label.offset_left = -560
	_label.offset_right = -24
	_label.offset_top = 24
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	add_child(_label)
	_log = Label.new()
	_log.anchor_left = 1.0
	_log.anchor_right = 1.0
	_log.anchor_top = 1.0
	_log.anchor_bottom = 1.0
	_log.offset_left = -560
	_log.offset_right = -24
	_log.offset_top = -260
	_log.offset_bottom = -24
	_log.add_theme_font_size_override("font_size", 15)
	_log.add_theme_color_override("font_color", Color(0.8, 0.8, 0.76))
	add_child(_log)
	var edge_color := Color(0.85, 0.78, 0.55, 0.85)
	_edges["UP"] = _bar(Rect2(0, 0, 1920, 8), edge_color)
	_edges["DOWN"] = _bar(Rect2(0, 1072, 1920, 8), edge_color)
	_edges["LEFT"] = _bar(Rect2(0, 0, 8, 1080), edge_color)
	_edges["RIGHT"] = _bar(Rect2(1912, 0, 8, 1080), edge_color)
	_parry_hint = Label.new()
	_parry_hint.text = "X"
	_parry_hint.add_theme_font_size_override("font_size", 42)
	_parry_hint.add_theme_color_override("font_color", edge_color)
	_parry_hint.position = Vector2(940, 20)
	_parry_hint.visible = false
	add_child(_parry_hint)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.size = Vector2(1920, 1080)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	director.fatal.decision_opened.connect(_on_decision_opened)
	director.event_logged.connect(func(_l): _log.text = "\n".join(director.log_lines))
	visible = visible_on_start


func _bar(r: Rect2, c: Color) -> ColorRect:
	var b := ColorRect.new()
	b.position = r.position
	b.size = r.size
	b.color = c
	b.visible = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		visible = not visible


func _on_decision_opened(_p: BossAttackPattern) -> void:
	# 선택 창이 열리는 순간의 짧은 시각 신호 (화면 가림 없음: 아주 옅은 한 프레임급 플래시)
	_flash_until_us = CombatClock.now_us() + 60_000


func _process(_delta: float) -> void:
	var now := CombatClock.now_us()
	_flash.color.a = 0.10 if now < _flash_until_us else 0.0
	var f := director.fatal
	var b := director.boss
	var in_decision := f.phase == FatalReactionController.Phase.DECISION
	for d in _edges:
		_edges[d].visible = visible and in_decision and f.pattern and f.pattern.screen_safe_directions.has(d)
	_parry_hint.visible = visible and in_decision and f.pattern and f.pattern.parryable
	if not visible:
		return
	var lines: PackedStringArray = []
	lines.append("FPS %d   time_scale %.2f   battle %s" % [Engine.get_frames_per_second(), Engine.time_scale, director.state_name()])
	lines.append("boss %s  HP %d/%d  parry %d   player %s%s" % [b.state_name(), b.hp, b.max_hp, b.parry_count, director.player.state_name(), "  [INVULN]" if director.player.invulnerable else ""])
	var p := b.pattern if b.pattern else f.pattern
	if p:
		lines.append("pattern %s" % p.summary())
		if p.is_fatal():
			lines.append("allowed %s   safe %s   parry %s" % [", ".join(p.allowed_actions), ", ".join(p.screen_safe_directions), p.parryable])
	else:
		lines.append("pattern -")
	var rem := f.remaining_ms()
	lines.append("fatal %s   remaining %s" % [f.phase_name(), ("%.0f ms" % rem) if rem >= 0.0 else "-"])
	lines.append("last input %s   %s   %s" % [f.last_action if f.last_action != &"" else "-", ("%.1f ms" % f.last_reaction_ms) if f.last_reaction_ms >= 0.0 else "-", f.last_result if f.last_result != "" else "-"])
	var sel := director.selected_pattern()
	lines.append("[F3] %s   [F4/F6] select: %s   [F5] fire   [R] retry   seq %d/%d" % ["AUTO" if director.auto_sequence else "MANUAL", sel.id if sel else "-", director.seq_index, director.sequence.size()])
	_label.text = "\n".join(lines)
