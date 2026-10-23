// RED_Grass — 균일 조명 잔디 빌보드 (기사 §Grass)
//
//  - Y축 빌보드 쿼드 + 잔디 텍스처(알파 시저). 바람에 살짝 흔들림.
//  - LIGHT_VERTEX 를 메시 밑동(인스턴스 원점)으로 두어 쿼드 전체가 '발밑 지면과 같은 조명'을 받는다
//    → 그림자 경계가 쿼드를 가로지르며 잘리지 않고, 지형과 같은 밴드로 섞여 들어간다.
//  - 노멀은 항상 위(+Y) 로 고정해 지면과 같은 밝기 밴드를 갖는다.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled, ambient_light_disabled;

#include "res://shaders/RED_bands.gdshaderinc"

uniform sampler2D tuft_tex : source_color, filter_nearest, repeat_disable;
uniform vec3 base_color : source_color = vec3(0.57, 0.61, 0.46);
uniform vec3 shadow_tint : source_color = vec3(0.20, 0.26, 0.29);
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.55;
uniform float sway_amount : hint_range(0.0, 0.3) = 0.05;
uniform float sway_speed : hint_range(0.0, 5.0) = 1.4;

varying vec3 base_world;


void vertex() {
	// Y축 빌보드 (Godot BillboardMode Y 와 동일한 식), 인스턴스 스케일 유지
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	// 윗부분만 바람에 흔들림
	float phase = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 1.3;
	VERTEX.x += sin(TIME * sway_speed + phase) * sway_amount * max(VERTEX.y, 0.0);
	base_world = MODEL_MATRIX[3].xyz;
}


void fragment() {
	vec4 t = texture(tuft_tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = base_color * t.rgb * 1.1;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	// 지면처럼 위를 보는 노멀, 조명은 밑동 위치에서 계산
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	LIGHT_VERTEX = (VIEW_MATRIX * vec4(base_world, 1.0)).xyz;
	EMISSION = mix(ALBEDO * dark_factor, shadow_tint * dark_factor, shadow_tint_strength);
}


void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float strength = local_light_strength;
	float atten = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		strength = 1.0;
		atten = smooth_shadow(ATTENUATION) * get_cloud_attenuation(base_world, TIME);
	}
	// ALBEDO 는 Godot 이 light() 뒤에 곱한다
	DIFFUSE_LIGHT += (LIGHT_COLOR / PI) * band_above_dark(ndl * atten) * strength;
}
