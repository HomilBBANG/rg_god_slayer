# 캡처 (1920×1080, Godot 4.7.2 Forward+, 640×360 픽셀 렌더 ×3, Xvfb + lavapipe)

| 파일 | 내용 |
|---|---|
| 01_idle.png | Idle — 아치 그림자 옆, 기본 태양 프리셋 |
| 02_move.png | ↑+→ 이동 중 (Walk 포즈) |
| 03_attack.png | Z 공격 유효 타격 구간(0.10~0.19 s), 더미 01 피격 직전 |
| 04_debug_hud.png | F1 디버그 정보 (char px ≈ 75) |
| 05_light_A_default.png | 태양 A: 고도 48°, 화면 오른쪽 |
| 06_light_B_opposite.png | 태양 B: 고도 48°, 화면 왼쪽 (A 와 그림자·면 명암 반전) |
| 07_light_C_low_sun.png | 태양 C: 고도 26°, 에너지 0.75 (긴 그림자, 밴드 이동) |
| 08_stairs_terrace.png | 계단(램프 충돌)으로 오른 1 m 테라스, 더미 02 |
| 09_dodge_back.png | Shift (입력 없음) — 시선 유지한 채 뒤로 백스텝, 웅크림 포즈 |
| 10_dodge_left.png | ← + Shift — 왼쪽으로 몸을 던지는 점프 |

재생성: `godot --path game -s tools/capture_runner.gd` → `user://captures/`
