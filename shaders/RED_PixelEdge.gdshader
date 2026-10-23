// RED_PixelEdge — 저해상도 3D 픽셀아트용 1픽셀 에지 후처리 (기사 §Outlines)
//
// 카메라 자식 풀스크린 쿼드에 붙는다 (Godot 4 "Advanced post-processing" 방식).
//  - 커널은 상하좌우 4텍셀만 → 선은 항상 1텍셀.
//  - 깊이 텍스처: 이웃이 '나보다 멀면' 이 픽셀은 가까운 물체의 실루엣 (볼록 에지만, 물체 안쪽에 그려짐).
//    경사진 면(지면)을 비스듬히 볼 때 생기는 가짜 에지는 뷰 노멀 각도로 임계값을 키워 억제 (Roystan).
//  - 노멀 텍스처: 같은 표면에서 노멀이 꺾이고 내 면이 더 위를 향하면 면 분리 하이라이트.
//  - 조명과 통합: 밝은(빛 받는) 픽셀의 선은 밝게, 어두운(그림자) 픽셀의 선은 어둡게 → 잉크선이 아니라 색면의 연장.
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

// 깊이 에지: 이웃이 이만큼(m) 더 멀면 실루엣
uniform float depth_threshold : hint_range(0.01, 2.0) = 0.22;
// 비스듬한 면일수록 깊이 임계값을 키우는 정도
uniform float depth_angle_scale : hint_range(0.0, 10.0) = 3.0;
// 실루엣 픽셀 색 곱 (0=검정, 1=없음)
uniform float edge_darken : hint_range(0.0, 1.0) = 0.55;
// 노멀 에지: 1 - dot(n, n_neighbor) 가 이 값보다 크면 면 꺾임
uniform float normal_threshold : hint_range(0.0, 1.0) = 0.35;
// 면 꺾임 선: 밝은 픽셀엔 가산, 어두운 픽셀엔 곱
uniform float edge_lighten : hint_range(0.0, 0.5) = 0.12;
uniform float edge_shadow_darken : hint_range(0.0, 1.0) = 0.8;
// 노멀 하이라이트는 위(+Y 뷰공간 up)를 더 향한 면에만
uniform float highlight_up_bias : hint_range(0.0, 1.0) = 0.15;
// 이 휘도보다 밝으면 '빛 받는 픽셀'
uniform float lit_luma_low : hint_range(0.0, 1.0) = 0.16;
uniform float lit_luma_high : hint_range(0.0, 1.0) = 0.30;


void vertex() {
	// 화면을 덮는 쿼드. reversed-Z 이므로 near = 1.0
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}


vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).rgb * 2.0 - 1.0);
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 col = texture(screen_tex, uv).rgb;

	float dc = linear_depth(uv, INV_PROJECTION_MATRIX);
	vec3 nc = view_normal(uv);
	// 직교 카메라: 뷰 방향은 항상 -Z. 비스듬한 면(nc.z 작음)은 임계값을 키운다.
	float grazing = 1.0 - clamp(nc.z, 0.0, 1.0);
	float d_thresh = depth_threshold * (1.0 + grazing * depth_angle_scale);

	vec2 offs[4] = {vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y)};
	float depth_edge = 0.0;
	float normal_edge = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 nuv = uv + offs[i];
		float dn = linear_depth(nuv, INV_PROJECTION_MATRIX);
		// 이웃이 더 멀다 → 나는 앞 물체의 가장자리
		depth_edge = max(depth_edge, step(d_thresh, dn - dc));
		vec3 nn = view_normal(nuv);
		float bend = 1.0 - dot(nc, nn);
		// 깊이 차가 거의 없는(같은 물체) 면 꺾임만, 그리고 내 면이 이웃보다 더 위를 향할 때만
		float same_surface = 1.0 - step(d_thresh, abs(dn - dc));
		float faces_up_more = step(highlight_up_bias, nc.y - nn.y);
		normal_edge = max(normal_edge, step(normal_threshold, bend) * same_surface * faces_up_more);
	}

	// 조명 통합: 픽셀 휘도로 빛 받는 면인지 판단
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float lit = smoothstep(lit_luma_low, lit_luma_high, luma);
	// 면 꺾임 선: 밝은 쪽은 밝게, 그림자 쪽은 더 어둡게
	float ne = normal_edge * (1.0 - depth_edge);
	col += vec3(edge_lighten) * ne * lit;
	col *= mix(1.0, edge_shadow_darken, ne * (1.0 - lit));
	// 실루엣: 밝은 면 가장자리는 덜, 어두운 면 가장자리는 더 어둡게
	float dark = mix(edge_darken * 0.8, edge_darken + (1.0 - edge_darken) * 0.4, lit);
	col *= mix(1.0, dark, depth_edge);
	ALBEDO = col;
}
