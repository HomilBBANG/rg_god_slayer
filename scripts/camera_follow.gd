## 직교 고정각 추적 카메라 + 픽셀아트용 텍셀 스냅 (GDD §6, 3D pixel art 기법)
## CameraRig(Node3D) 에 부착. 자식 Camera3D를 elevation/azimuth/distance 로 배치하고
## 리그만 플레이어를 부드럽게 따라간다. 회전·줌은 런타임에 절대 바뀌지 않는다.
##
## 픽셀 스냅: 저해상도 SubViewport 에서 카메라가 텍셀 단위로만 움직이게 카메라 위치를
## 화면 right/up 축으로 양자화하고, 남은 서브텍셀 잔량은 `subpixel_offset` 으로 내보내
## 메인 씬이 화면 TextureRect 를 그만큼 반대로 밀어 부드러운 스크롤을 만든다 (pixel-aligned panning).
class_name CameraFollow
extends Node3D

@export var target_path: NodePath
## 수평면 기준 고도각 (도)
@export var elevation_deg: float = 52.0
## Y축 회전 (도)
@export var azimuth_deg: float = 45.0
## 목표점까지 거리 (m). 직교 투영이라 화면 배율엔 영향 없음, 클리핑 여유용.
@export var distance: float = 25.0
## 직교 투영 세로 크기 (m) — 1080p 기준 화면 세로. 70~90px 캐릭터 검증 시 13.5~17.0 사이에서 조절.
@export var ortho_size: float = 15.0
## 주시점 오프셋 — 발보다 상체 쪽
@export var look_offset: Vector3 = Vector3(0.0, 0.8, 0.0)
## 지수 보간 시간 상수 (초)
@export var smoothing_time: float = 0.12
## 리그 목표 위치를 제한하는 XZ 범위 (맵 밖 빈 공간 노출 방지)
@export var bounds_min: Vector2 = Vector2(-13.0, -9.0)
@export var bounds_max: Vector2 = Vector2(13.0, 9.0)

@export_group("Pixel")
## 1080p 기준 렌더 텍셀 크기 (3 → 640×360 렌더). 메인 씬이 이 값으로 SubViewport 크기를 정한다.
@export var pixel_scale: int = 1
## 서브텍셀 스크롤용 여유 텍셀 (각 변)
@export var margin_texels: int = 2
## 텍셀 스냅 사용 (끄면 일반 부드러운 카메라)
@export var snap_enabled: bool = true

@onready var camera: Camera3D = $Camera3D

## 메인 씬이 읽는 화면 픽셀 단위 보정값
var subpixel_offset: Vector2 = Vector2.ZERO
## 텍셀 한 칸의 월드 크기 (m)
var texel_size: float = 0.0

var _target: Node3D
var _camera_local_offset: Vector3


func _ready() -> void:
	if target_path != NodePath():
		_target = get_node_or_null(target_path)
	_apply_camera_transform()
	if _target:
		global_position = _clamped_target()
		_snap_camera()


## 카메라를 리그 원점 기준 (h·sin az, v, h·cos az) 에 두고 원점을 바라보게 한다.
func _apply_camera_transform() -> void:
	var el := deg_to_rad(elevation_deg)
	var az := deg_to_rad(azimuth_deg)
	var horizontal := distance * cos(el)
	var vertical := distance * sin(el)
	_camera_local_offset = Vector3(horizontal * sin(az), vertical, horizontal * cos(az))
	camera.position = _camera_local_offset
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.far = 100.0
	# 렌더 텍셀 수(세로) = 1080/scale + 여유. 여유만큼 투영 크기를 늘려 텍셀 크기를 유지한다.
	var h_texels := int(1080.0 / float(pixel_scale))
	texel_size = ortho_size / float(h_texels)
	camera.size = texel_size * float(h_texels + margin_texels * 2)


## SubViewport 가 가져야 하는 렌더 크기
func render_size() -> Vector2i:
	return Vector2i(int(1920.0 / float(pixel_scale)) + margin_texels * 2, int(1080.0 / float(pixel_scale)) + margin_texels * 2)


func _clamped_target() -> Vector3:
	var p := _target.global_position + look_offset
	p.x = clampf(p.x, bounds_min.x, bounds_max.x)
	p.z = clampf(p.z, bounds_min.y, bounds_max.y)
	return p


func _process(delta: float) -> void:
	if _target == null:
		return
	var goal := _clamped_target()
	# 지수 보간: 프레임레이트와 무관하게 smoothing_time 안에 약 63% 도달
	var w := 1.0 - exp(-delta / maxf(smoothing_time, 0.0001))
	global_position = global_position.lerp(goal, w)
	_snap_camera()


## 카메라의 '진짜' 위치를 화면 right/up 축에서 텍셀 단위로 내림하고 잔량을 보정값으로 내보낸다.
func _snap_camera() -> void:
	var true_pos := global_position + _camera_local_offset
	if not snap_enabled or texel_size <= 0.0:
		camera.global_position = true_pos
		subpixel_offset = Vector2.ZERO
		return
	var right := camera.global_transform.basis.x
	var up := camera.global_transform.basis.y
	var px := true_pos.dot(right)
	var py := true_pos.dot(up)
	var rx := px - floorf(px / texel_size) * texel_size
	var ry := py - floorf(py / texel_size) * texel_size
	camera.global_position = true_pos - right * rx - up * ry
	# 카메라가 왼쪽/아래로 rx, ry 만큼 당겨졌으므로 화면은 반대로 밀어 준다 (화면 y 는 아래가 +)
	subpixel_offset = Vector2(-rx / texel_size, ry / texel_size) * float(pixel_scale)


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
