// RED_FlatLitTex — RED_FlatLit 의 텍스처 버전 (플레이어 캐릭터 베이스컬러용)
// 조명/밴드/구름/얼룩은 FlatLit 과 동일. 알베도만 텍스처 × tint.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled, ambient_light_disabled;

#include "res://shaders/RED_bands.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
// 텍스처 채도 조절 (0 = 흑백, 1 = 원본). 회화풍 팔레트에 맞춰 낮출 수 있음
uniform float saturation : hint_range(0.0, 1.5) = 0.9;
uniform vec3 shadow_tint : source_color = vec3(0.15, 0.19, 0.30);
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.7;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	ALBEDO = c * tint * paint_mottle(world_pos);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = mix(ALBEDO * dark_factor, shadow_tint * dark_factor, shadow_tint_strength);
}


void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float strength = local_light_strength;
	float atten = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		strength = 1.0;
		atten = smooth_shadow(ATTENUATION) * get_cloud_attenuation(world_pos, TIME);
	}
	DIFFUSE_LIGHT += (LIGHT_COLOR / PI) * band_above_dark(ndl * atten) * strength;
}
