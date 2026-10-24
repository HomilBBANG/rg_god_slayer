## 치명적 패턴 카메라 연출 (GDD §10). 기존 CameraFollow 리그 위에서 동작하며
## 회전은 절대 바꾸지 않고 직교 Size 와 주시점만 현실 시간으로 보간한다.
## 주시점 = 보스 65 % + 주인공 35 %, 단 주인공이 화면 10~90 % 영역 안에 남도록 보정.
class_name CombatCameraDirector
extends Node

@export var base_size: float = 15.0
@export var player_margin: float = 0.10

var rig: CameraFollow
var boss: Node3D
var player: Node3D

var _from_size: float = 15.0
var _to_size: float = 15.0
var _start_us: int = 0
var _dur_us: int = 1
var _last_us: int = 0
var _focusing: bool = false
var _releasing: bool = false
var _size_now: float = 15.0


func setup(r: CameraFollow, b: Node3D, p: Node3D) -> void:
	rig = r
	boss = b
	player = p
	base_size = r.ortho_size
	_size_now = base_size
	process_mode = Node.PROCESS_MODE_ALWAYS


## 보스 중심으로 확대 (현실 시간 real_seconds)
func focus(zoom_size: float, real_seconds: float) -> void:
	_from_size = _size_now
	_to_size = zoom_size
	_start_us = CombatClock.now_us()
	_dur_us = maxi(1, int(real_seconds * 1_000_000.0))
	_focusing = true
	_releasing = false
	rig.focus_override = true
	rig.focus_point = _focus_point()


## 기본 시점/크기로 복귀 (현실 시간)
func release(real_seconds: float) -> void:
	_from_size = _size_now
	_to_size = base_size
	_start_us = CombatClock.now_us()
	_dur_us = maxi(1, int(real_seconds * 1_000_000.0))
	_focusing = false
	_releasing = true


## 즉시 기본값 (사망/재시작/승리)
func reset_immediate() -> void:
	_focusing = false
	_releasing = false
	_size_now = base_size
	rig.focus_override = false
	rig.set_ortho_size(base_size)


func is_default() -> bool:
	return not _focusing and not _releasing and absf(_size_now - base_size) < 0.001 and not rig.focus_override


func _process(_delta: float) -> void:
	if rig == null:
		return
	var now := CombatClock.now_us()
	if _focusing or _releasing:
		var k := clampf(float(now - _start_us) / float(_dur_us), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)   # smoothstep
		_size_now = lerpf(_from_size, _to_size, k)
		rig.set_ortho_size(_size_now)
		if _releasing and k >= 1.0:
			_releasing = false
			rig.focus_override = false
		elif _focusing and k >= 1.0:
			_focusing = false
	if rig.focus_override:
		rig.focus_point = _focus_point()


## 보스 65 / 주인공 35 가중 중간점. 주인공이 화면 margin 안쪽에 남도록 카메라 right/up 축으로 보정.
func _focus_point() -> Vector3:
	if boss == null or player == null:
		return rig.global_position
	var b := boss.global_position + Vector3(0, 1.2, 0)
	var p := player.global_position + Vector3(0, 0.8, 0)
	var f := b * 0.65 + p * 0.35
	var cam := rig.camera
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var size := _size_now if (_focusing or _releasing) else rig.ortho_size
	var half_h := size * 0.5
	var half_w := half_h * 16.0 / 9.0
	var lim_x := half_w * (1.0 - 2.0 * player_margin)
	var lim_y := half_h * (1.0 - 2.0 * player_margin)
	var d := p - f
	var dx := d.dot(right)
	var dy := d.dot(up)
	if absf(dx) > lim_x:
		f += right * (dx - signf(dx) * lim_x)
	if absf(dy) > lim_y:
		f += up * (dy - signf(dy) * lim_y)
	return f
