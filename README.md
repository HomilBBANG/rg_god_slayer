# RED — Godot 그래픽 프로토타입 v0.2

`GRAPHICS_PROTOTYPE_GDD_v0.2.md` 를 구현한 **Graphics Vertical Slice** 입니다.
3D 메시를 실시간 렌더링하되, 외곽선 없는 2~3단계 색면 조명으로 2D 회화풍 쿼터뷰처럼 보이게 하는 것이 목적입니다.

- 엔진: **Godot 4.7.2 Stable**, GDScript, **Forward+**
- 해상도: 1920×1080 고정 뷰포트, 16:9 (`stretch: canvas_items / keep`, 다른 비율은 레터박스)
- 검증 캡처: `docs/captures/` (1920×1080)
- 미구현/미검증 항목: `KNOWN_LIMITATIONS.md`

## 실행

1. Godot 4.7.2 에디터에서 **Import** → 이 폴더의 `project.godot` 선택.
2. F5 (또는 ▶) 로 실행. 메인 씬은 `res://scenes/Main.tscn`.
3. 창은 1600×900 으로 열리지만 내부 뷰포트는 항상 1920×1080 입니다 (F12 캡처도 1080p).

CLI:
```
godot --path <이 폴더>            # 실행
godot --path <이 폴더> -s tools/capture_runner.gd   # 자동 검증 + docs 캡처 재생성 (user://captures/)
```

## 조작 (Input Map 이름은 GDD 와 동일)

| 액션 | 키 | 기능 |
|---|---|---|
| `move_up / down / left / right` | ↑ ↓ ← → | **화면 기준** 이동, 대각선 정규화 |
| `attack` | Z | 단발 전방 근접 공격 (0.38 s) |
| `debug_toggle` | F1 | 디버그 정보 On/Off |
| `debug_light_cycle` | F2 | 태양 프리셋 순환 (기본 → 반대편 → 낮은 해) — A/B 비교용 |
| `debug_screenshot` | F12 | 1920×1080 PNG 저장 → `user://captures/` |
| `ui_cancel` | Esc | (기본 Godot 동작, 메뉴 없음) |

WASD, 마우스 조준/클릭 공격은 의도적으로 **없습니다**.

## 씬 / 파일 구조

```
game/
├─ project.godot
├─ scenes/
│  ├─ Main.tscn            # WorldEnvironment, DirectionalLight3D, TestCourtyard, Player, HitDummies, CameraRig, HUD
│  ├─ Player.tscn          # CharacterBody3D + 임시 로우폴리 신체 (박스 메시, 6등신 1.70 m)
│  ├─ CameraRig.tscn       # Node3D + Camera3D (직교, 고정각)
│  ├─ TestCourtyard.tscn   # 스크립트가 런타임에 프리미티브로 맵을 조립
│  └─ HitDummy.tscn        # StaticBody3D, 그룹 attack_targets, receive_hit()
├─ scripts/
│  ├─ player_controller.gd # 이동/방향/공격 상태 + 절차 애니메이션(Idle/Walk/Attack)
│  ├─ camera_follow.gd     # elevation 52°, azimuth 45°, distance 25 m, size 15, 지수 보간 추적
│  ├─ hit_dummy.gd         # 피격 카운터 + 0.1 s 기울임 반응
│  ├─ debug_hud.gd         # 체력 바, 조작 안내(10 s), F1 디버그
│  ├─ test_courtyard.gd    # 돌담/계단(램프 충돌)/폐허 건물(지붕 분리)/나무/아치/경계
│  └─ main.gd              # 라이트 프리셋(F2), 캡처(F12)
├─ shaders/RED_FlatLit.gdshader
├─ materials/mat_*.tres    # 팔레트별 ShaderMaterial (base_color 만 다름)
├─ ui/HUD.tscn
├─ tools/capture_runner.gd # 자동 검증/캡처 (개발용)
└─ docs/captures/          # 제출 캡처
```

## 카메라 (`camera_follow.gd` export)

