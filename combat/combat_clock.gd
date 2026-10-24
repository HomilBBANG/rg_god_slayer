## 전투 판정용 현실 시계. 기본은 Time.get_ticks_usec() (단조 증가, Engine.time_scale 무관).
## virtual_enabled 는 오프라인 녹화(--fixed-fps) 전용: 러너가 프레임마다 가상 시계를 1/30 s 씩 전진시켜
## 저사양 환경에서도 현실 시간 비율이 맞는 영상을 만든다. 게임플레이/테스트에서는 절대 켜지 않는다.
class_name CombatClock
extends RefCounted

static var virtual_enabled: bool = false
static var virtual_us: int = 0


static func now_us() -> int:
	return virtual_us if virtual_enabled else Time.get_ticks_usec()
