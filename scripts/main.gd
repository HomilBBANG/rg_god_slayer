## Main 씬 루트: 라이트 프리셋 전환(F2, A/B 비교 캡처용), 뷰포트 캡처(F12), 지붕 가림 처리.
extends Node3D

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var player: PlayerController = $Player

@onready var camera_rig: CameraFollow = $CameraRig

## F2로 순환하는 태양 프리셋: [고도각(도), 화면 기준 방위각(도, 0=화면 오른쪽, 90=화면 위), 에너지].
## 쿼터뷰에서 카메라에 보이는 면은 +X/+Z 면이므로, 태양을 화면 '오른쪽(약간 위)'에 두면
## 인물·벽의 오른쪽 면이 밝고 왼쪽 면이 어두우며 그림자는 화면 왼쪽으로 떨어진다 (레퍼런스와 같은 읽힘).
var light_presets: Array = [
	[48.0, 10.0, 1.0],    # 기본: 화면 오른쪽 상단 햇빛
	[48.0, 190.0, 1.0],   # A/B: 정반대(왼쪽)에서
	[26.0, 10.0, 0.75],   # 낮은 해, 약한 에너지
]
var _light_index: int = 0
var _capture_index: int = 0


func _ready() -> void:
	_apply_light_preset(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_light_cycle"):
		_apply_light_preset((_light_index + 1) % light_presets.size())
	elif event.is_action_pressed("debug_screenshot"):
		capture_screenshot()


func _apply_light_preset(i: int) -> void:
	_light_index = i
	var preset: Array = light_presets[i]
	var el: float = deg_to_rad(preset[0])
	var az: float = deg_to_rad(preset[1])
	# 화면 축을 월드 XZ로 투영한 벡터로 '태양이 있는 방향'을 만든 뒤, 빛은 그 반대로 쏜다.
	var sun_from := (camera_rig.screen_right() * cos(az) + camera_rig.screen_up() * sin(az)) * cos(el) + Vector3.UP * sin(el)
	sun.global_transform.basis = Basis.looking_at(-sun_from.normalized(), Vector3.UP)
	sun.light_energy = preset[2]
	print("[RED] light preset %d: elev=%.0f° screen_az=%.0f° energy=%.2f  dir=%s" % [i, preset[0], preset[1], preset[2], -sun.global_transform.basis.z])


func set_light_preset(i: int) -> void:
	_apply_light_preset(i % light_presets.size())


## 뷰포트(1920×1080 고정)를 user://captures/ 에 PNG로 저장. 창 크기와 무관하게 1080p로 찍힌다.
func capture_screenshot(file_name: String = "") -> String:
	var img := get_viewport().get_texture().get_image()
	var dir := "user://captures"
	DirAccess.make_dir_recursive_absolute(dir)
	if file_name == "":
		file_name = "capture_%02d.png" % _capture_index
		_capture_index += 1
	var path := dir.path_join(file_name)
	var err := img.save_png(path)
	print("[RED] screenshot %s -> %s (%s)" % [img.get_size(), ProjectSettings.globalize_path(path), error_string(err)])
	return path
