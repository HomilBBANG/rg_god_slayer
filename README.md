# RED — Godot 그래픽 프로토타입 v0.2

`GRAPHICS_PROTOTYPE_GDD_v0.2.md` 를 구현한 **Graphics Vertical Slice** 입니다.
3D 메시를 실시간 렌더링하되, 2~3단계 색면 조명 + 저해상도 픽셀 렌더로 2D 픽셀아트 쿼터뷰처럼 보이게 하는 것이 목적입니다.
픽셀 파이프라인은 David Holland 의 *3D Pixel Art Rendering* (t3ssel8r 계열) 기법을 따릅니다 — 저해상도 렌더 타겟, 텍셀 스냅 카메라 + 서브픽셀 패닝, 깊이/노멀 1픽셀 에지.

- 엔진: **Godot 4.7.2 Stable**, GDScript, **Forward+**
- 해상도: 1920×1080 고정 뷰포트, 16:9 (`stretch: canvas_items / keep`, 다른 비율은 레터박스)
- 검증 캡처: `docs/captures/` (1920×1080)
- 미구현/미검증 항목: `KNOWN_LIMITATIONS.md`

## 실행

1. Godot 4.7.2 에디터에서 **Import** → 이 폴더의 `project.godot` 선택.
2. F5 (또는 ▶) 로 실행. 메인 씬은 `res://scenes/Main.tscn`.
3. 창은 1920×1080 으로 열립니다. 화면이 작으면 **F11** 로 전체화면 전환. 내부 뷰포트는 항상 1920×1080 (F12 캡처도 1080p).

CLI:
```
godot --path <이 폴더>            # 실행
godot --path <이 폴더> -s tools/capture_runner.gd   # 자동 검증 + docs 캡처 재생성 (user://captures/)
```

## 조작 (Input Map 이름은 GDD 와 동일)

| 액션 | 키 | 기능 |
|---|---|---|
| `move_up / down / left / right` | ↑ ↓ ← → | **화면 기준** 이동, 대각선 정규화 |
| `attack` | Z | 단발 전방 근접 공격 (0.30 s) |
| `dodge` | Shift | 회피: 방향키 방향으로 짧은 점프. 입력 없으면 보는 방향 반대로 백스텝(시선 유지) |
| `debug_toggle` | F1 | 디버그 정보 On/Off |
| `debug_light_cycle` | F2 | 태양 프리셋 순환 (기본 → 반대편 → 낮은 해) — A/B 비교용 |
| `debug_fullscreen` | F11 | 전체화면 토글 |
| `debug_screenshot` | F12 | 1920×1080 PNG 저장 → `user://captures/` |
| `ui_cancel` | Esc | (기본 Godot 동작, 메뉴 없음) |

WASD, 마우스 조준/클릭 공격은 의도적으로 **없습니다**.

## 씬 / 파일 구조

