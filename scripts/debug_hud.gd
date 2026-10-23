## 최소 HUD (GDD §9): 좌상단 체력 바, 좌하단 조작 안내(10초 후 숨김), F1 디버그 정보.
extends CanvasLayer

@export var player_path: NodePath
@export var camera_rig_path: NodePath
@export var sun_path: NodePath
@export var hint_visible_seconds: float = 10.0
@export var dummy_hp: int = 5

@onready var _health_bar: ProgressBar = $Root/HealthBar
@onready var _hint: Label = $Root/Hint
@onready var _debug: Label = $Root/Debug

var _player: PlayerController
var _rig: CameraFollow
var _sun: DirectionalLight3D
var _elapsed: float = 0.0
var debug_visible: bool = false


func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerController
	_rig = get_node_or_null(camera_rig_path) as CameraFollow
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_health_bar.max_value = dummy_hp
	_health_bar.value = dummy_hp
	_debug.visible = debug_visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		set_debug_visible(not debug_visible)


func set_debug_visible(v: bool) -> void:
	debug_visible = v
	_debug.visible = v


func _process(delta: float) -> void:
	_elapsed += delta
	# 디버그 켜져 있으면 안내도 계속 보여 준다
	_hint.visible = debug_visible or _elapsed < hint_visible_seconds
	if debug_visible:
		_debug.text = _build_debug_text()


func _build_debug_text() -> String:
	var lines: PackedStringArray = []
	lines.append("FPS %d" % Engine.get_frames_per_second())
	lines.append("viewport %s  window %s" % [get_viewport().get_visible_rect().size, DisplayServer.window_get_size()])
	if _player:
		var p := _player.global_position
		lines.append("player (%.2f, %.2f, %.2f)  state %s" % [p.x, p.y, p.z, _player.state_name()])
		lines.append("facing (%.2f, %.2f)  input %s  floor %s" % [_player.facing.x, _player.facing.z, _player.move_input, _player.is_on_floor()])
		lines.append("char px @1080p ≈ %.0f" % _character_pixel_height())
	if _rig:
		lines.append("camera ortho size %.1f  elev %.0f°  az %.0f°  dist %.0fm" % [_rig.ortho_size, _rig.elevation_deg, _rig.azimuth_deg, _rig.distance])
	if _sun:
		var e := _sun.rotation_degrees
		lines.append("sun rot (%.0f, %.0f, %.0f)  energy %.2f  [F2 cycle]" % [e.x, e.y, e.z, _sun.light_energy])
	lines.append("F1 debug  F2 light preset  F12 screenshot (user://captures)")
	return "\n".join(lines)


## 1.70m 인물이 1080p에서 차지하는 픽셀 높이 — 발과 정수리를 실제로 투영해 측정
func _character_pixel_height() -> float:
	if _player == null or _rig == null:
		return 0.0
	var cam := _rig.camera
	var foot := cam.unproject_position(_player.global_position)
	var head := cam.unproject_position(_player.global_position + Vector3(0, 1.70, 0))
	var vp_h := get_viewport().get_visible_rect().size.y
	return absf(foot.y - head.y) * (1080.0 / maxf(vp_h, 1.0))
