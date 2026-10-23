// RED_FlatLit — 조명 반응형 2D 색면 셰이더
//
// 원칙 (GDD §7):
//  - 외곽선 없음, 정반사 없음, 텍스처 없음. base_color 한 가지와 조명만으로 그림을 만든다.
//  - light()에서 직접광을 3단계(dark/mid/light) 밴드로 양자화하고 얇은 smoothstep 경계로 완화한다.
//  - DirectionalLight3D 그림자는 ATTENUATION을 통해 그대로 받는다 (그림자 = dark 밴드).
//  - 캐릭터·지면·벽·나무 전부 이 셰이더를 공유하며 머티리얼마다 base_color만 다르다.
//  - render_mode unshaded 금지. 실제 광원 방향/에너지 변화에 결과가 따라가야 한다.
// 추가 (3D pixel art 기사 §Lighting): 방향광 감쇠 스무딩, 구름 그림자 (RED_bands.gdshaderinc)
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled, ambient_light_disabled;

#include "res://shaders/RED_bands.gdshaderinc"

// 재질 시작값 (조명 전). GDD §2 팔레트에서 선택.
uniform vec3 base_color : source_color = vec3(0.6, 0.6, 0.6);

// 그림자/어두운 면을 물들이는 청회색. WorldEnvironment의 ambient 대신 셰이더가 직접 더한다.
uniform vec3 shadow_tint : source_color = vec3(0.20, 0.26, 0.29);
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.55;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	ALBEDO = base_color * paint_mottle(world_pos);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	// 주광이 전혀 닿지 않는 면도 완전한 검정이 되지 않도록, 색면용 기본 어둠을 한 번만 깔아 둔다.
	// (ambient_light_disabled 이므로 환경 ambient는 여기에 더해지지 않는다.)
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
	// ATTENUATION 에 방향광 그림자가 포함된다 → 그림자 속은 lit ≈ 0 → dark 밴드.
	float lit = ndl * atten;
	// LIGHT_COLOR 는 색 × 에너지 × PI 이므로 PI로 나눠 1.0 기준으로 되돌린다.
	// (Godot 4 는 light() 이후에 DIFFUSE_LIGHT 에 ALBEDO 를 곱하므로 여기서 곱하지 않는다)
	DIFFUSE_LIGHT += (LIGHT_COLOR / PI) * band_above_dark(lit) * strength;
}
