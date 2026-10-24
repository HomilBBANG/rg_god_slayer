## 아이템 정의 (데이터). 숫자는 테스트 초기값 — 스피디한 전투 기준.
class_name Items
extends RefCounted

enum Kind { MELEE, RANGED, CONSUMABLE }

const DB := {
	"sword": {
		"name": "검", "kind": Kind.MELEE,
		"damage": 1, "range": 1.45, "cone_deg": 100.0,
		"duration": 0.30, "windup": 0.07, "active_end": 0.16, "move_factor": 0.6,
	},
	"pistol": {
		"name": "권총", "kind": Kind.RANGED,
		"damage": 1, "interval": 0.16, "auto": false, "speed": 32.0, "range": 11.0, "spread_deg": 1.5,
		"magazine": 8, "reload": 0.7, "move_factor": 0.85, "recoil": 0.05,
	},
	"rifle": {
		"name": "라이플", "kind": Kind.RANGED,
		"damage": 2, "interval": 0.09, "auto": true, "speed": 48.0, "range": 18.0, "spread_deg": 3.5,
		"magazine": 30, "reload": 1.3, "move_factor": 0.7, "recoil": 0.03,
	},
	"dagger": {
		"name": "단검", "kind": Kind.CONSUMABLE, "use": "throw",
		"damage": 2, "speed": 22.0, "range": 10.0, "cooldown": 0.22, "stack": 10,
	},
	"bomb": {
		"name": "폭탄", "kind": Kind.CONSUMABLE, "use": "lob",
		"damage": 3, "speed": 7.5, "fuse": 1.2, "radius": 2.6, "cooldown": 0.5, "stack": 5,
	},
}


static func get_item(id: String) -> Dictionary:
	return DB.get(id, {})


static func kind_name(k: int) -> String:
	match k:
		Kind.MELEE:
			return "근접"
		Kind.RANGED:
			return "원거리"
		Kind.CONSUMABLE:
			return "소모품"
	return "?"
