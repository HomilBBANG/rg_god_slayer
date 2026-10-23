// RED_Leaf — 잎/풀 카드 셰이더 (Blender 에서 카메라를 향하도록 미리 회전해 둔 쿼드용)
//
//  - 카드마다 Blender 가 심어 둔 커스텀 노멀(나무: 캐노피 볼륨 노멀, 덤불 테두리: 위)을 그대로 조명에 사용
//    → 수백 장의 카드가 '덩어리 하나' 처럼 2~3톤으로 읽힌다 (t3ssel8r 방식).
//  - 알파 시저 텍스처. 텍스처 밝기(255/205/150)는 톤 변화·테두리용 승수.
//  - 그림자 수신은 끈다(카드끼리 자기 그림자가 점박이를 만듦). 구름 그림자는 월드 위치로 계산.
//  - 바람: 카드 중심(MODEL 원점 아님, 카드별 위상은 월드 위치로)에서 살짝 흔들림.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled, ambient_light_disabled, shadows_disabled;

#include "res://shaders/RED_bands.gdshaderinc"

uniform sampler2D card_tex : source_color, filter_nearest, repeat_disable;
uniform vec3 base_color : source_color = vec3(0.78, 0.86, 0.48);
uniform vec3 shadow_tint : source_color = vec3(0.20, 0.26, 0.29);
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.35;
uniform float sway_amount : hint_range(0.0, 0.3) = 0.04;
uniform float sway_speed : hint_range(0.0, 5.0) = 1.1;
// 카드 노멀을 위쪽으로 당겨 윗면이 더 넓게 밝아지게 (0 = 원본 노멀)
uniform float normal_up_bias : hint_range(0.0, 1.0) = 0.2;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = world_pos.x * 0.9 + world_pos.z * 0.7 + world_pos.y * 0.5;
	VERTEX.x += sin(TIME * sway_speed + phase) * sway_amount;
	VERTEX.z += cos(TIME * sway_speed * 0.8 + phase) * sway_amount * 0.6;
	NORMAL = normalize(NORMAL + vec3(0.0, normal_up_bias, 0.0));
}


void fragment() {
	vec4 t = texture(card_tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = base_color * t.rgb * paint_mottle(world_pos);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	// 양면: 뒷면이면 노멀 뒤집기
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	EMISSION = mix(ALBEDO * dark_factor, shadow_tint * dark_factor, shadow_tint_strength);
}


void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float strength = local_light_strength;
	float atten = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		strength = 1.0;
		atten = get_cloud_attenuation(world_pos, TIME);
	}
	DIFFUSE_LIGHT += (LIGHT_COLOR / PI) * band_above_dark(ndl * atten) * strength;
}
