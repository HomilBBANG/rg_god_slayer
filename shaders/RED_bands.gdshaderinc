// RED 공통 조명 조각 — 3단계 밴드 + 방향광 감쇠 스무딩 + 구름 그림자
// RED_FlatLit / RED_Grass 가 #include 해서 같은 그림체를 공유한다.

// 3단계 밴드 밝기 계수
uniform float dark_factor : hint_range(0.0, 1.0) = 0.22;
uniform float mid_factor : hint_range(0.0, 1.0) = 0.65;
uniform float light_factor : hint_range(0.0, 2.0) = 1.0;

// 밴드 경계 (N·L × 감쇠 기준)
uniform float threshold_low : hint_range(0.0, 1.0) = 0.32;
uniform float threshold_high : hint_range(0.0, 1.0) = 0.70;
uniform float edge_softness : hint_range(0.0, 0.2) = 0.04;

// 방향광 그림자 감쇠를 부드럽게 (느리게 움직이는 해의 그림자 깜빡임 완화, 기사 §Lighting)
uniform float shadow_smooth : hint_range(0.0, 0.5) = 0.25;

// 비-방향광(Omni/Spot)의 기여 제한
uniform float local_light_strength : hint_range(0.0, 1.0) = 0.25;

// 구름 그림자 — 글로벌 노이즈 텍스처를 월드 XZ 에 투영해 방향광 감쇠에 곱한다 (기사 §Lighting)
global uniform sampler2D cloud_noise;
uniform float cloud_scale : hint_range(0.001, 0.2) = 0.011;
uniform vec2 cloud_wind = vec2(0.6, 0.25);
uniform float cloud_strength : hint_range(0.0, 1.0) = 0.38;
uniform float cloud_cover_low : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_cover_high : hint_range(0.0, 1.0) = 0.62;


// 월드 위치의 구름 감쇠 (1 = 맑음, 1-cloud_strength = 구름 그늘)
float get_cloud_attenuation(vec3 world_pos, float t) {
	vec2 uv = world_pos.xz * cloud_scale + cloud_wind * t * cloud_scale;
	float n = texture(cloud_noise, uv).r;
	float cloud = smoothstep(cloud_cover_low, cloud_cover_high, n);
	return 1.0 - cloud * cloud_strength;
}


// 방향광 감쇠(그림자) 스무딩
float smooth_shadow(float attenuation) {
	return smoothstep(0.5 - shadow_smooth, 0.5 + shadow_smooth, attenuation);
}


// lit(0~1) → dark 밴드 위에 얹을 밝기 (dark 밴드 자체는 fragment 의 EMISSION 이 담당)
float band_above_dark(float lit) {
	float to_mid = smoothstep(threshold_low - edge_softness, threshold_low + edge_softness, lit);
	float to_light = smoothstep(threshold_high - edge_softness, threshold_high + edge_softness, lit);
	float band = mix(0.0, mid_factor - dark_factor, to_mid);
	return mix(band, light_factor - dark_factor, to_light);
}
