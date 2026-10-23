// RED_LightShaft — 광원 방향에 평행한 평면 셸 볼류메트릭 (기사 §Volumetric Lighting, t3ssel8r)
//
// 광원 방향을 품은 평행 평면 N장을 겹쳐 두고, 각 평면 픽셀이 '그림자 속인지' 를
// 표준 라이팅의 ATTENUATION(방향광 섀도맵)으로 판정해 빛이 닿는 곳만 가산한다.
// 평면이 겹치면서 빛 기둥/대기 산란 느낌이 생긴다. 지면/물체와의 교차는 깊이 페이드로 부드럽게.
shader_type spatial;
render_mode blend_add, cull_disabled, depth_draw_never, depth_test_disabled, specular_disabled, ambient_light_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 shaft_color : source_color = vec3(1.0, 0.92, 0.72);
uniform float intensity : hint_range(0.0, 0.5) = 0.03;
// 지면 위 이 높이부터 서서히 사라짐
uniform float fade_height_start : hint_range(0.0, 20.0) = 1.0;
uniform float fade_height_end : hint_range(0.0, 30.0) = 7.5;
// 물체/지면 표면과 이 거리(m) 안에서 페이드
uniform float depth_fade : hint_range(0.01, 5.0) = 1.2;

varying vec3 world_pos;
varying float view_depth;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}


float scene_linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}


void fragment() {
	// 지면 아래는 그리지 않고, 평면이 지면/물체 뒤에 있으면 버린다 (depth_test_disabled 이므로 직접 처리)
	float scene_d = scene_linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float behind = scene_d - view_depth;
	if (behind < 0.0 || world_pos.y < 0.0) {
		discard;
	}
	float df = clamp(behind / depth_fade, 0.0, 1.0);
	float hf = 1.0 - smoothstep(fade_height_start, fade_height_end, world_pos.y);
	// ALBEDO 는 light() 뒤에 DIFFUSE_LIGHT 에 곱해지므로 빛 기둥 색을 여기에 둔다
	ALBEDO = shaft_color;
	ALPHA = df * hf;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}


void light() {
	// 평면은 빛 방향을 품고 있어 N·L ≈ 0 이므로 각도는 무시하고 섀도 감쇠만 쓴다
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += (LIGHT_COLOR / PI) * ATTENUATION * intensity;
	}
}
