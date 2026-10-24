## 사망/승리 UI (GDD §9). 실패 피드백은 즉시(0.35 s 이내) 표시, R 로 재도전.
class_name BattleResultController
extends CanvasLayer

var _death: PanelContainer
var _death_label: Label
var _victory: PanelContainer
var _victory_label: Label


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_death = _panel(Color(0.30, 0.10, 0.10, 0.92))
	_death_label = _death.get_child(0)
	_victory = _panel(Color(0.12, 0.18, 0.16, 0.92))
	_victory_label = _victory.get_child(0)
	hide_all()


func _panel(bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -360
	p.offset_right = 360
	p.offset_top = -90
	p.offset_bottom = 90
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.55, 0.5, 0.42, 1.0)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(22)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	p.add_child(l)
	add_child(p)
	return p


func show_death(reason: String, reaction_ms: float, action: StringName) -> void:
	var detail := reason
	if reaction_ms >= 0.0 and action != &"":
		detail += "   (%s @ %.0f ms)" % [action, reaction_ms]
	elif reaction_ms >= 0.0:
		detail += "   (입력 없음, %.0f ms)" % reaction_ms
	_death_label.text = "사망\n%s\n\nR — 즉시 재도전" % detail
	_death.visible = true
	_victory.visible = false


func show_victory() -> void:
	_victory_label.text = "보스 격파\n\nR — 다시 싸우기"
	_victory.visible = true
	_death.visible = false


func hide_all() -> void:
	if _death == null:
		return   # 아직 _ready 전 (디렉터의 첫 reset)
	_death.visible = false
	_victory.visible = false
