## 보스 → 플레이어 피격 판정의 단일 권한 (GDD §13). 즉사 전환은 여기서만 일어난다.
class_name BossHitResolver
extends Node

var director: CombatDirector
var player: PlayerController


## 일반 패턴 유효 타격 중 플레이어가 영역 안에 있을 때. true = 치명 처리됨
func boss_hit_player(pattern: BossAttackPattern, boss: BossController, reason: String = "hit") -> bool:
	if director == null or director.state != CombatDirector.BattleState.COMBAT:
		return false
	if player.invulnerable:
		return false
	# 일반 패턴 패링 (parryable=true 인 일반 공격만, 타격 전후 ±0.10 s 게임 시간 → 플레이어의 패링 활성창)
	if pattern.parryable and not pattern.is_fatal() and player.is_parry_active():
		boss.on_parried()
		director.log_event(pattern.id, "PARRY_X", 0, "parry_normal")
		return false
	director.player_died("%s %s" % [pattern.id, reason])
	return true


## 치명적 패턴 실패 — 공격이 명중한다
func kill_player(pattern: BossAttackPattern, reason: String) -> void:
	if director == null or director.state != CombatDirector.BattleState.COMBAT:
		return
	director.player_died("%s %s" % [pattern.id, reason])