| 항목 | 값 |
|---|---:|
| projection / keep_aspect | ORTHOGONAL / KEEP_HEIGHT |
| `ortho_size` | 15.0 (세로 15 m, 가로 26.67 m) |
| `elevation_deg` / `azimuth_deg` / `distance` | 52° / 45° / 25 m |
| `look_offset` | (0, 0.8, 0) |
| `smoothing_time` | 0.18 s (지수 보간) |
| `bounds_min / max` | 리그 목표 XZ 클램프 (−13,−9) ~ (13,9) |

실측: 1.70 m 인물 = **75 px @1080p** (F1 디버그의 `char px` 가 실시간으로 발/정수리를 투영해 계산). 70~90 px 범위 밖이면 `ortho_size` 13.5~17.0 에서 조절.

## 셰이더 `RED_FlatLit.gdshader`

`shader_type spatial`, `render_mode cull_back, depth_draw_opaque, specular_disabled, ambient_light_disabled`.
`fragment()` 가 `ALBEDO = base_color` 와 dark 밴드용 기본 어둠(EMISSION)을 깔고, `light()` 가 `dot(NORMAL, LIGHT) × ATTENUATION` 을 3단계로 양자화해 `DIFFUSE_LIGHT` 에 누적합니다. 방향광 그림자는 `ATTENUATION` 으로 들어오므로 그림자 = dark 밴드입니다.

| uniform | 기본값 | 의미 |
|---|---:|---|
| `base_color` | 재질별 | 조명 전 재질색 (GDD §2 팔레트) |
| `dark_factor` | 0.22 | 그림자/역광 면 밝기 |
| `mid_factor` | 0.65 | 중간 면 밝기 |
| `light_factor` | 1.0 | 직사광 면 밝기 |
| `threshold_low` | 0.32 | dark→mid 경계 (N·L×감쇠) |
| `threshold_high` | 0.70 | mid→light 경계 |
| `edge_softness` | 0.04 | 밴드 경계 smoothstep 폭 |
| `local_light_strength` | 0.25 | Omni/Spot 기여 제한 |
| `shadow_tint` | #33434A | dark 밴드에 섞는 청회색 |
| `shadow_tint_strength` | 0.55 | 청회색 비율 |

캐릭터(머리/피부/옷), 지면, 돌담, 나무, 더미 모두 같은 셰이더를 쓰며 머티리얼마다 `base_color` 만 다릅니다.

## 조명

- `DirectionalLight3D` 1개, 그림자 ON (4096, soft filter medium), 색 `(0.98, 0.93, 0.80)`.
- 태양 방향은 `main.gd` 의 `light_presets` 에서 **화면 기준** `[고도각, 방위각(0=화면 오른쪽, 90=화면 위), 에너지]` 로 정의하고 카메라 축을 이용해 월드 방향으로 변환합니다. 기본 = 48°, 10°: 인물/벽의 오른쪽 면이 밝고 그림자가 화면 왼쪽으로 떨어집니다.
- `WorldEnvironment`: 단색 배경(저채도 청회), ambient 약함(셰이더가 `ambient_light_disabled` 라 색면에는 영향 없음), 톤매핑 Filmic, 채도 0.9. GI/SSGI/SSR/SSAO/Glow/DOF/Fog 전부 OFF.
- MSAA 2×.

## 플레이어 수치 (`player_controller.gd` export)

이동 3.4 m/s, 가속 12 m/s², 감속 18 m/s², 중력 9.8, 회전 보간 14/s.
공격 0.38 s (준비 0~0.10, 유효 0.10~0.19, 복귀 ~0.38), 사거리 1.45 m + 더미 반경, 전방 100°, 공격 중 이동 40%, 한 공격당 더미 1회 타격.

## 맵 (`test_courtyard.gd`)

36×28 m. 중앙 광장(돌길 3장) → 동쪽 좁은 돌담 통로(폭 ~3.6 m) → 북동 계단(보이는 5단 메시 + 26.6° 램프 충돌) → 1 m 테라스(더미 02).
서북쪽 폐허 건물(입구 1, 무너진 동쪽 벽, **지붕은 별도 노드** — 플레이어가 들어가면 Area3D 가 숨김), 돌담 8개, 나무 3그루(수관 4덩어리), 그림자 가림 시험용 아치, 경계 투명벽.
