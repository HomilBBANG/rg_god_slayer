## 인벤토리 + 장비 + 퀵슬롯 상태. UI 와 플레이어가 공유한다.
class_name Inventory
extends Node

signal changed

## id → 개수 (장비는 1)
var items: Dictionary = {"sword": 1, "pistol": 1, "rifle": 1, "dagger": 10, "bomb": 5}
## 퀵슬롯 1~5 → 아이템 id ("" = 비어 있음)
var quick: Array[String] = ["sword", "pistol", "rifle", "dagger", "bomb"]
## 장비 슬롯
var equipped: Dictionary = {"melee": "sword", "ranged": "pistol"}
## 현재 손에 든 무기 종류: "melee" / "ranged"
var active: String = "melee"
## 원거리 무기별 남은 탄 (id → 탄 수)
var ammo: Dictionary = {}


func _ready() -> void:
	for id in items:
		var d := Items.get_item(id)
		if d.get("kind") == Items.Kind.RANGED:
			ammo[id] = d["magazine"]


func count(id: String) -> int:
	return int(items.get(id, 0))


func has(id: String) -> bool:
	return count(id) > 0


func consume(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	items[id] = count(id) - n
	if items[id] <= 0:
		items.erase(id)
		for i in quick.size():
			if quick[i] == id:
				quick[i] = ""
	changed.emit()
	return true


func set_quick(slot: int, id: String) -> void:
	if slot < 0 or slot >= quick.size():
		return
	# 같은 아이템이 다른 슬롯에 있으면 비운다
	for i in quick.size():
		if quick[i] == id:
			quick[i] = ""
	quick[slot] = id
	changed.emit()


func equip(id: String) -> bool:
	var d := Items.get_item(id)
	if d.is_empty() or not has(id):
		return false
	match d["kind"]:
		Items.Kind.MELEE:
			equipped["melee"] = id
			active = "melee"
		Items.Kind.RANGED:
			equipped["ranged"] = id
			active = "ranged"
		_:
			return false
	changed.emit()
	return true


func active_weapon() -> String:
	return String(equipped.get(active, ""))


func weapons_of(kind: int) -> Array[String]:
	var out: Array[String] = []
	for id in items:
		if Items.get_item(id).get("kind") == kind:
			out.append(id)
	out.sort()
	return out
