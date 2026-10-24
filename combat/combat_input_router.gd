## 전투 입력 라우터 (GDD §13). _input 에서 **새 키다운(에코 아님)** 만 골라 행동 이름과
## 현실 시각(usec) 을 신호로 내보낸다. 눌린 채 유지되는 키는 다시 보고하지 않는다.
## Z 는 치명적 판단 창에서 무시해야 하므로 여기서 내보내지 않는다 (공격 입력은 플레이어가 Input 으로 처리).
class_name CombatInputRouter
extends Node

signal new_action(action: StringName, usec: int)
## 전투 명령 키 (R 재도전, F3~F6 패턴 테스트 메뉴). SubViewport 안의 노드는 _input 을 받지 못하므로
## 이 라우터는 루트 뷰포트(씬 루트) 에 붙고, 디렉터는 이 신호로 명령을 받는다.
signal command(cmd: StringName)

const COMMANDS := ["retry", "debug_pattern_mode", "debug_pattern_prev", "debug_pattern_next", "debug_pattern_fire"]

const DIR_ACTIONS := {
	"move_up": &"DODGE_UP", "move_down": &"DODGE_DOWN", "move_left": &"DODGE_LEFT", "move_right": &"DODGE_RIGHT",
	"parry": &"PARRY_X",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	for a in DIR_ACTIONS:
		if key.is_action(a):
			new_action.emit(DIR_ACTIONS[a], CombatClock.now_us())
			return
	for c in COMMANDS:
		if key.is_action(c):
			command.emit(StringName(c))
			return
