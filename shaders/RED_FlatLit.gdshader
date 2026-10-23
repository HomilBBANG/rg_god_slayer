// RED_FlatLit — 조명 반응형 2D 색면 셰이더
//
// 원칙 (GDD §7):
//  - 외곽선 없음, 정반사 없음, 텍스처 없음. base_color 한 가지와 조명만으로 그림을 만든다.
//  - light()에서 직접광을 3단계(dark/mid/light) 밴드로 양자화하고 얇은 smoothstep 경계로 완화한다.
//  - DirectionalLight3D 그림자는 ATTENUATION을 통해 그대로 받는다 (그림자 = dark 밴드).
//  - 캐릭터·지면·벽·나무 전부 이 셰이더를 공유하며 머티리얼마다 base_color만 다르다.
//  - render_mode unshaded 금지. 실제 광원 방향/에너지 변화에 결과가 따라가야 한다.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled, ambient_light_disabled;

// 재질 시작값 (조명 전). GDD §2 팔레트에서 선택.
uniform vec3 base_color : source_color = vec3(0.6, 0.6, 0.6);

// 3단계 밴드 밝기 계수
uniform float dark_factor : hint_range(0.0, 1.0) = 0.22;
uniform float mid_factor : hint_range(0.0, 1.0) = 0.65;
uniform float light_factor : hint_range(0.0, 2.0) = 1.0;

// 밴드 경계 (N·L × 감쇠 기준)
uniform float threshold_low : hint_range(0.0, 1.0) = 0.32;
uniform float threshold_high : hint_range(0.0, 1.0) = 0.70;
uniform float edge_softness : hint_range(0.0, 0.2) = 0.04;

// 비-방향광(Omni/Spot)의 기여 제한. 프로토타입은 태양광 1개만 쓰므로 거의 사용되지 않는다.
uniform float local_light_strength : hint_range(0.0, 1.0) = 0.25;

// 그림자/어두운 면을 물들이는 청회색. WorldEnvironment의 ambient 대신 셰이더가 직접 더한다.
uniform vec3 shadow_tint : source_color = vec3(0.20, 0.26, 0.29);
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	ALBEDO = base_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	// 주광이 전혀 닿지 않는 면도 완전한 검정이 되지 않도록, 색면용 기본 어둠을 한 번만 깔아 둔다.
	// (ambient_light_disabled 이므로 환경 ambient는 여기에 더해지지 않는다.)
	EMISSION = mix(base_color * dark_factor, shadow_tint * dark_factor, shadow_tint_strength);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// ATTENUATION 에 방향광 그림자가 포함된다 → 그림자 속은 lit ≈ 0 → dark 밴드.
	float lit = ndl * ATTENUATION;

	float to_mid = smoothstep(threshold_low - edge_softness, threshold_low + edge_softness, lit);
	float to_light = smoothstep(threshold_high - edge_softness, threshold_high + edge_softness, lit);

	// dark 밴드는 fragment()의 EMISSION이 이미 담당하므로 light()는 그 위에 얹는 양만 계산한다.
	float band = mix(0.0, mid_factor - dark_factor, to_mid);
	band = mix(band, light_factor - dark_factor, to_light);

	float strength = LIGHT_IS_DIRECTIONAL ? 1.0 : local_light_strength;
	// LIGHT_COLOR 는 색 × 에너지 × PI 이므로 PI로 나눠 1.0 기준으로 되돌린다.
	DIFFUSE_LIGHT += ALBEDO * (LIGHT_COLOR / PI) * band * strength;
}
