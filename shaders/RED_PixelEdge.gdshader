// RED_PixelEdge — 저해상도 3D 픽셀아트용 1픽셀 에지 후처리
//
// 카메라 자식 풀스크린 쿼드에 붙는다 (Godot 4 "Advanced post-processing" 방식).
// 참고 기법 (David Holland / t3ssel8r 3D pixel art):
//  - 깊이 텍스처: 이웃 4텍셀 중 하나라도 '나보다 멀면' 이 픽셀은 가까운 물체의 실루엣 → 어둡게 (볼록 에지만, 항상 1px)
//  - 노멀 텍스처: 이웃과 노멀이 꺾이고 내 면이 더 위/카메라를 향하면 → 살짝 밝게 (면 분리 하이라이트)
//  - 검은 잉크선이 아니라 그 픽셀 색을 곱/더하는 방식이라 저채도 색면 그림체를 해치지 않는다.
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

// 깊이 에지: 이웃이 이만큼(m) 더 멀면 실루엣
uniform float depth_threshold : hint_range(0.01, 2.0) = 0.22;
// 실루엣 픽셀 색 곱 (0=검정, 1=없음)
uniform float edge_darken : hint_range(0.0, 1.0) = 0.55;
// 노멀 에지: 1 - dot(n, n_neighbor) 가 이 값보다 크면 면 꺾임
uniform float normal_threshold : hint_range(0.0, 1.0) = 0.35;
// 면 꺾임 하이라이트 가산량
uniform float edge_lighten : hint_range(0.0, 0.5) = 0.12;
// 노멀 하이라이트는 위(+Y 뷰공간 up)를 더 향한 면에만
uniform float highlight_up_bias : hint_range(0.0, 1.0) = 0.15;


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

	vec2 offs[4] = {vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y)};
	float depth_edge = 0.0;
	float normal_edge = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 nuv = uv + offs[i];
		float dn = linear_depth(nuv, INV_PROJECTION_MATRIX);
		// 이웃이 더 멀다 → 나는 앞 물체의 가장자리
		depth_edge = max(depth_edge, step(depth_threshold, dn - dc));
		vec3 nn = view_normal(nuv);
		float bend = 1.0 - dot(nc, nn);
		// 깊이 차가 거의 없는(같은 물체) 면 꺾임만, 그리고 내 면이 이웃보다 더 위를 향할 때만
		float same_surface = 1.0 - step(depth_threshold, abs(dn - dc));
		float faces_up_more = step(highlight_up_bias, nc.y - nn.y);
		normal_edge = max(normal_edge, step(normal_threshold, bend) * same_surface * faces_up_more);
	}

	// 실루엣이 하이라이트보다 우선
	col += vec3(edge_lighten) * normal_edge * (1.0 - depth_edge);
	col *= mix(1.0, edge_darken, depth_edge);
	ALBEDO = col;
}
