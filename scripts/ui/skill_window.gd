## K — 스킬 창. 순발력/판단력을 +/- 로 배운다 (프로토타입: 포인트 제한 없음). 열려 있는 동안 일시정지.
class_name SkillWindow
extends CanvasLayer

var skills: PlayerSkills
var _panel: PanelContainer
var _rows: Dictionary = {}


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -330
	_panel.offset_right = 330
	_panel.offset_top = -150
	_panel.offset_bottom = 150
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.09, 0.94)
	sb.border_color = Color(0.55, 0.5, 0.42, 1.0)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_panel.add_child(vb)
	var title := Label.new()
	title.text = "스킬   (K 닫기)   +/- 로 배우기"
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)
	for key in ["reflex", "judgement"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vb.add_child(row)
		var l := Label.new()
		l.custom_minimum_size = Vector2(420, 36)
		l.add_theme_font_size_override("font_size", 17)
		row.add_child(l)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(44, 36)
		minus.pressed.connect(_bump.bind(key, -1))
		row.add_child(minus)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(44, 36)
		plus.pressed.connect(_bump.bind(key, 1))
		row.add_child(plus)
		_rows[key] = l


func _bump(key: String, d: int) -> void:
	if skills == null:
		return
	if key == "reflex":
		skills.set_reflex(skills.reflex + d)
	else:
		skills.set_judgement(skills.judgement + d)


func open(s: PlayerSkills) -> void:
	skills = s
	if not s.changed.is_connected(refresh):
		s.changed.connect(refresh)
	refresh()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func refresh() -> void:
	if skills == null:
		return
	_rows["reflex"].text = "순발력  %d / %d   판단 창 %.2f s (기본 0.20, 최대 0.50)" % [skills.reflex, PlayerSkills.REFLEX_MAX, skills.decision_seconds()]
	_rows["judgement"].text = "판단력  %d / %d   슬로모션 %.1f s (기본 1.0, 최대 4.0)" % [skills.judgement, PlayerSkills.JUDGEMENT_MAX, skills.slow_seconds()]
