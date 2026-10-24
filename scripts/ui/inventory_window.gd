## I — 인벤토리 창. 아이템을 고르고 1~5 를 누르거나 슬롯 버튼을 눌러 퀵슬롯에 등록한다.
## 열려 있는 동안 게임은 일시정지. 코드로 UI 를 만든다 (씬 파일 없음).
class_name InventoryWindow
extends CanvasLayer

var inventory: Inventory
var _panel: PanelContainer
var _list: ItemList
var _slot_buttons: Array[Button] = []
var _ids: Array[String] = []
var _info: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchors_preset = Control.PRESET_CENTER
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -300
	_panel.offset_right = 300
	_panel.offset_top = -220
	_panel.offset_bottom = 220
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.09, 0.94)
	sb.border_color = Color(0.55, 0.5, 0.42, 1.0)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add_child(vb)
	var title := Label.new()
	title.text = "인벤토리   (I 닫기)   아이템 선택 후 1~5 키 = 퀵슬롯 등록"
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(hb)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(300, 320)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", 18)
	_list.item_selected.connect(func(_i): _refresh_info())
	hb.add_child(_list)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	hb.add_child(side)
	var l := Label.new()
	l.text = "퀵슬롯"
	l.add_theme_font_size_override("font_size", 18)
	side.add_child(l)
	for i in 5:
		var b := Button.new()
		b.custom_minimum_size = Vector2(220, 36)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_assign_selected.bind(i))
		side.add_child(b)
		_slot_buttons.append(b)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(220, 60)
	_info.add_theme_font_size_override("font_size", 14)
	side.add_child(_info)


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
	var selected := _selected_id()
	_list.clear()
	_ids.clear()
	var ids: Array = inventory.items.keys()
	ids.sort()
	for id in ids:
		var d := Items.get_item(id)
		var line: String = "%s  ×%d   [%s]" % [d.get("name", id), inventory.count(id), Items.kind_name(d.get("kind", 0))]
		var q := inventory.quick.find(id)
		if q >= 0:
			line += "  → 슬롯 %d" % (q + 1)
		if inventory.equipped.values().has(id):
			line += "  (장비 중)"
		_list.add_item(line)
		_ids.append(id)
	if selected != "":
		var k := _ids.find(selected)
		if k >= 0:
			_list.select(k)
	for i in 5:
		var id: String = inventory.quick[i]
		_slot_buttons[i].text = "%d : %s" % [i + 1, Items.get_item(id).get("name", "-") if id != "" else "-"]
	_refresh_info()


func _selected_id() -> String:
	var sel := _list.get_selected_items()
	if sel.is_empty() or sel[0] >= _ids.size():
		return ""
	return _ids[sel[0]]


func _refresh_info() -> void:
	var id := _selected_id()
	if id == "":
		_info.text = "아이템을 선택하세요."
		return
	var d := Items.get_item(id)
	var s := "%s — %s" % [d.get("name", id), Items.kind_name(d.get("kind", 0))]
	if d.has("damage"):
		s += "\n피해 %d" % d["damage"]
	if d.has("magazine"):
		s += ", 탄창 %d" % d["magazine"]
	if d.has("range"):
		s += ", 사거리 %.1f m" % d["range"]
	_info.text = s


func _assign_selected(slot: int) -> void:
	var id := _selected_id()
	if id == "" or inventory == null:
		return
	inventory.set_quick(slot, id)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	for i in 5:
		if event.is_action_pressed("quick_%d" % (i + 1)):
			_assign_selected(i)
			get_viewport().set_input_as_handled()
			return
