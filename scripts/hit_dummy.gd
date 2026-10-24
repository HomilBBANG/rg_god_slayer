## 타격 더미 (GDD §5). AI 없음. 그룹 attack_targets 에 속하며 receive_hit() 로 반응한다.
class_name HitDummy
extends StaticBody3D

## 공격 판정 시 더미 중심까지의 거리에 더해 주는 반경 (몸통 두께)
@export var hit_radius: float = 0.35
@export var max_hp: int = 5

var hp: int
var hit_count: int = 0

@onready var _visual: Node3D = $Visual
@onready var _label: Label3D = $HitLabel

var _tween: Tween


func _ready() -> void:
	hp = max_hp
	add_to_group("attack_targets")
	_refresh_label()


## 플레이어 공격이 닿았을 때 호출. from_dir = 공격자 → 더미 방향(수평).
func receive_hit(from_dir: Vector3, damage: int = 1) -> void:
	hit_count += 1
	hp -= damage
	if hp <= 0:
		hp = max_hp
	_refresh_label()
	_play_hit_reaction(from_dir)


func _refresh_label() -> void:
	_label.text = "HIT %d\nHP %d/%d" % [hit_count, hp, max_hp]


## 0.1초 짧은 기울임 후 복귀 — 외곽선/번쩍임 대신 자세 변화로 피격을 읽게 한다.
func _play_hit_reaction(from_dir: Vector3) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	var axis := Vector3.UP.cross(from_dir).normalized()
	if axis.length_squared() < 0.001:
		axis = Vector3.RIGHT
	_visual.rotation = Vector3.ZERO
	var tilted := Basis(axis, deg_to_rad(-14.0)).get_euler()
	_tween = create_tween()
	_tween.tween_property(_visual, "rotation", tilted, 0.05)
	_tween.tween_property(_visual, "rotation", Vector3.ZERO, 0.12).set_ease(Tween.EASE_OUT)
