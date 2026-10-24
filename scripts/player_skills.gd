## 플레이어 스킬 (K 창). 프로토타입이라 포인트 없이 자유롭게 올리고 내린다.
## 순발력(reflex): 치명적 판단 창 0.20 s → +0.06 s/단계, 최대 5 (0.50 s)
## 판단력(judgement): 슬로모션 유지 시간 1.0 s → +1.0 s/단계, 최대 3 (4.0 s)
class_name PlayerSkills
extends Node

signal changed

const REFLEX_MAX := 5
const JUDGEMENT_MAX := 3
const DECISION_BASE := 0.20
const DECISION_STEP := 0.06
const SLOW_BASE := 1.0
const SLOW_STEP := 1.0

var reflex: int = 0
var judgement: int = 0


func decision_seconds() -> float:
	return DECISION_BASE + DECISION_STEP * reflex


func slow_seconds() -> float:
	return SLOW_BASE + SLOW_STEP * judgement


func set_reflex(v: int) -> void:
	reflex = clampi(v, 0, REFLEX_MAX)
	changed.emit()


func set_judgement(v: int) -> void:
	judgement = clampi(v, 0, JUDGEMENT_MAX)
	changed.emit()
