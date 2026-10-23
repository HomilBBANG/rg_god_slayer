## 직교 고정각 추적 카메라 (GDD §6)
## CameraRig(Node3D) 에 부착. 자식 Camera3D를 elevation/azimuth/distance 로 배치하고
## 리그 자체만 플레이어를 부드럽게 따라간다. 회전·줌은 런타임에 절대 바뀌지 않는다.
class_name CameraFollow
extends Node3D

@export var target_path: NodePath
## 수평면 기준 고도각 (도)
@export var elevation_deg: float = 52.0
## Y축 회전 (도)
@export var azimuth_deg: float = 45.0
## 목표점까지 거리 (m). 직교 투영이라 화면 배율엔 영향 없음, 클리핑 여유용.
@export var distance: float = 25.0
## 직교 투영 세로 크기 (m). 70~90px 캐릭터 검증 시 13.5~17.0 사이에서 조절.
@export var ortho_size: float = 15.0
## 주시점 오프셋 — 발보다 상체 쪽
@export var look_offset: Vector3 = Vector3(0.0, 0.8, 0.0)
## 지수 보간 시간 상수 (초)
@export var smoothing_time: float = 0.18
## 리그 목표 위치를 제한하는 XZ 범위 (맵 밖 빈 공간 노출 방지)
@export var bounds_min: Vector2 = Vector2(-13.0, -9.0)
@export var bounds_max: Vector2 = Vector2(13.0, 9.0)

@onready var camera: Camera3D = $Camera3D

var _target: Node3D


func _ready() -> void:
	if target_path != NodePath():
		_target = get_node_or_null(target_path)
	_apply_camera_transform()
	if _target:
		global_position = _clamped_target()


## 카메라를 리그 원점 기준 (h·sin az, v, h·cos az) 에 두고 원점을 바라보게 한다.
func _apply_camera_transform() -> void:
	var el := deg_to_rad(elevation_deg)
	var az := deg_to_rad(azimuth_deg)
	var horizontal := distance * cos(el)
	var vertical := distance * sin(el)
	camera.position = Vector3(horizontal * sin(az), vertical, horizontal * cos(az))
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = ortho_size
	camera.near = 0.1
	camera.far = 100.0


func _clamped_target() -> Vector3:
	var p := _target.global_position + look_offset
	p.x = clampf(p.x, bounds_min.x, bounds_max.x)
	p.z = clampf(p.z, bounds_min.y, bounds_max.y)
	return p


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var goal := _clamped_target()
	# 지수 보간: 프레임레이트와 무관하게 smoothing_time 안에 약 63% 도달
	var w := 1.0 - exp(-delta / maxf(smoothing_time, 0.0001))
	global_position = global_position.lerp(goal, w)


## 화면 '오른쪽' 방향을 월드 XZ 평면에 투영한 단위 벡터
func screen_right() -> Vector3:
	var r := camera.global_transform.basis.x
	r.y = 0.0
	return r.normalized()


## 화면 '위쪽' 방향(카메라 전방)을 월드 XZ 평면에 투영한 단위 벡터
func screen_up() -> Vector3:
	var f := -camera.global_transform.basis.z
	f.y = 0.0
	return f.normalized()
