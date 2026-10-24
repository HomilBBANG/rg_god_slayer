## W — 장비 창. 근접/원거리 슬롯에 인벤토리의 무기를 장비한다. 열려 있는 동안 일시정지.
class_name EquipmentWindow
extends CanvasLayer

var inventory: Inventory
var _panel: PanelContainer
var _rows: Dictionary = {}   # "melee"/"ranged" → HBoxContainer


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
	_panel.offset_left = -280
	_panel.offset_right = 280
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
	title.text = "장비   (W 닫기)   버튼을 눌러 장비"
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)
	for key in ["melee", "ranged"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vb.add_child(row)
		var l := Label.new()
		l.custom_minimum_size = Vector2(140, 36)
		l.add_theme_font_size_override("font_size", 18)
		row.add_child(l)
		_rows[key] = row


func open(inv: Inventory) -> void:
	inventory = inv
	if not inv.changed.is_connected(refresh):
		inv.changed.connect(refresh)
	refresh()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func refresh() -> void:
	if inventory == null:
		return
	for key in _rows:
		var row: HBoxContainer = _rows[key]
		# 첫 라벨만 남기고 버튼 재생성
		for c in row.get_children().slice(1):
			c.queue_free()
		var label: Label = row.get_child(0)
		var cur: String = inventory.equipped.get(key, "")
		label.text = "%s 슬롯:  %s" % ["근접" if key == "melee" else "원거리", Items.get_item(cur).get("name", "-")]
		var kind := Items.Kind.MELEE if key == "melee" else Items.Kind.RANGED
		for id in inventory.weapons_of(kind):
			var b := Button.new()
			b.text = Items.get_item(id)["name"] + ("  ✓" if id == cur else "")
			b.custom_minimum_size = Vector2(110, 36)
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(func(): inventory.equip(id))
			row.add_child(b)