```
game/
├─ project.godot
├─ scenes/
│  ├─ Main.tscn            # PixelScreen(TextureRect) ← World(SubViewport 644×364): 환경/광원/맵/플레이어/더미/카메라, HUD
│  ├─ Player.tscn          # CharacterBody3D + 임시 로우폴리 신체 (박스 메시, 6등신 1.70 m)
│  ├─ CameraRig.tscn       # Node3D + Camera3D (직교, 고정각)
│  ├─ TestCourtyard.tscn   # 스크립트가 런타임에 프리미티브로 맵을 조립
│  └─ HitDummy.tscn        # StaticBody3D, 그룹 attack_targets, receive_hit()
├─ scripts/
│  ├─ player_controller.gd # 이동/방향/공격/회피 상태 + 절차 애니메이션(Idle/Walk/Attack/Dodge)
│  ├─ camera_follow.gd     # elevation 52°, azimuth 45°, distance 25 m, size 15, 지수 보간 추적, 텍셀 스냅
│  ├─ hit_dummy.gd         # 피격 카운터 + 0.1 s 기울임 반응
│  ├─ debug_hud.gd         # 체력 바, 조작 안내(10 s), F1 디버그
│  ├─ test_courtyard.gd    # 돌담/계단(램프 충돌)/폐허 건물(지붕 분리)/나무/아치/경계
│  └─ main.gd              # 픽셀 스크린 합성/서브픽셀 패닝, 라이트 프리셋(F2), 캡처(F12), 전체화면(F11)
├─ shaders/RED_FlatLit.gdshader   # 3단계 색면 라이팅 (전 오브젝트 공통)
├─ shaders/RED_PixelEdge.gdshader # 깊이/노멀 1픽셀 에지 후처리
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
| `smoothing_time` | 0.12 s (지수 보간) |
| `pixel_scale` | 3 → 렌더 640×360 (+여유 2텍셀) 을 1080p 에 3배 nearest 확대 |
| `margin_texels` | 2 (서브픽셀 패닝용 여유) |
| `snap_enabled` | true (카메라를 텍셀 단위로 양자화, 잔량은 화면 TextureRect 오프셋으로) |
| `bounds_min / max` | 리그 목표 XZ 클램프 (−13,−9) ~ (13,9) |

실측: 1.70 m 인물 = **75 px @1080p = 25 텍셀** (F1 디버그의 `char px`). 캐릭터를 더 크게 보려면 `ortho_size` 를 낮추거나 `pixel_scale` 을 2 로 (960×540 렌더, 37 텍셀).

## 픽셀 파이프라인

1. `Main/World` SubViewport 가 `(1920/scale + 4) × (1080/scale + 4)` 로 3D 를 렌더 (MSAA/AA 없음, 하드 섀도).
2. `PixelScreen` TextureRect 가 그 텍스처를 nearest 필터로 정수 배율 확대. 바깥 2텍셀 여유는 화면 밖에 있다.
3. `camera_follow.gd` 가 매 프레임 카메라 위치를 화면 right/up 축에서 텍셀 단위로 내림 → 월드가 텍셀 격자에 고정되어 "픽셀 크리핑" 이 없다. 남은 서브텍셀 잔량 × scale 만큼 `PixelScreen` 을 반대로 밀어 스크롤은 부드럽다.
4. `RED_PixelEdge.gdshader` (카메라 자식 풀스크린 쿼드): 이웃 4텍셀의 선형 깊이가 `depth_threshold` 이상 멀면 실루엣; 같은 깊이에서 노멀이 `normal_threshold` 이상 꺾이고 내 면이 더 위를 향하면 면 분리 선. 항상 1텍셀, 볼록 에지만. 비스듬한 면은 `depth_angle_scale` 로 임계값을 키워 가짜 에지를 막고(Roystan), **조명과 통합** — 픽셀 휘도가 높으면(빛 받는 면) 선을 밝게, 낮으면(그림자) 더 어둡게 그린다.
5. 구름 그림자: `[shader_globals] cloud_noise` (NoiseTexture2D, seamless) 를 월드 XZ 에 투영해 방향광 감쇠에 곱한다 (`RED_bands.gdshaderinc::get_cloud_attenuation`). `cloud_wind` 로 흐른다.
6. 잔디: `GrassField` (MultiMesh, 드로우콜 1) + `RED_Grass.gdshader` — Y축 빌보드, 알파 시저 텍스처, `LIGHT_VERTEX` 를 밑동으로 두어 쿼드 전체가 지면과 같은 조명/그림자 밴드를 받는다.
7. 볼류메트릭(갓레이): `LightShafts` 가 빛 방향을 품은 평행 평면 12장을 카메라 쪽으로 세워 겹치고, `RED_LightShaft.gdshader` 가 각 평면에서 방향광 섀도 `ATTENUATION` 이 1인 곳만 가산(blend_add). 지면/물체 근처는 깊이 페이드, 높이 페이드. 태양 프리셋이 바뀌면 `rebuild()`.

| PixelEdge uniform | 기본값 |
|---|---:|
| `depth_threshold` | 0.22 m |
| `depth_angle_scale` | 3.0 |
| `edge_darken` | 0.55 (1=끔) |
| `normal_threshold` | 0.35 |
| `edge_lighten` | 0.12 (0=끔) |
| `edge_shadow_darken` | 0.8 |
| `highlight_up_bias` | 0.15 |
| `lit_luma_low / high` | 0.16 / 0.30 |

| LightShaft uniform | 기본값 |
|---|---:|
| `intensity` | 0.032 |
| `fade_height_start / end` | 1.0 / 7.5 m |
| `depth_fade` | 1.2 m |
| `plane_count / spacing` (노드) | 12 / 1.6 m |

GDD 의 "외곽선 없음" 원칙과는 다른 방향이라, 두 값을 1.0 / 0.0 으로 두면 에지 없이 색면만 남습니다.

## 셰이더 `RED_FlatLit.gdshader`

`shader_type spatial`, `render_mode cull_back, depth_draw_opaque, specular_disabled, ambient_light_disabled`.
`fragment()` 가 `ALBEDO = base_color` 와 dark 밴드용 기본 어둠(EMISSION)을 깔고, `light()` 가 `dot(NORMAL, LIGHT) × ATTENUATION` 을 3단계로 양자화해 `DIFFUSE_LIGHT` 에 누적합니다 (Godot 4 는 `light()` 뒤에 ALBEDO 를 곱하므로 `light()` 안에서는 곱하지 않음). 방향광 그림자는 `ATTENUATION` 으로 들어오므로 그림자 = dark 밴드. 밴드/구름/감쇠 스무딩 코드는 `RED_bands.gdshaderinc` 에 있고 `RED_Grass` 와 공유합니다.

| uniform | 기본값 | 의미 |
|---|---:|---|
| `base_color` | 재질별 | 조명 전 재질색 (GDD §2 팔레트) |
| `dark_factor` | 0.40 | 그림자/역광 면 밝기 (레퍼런스처럼 그림자도 중채도) |
| `mid_factor` | 0.72 | 중간 면 밝기 |
| `light_factor` | 1.0 | 직사광 면 밝기 |
| `threshold_low` | 0.32 | dark→mid 경계 (N·L×감쇠) |
| `threshold_high` | 0.70 | mid→light 경계 |
| `edge_softness` | 0.04 | 밴드 경계 smoothstep 폭 |
| `local_light_strength` | 0.25 | Omni/Spot 기여 제한 |
| `shadow_smooth` | 0.25 | 방향광 그림자 감쇠 smoothstep 폭 |
| `cloud_scale / wind / strength` | 0.011 / (0.6, 0.25) / 0.38 | 구름 그림자 |
| `cloud_cover_low / high` | 0.48 / 0.62 | 노이즈 → 구름 임계 |
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

## 환경 에셋 (Blender 절차 생성)

`tools/blender/gen_assets.py` 가 Blender 헤드리스로 레퍼런스(t3ssel8r 풍) 에셋을 만들어 `assets/environment/*.glb` 로 내보냅니다.

```
blender -b -P tools/blender/gen_assets.py -- assets/environment   # Blender 4.0 + numpy 필요
python3 tools/gen_textures.py                                      # 잎/풀/꽃 픽셀 카드 텍스처
```

| 에셋 | 구성 |
|---|---|
| `tree_a/b.glb` | 7각 테이퍼 줄기 + 뿌리혹, smooth-min 구 합집합 표면에 포아송 간격으로 뿌린 잎 카드 ~250장. **카드 노멀 = 캐노피 볼륨 노멀** → 덩어리 하나처럼 2~3톤 음영 |
| `rock_a~d.glb` | 노이즈 변위 이코스피어, 각도 제한 디졸브로 큰 면만, 플랫 셰이딩, 바닥 평평 |
| `bush_a/b.glb` | 납작 둔덕(smooth) + 테두리 풀 카드(노멀 위) |
| `pillar_a/b.glb`, `block_a/b.glb` | 꼭짓점을 안으로 깎은 돌 블록을 쌓은 폐허 기둥 / 흩어진 블록 |

카드는 카메라(고도 52°, 방위 45°)를 향하도록 **미리 회전**해 두므로 나무·덤불은 yaw 0 으로만 배치합니다 (변형은 variant 로). glTF 머티리얼 이름(Leaf/Bark/Rock/Stone/Bush/GrassCard)을 `scripts/env_assets.gd` 가 `materials/mat_*.tres` 로 치환하고, 바위/기둥/블록엔 볼록 껍질, 나무엔 줄기 실린더 충돌을 붙입니다.
잎/풀 카드는 `RED_Leaf.gdshader` (알파 시저, 메시 커스텀 노멀, 자기 그림자 미수신, 바람). 꽃은 `FlowerField` (GrassField 재사용, 8×8 스프라이트).

## 맵 (`test_courtyard.gd`)

36×28 m, 풀밭 위에 흙 광장. 중앙 광장(돌길 3장) → 동쪽 좁은 돌담 통로(폭 ~3.6 m) → 북동 계단(보이는 5단 메시 + 26.6° 램프 충돌) → 1 m 테라스(더미 02).
서북쪽 폐허 건물(입구 1 + 문설주, 창 구멍, 무너진 동쪽 벽, **지붕은 별도 노드** — 플레이어가 들어가면 Area3D 가 숨김), 돌담 8개 + 갓돌, 그림자 가림 시험용 아치, 경계 투명벽.
Blender 에셋 배치: 나무 4, 바위 9, 덤불 8, 기둥 4, 블록 4 + 잔디 텍셀 뭉치(MultiMesh) + 꽃 스프라이트.
