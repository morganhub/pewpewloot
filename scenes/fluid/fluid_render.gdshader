shader_type canvas_item;
render_mode blend_add;

// Rendu final du fluide — colorisation, fake bloom, blend additif

uniform sampler2D fluid_texture : hint_default_transparent, filter_linear;
uniform float bloom_strength : hint_range(0.0, 2.0) = 0.4;
uniform float brightness : hint_range(0.5, 3.0) = 1.3;
uniform float alpha_boost : hint_range(1.0, 5.0) = 1.5;

void fragment() {
	vec2 uv = UV;
	vec2 px = TEXTURE_PIXEL_SIZE;

	// 1. Lire le fluide simulé
	vec4 fluid = texture(fluid_texture, uv);

	// 2. Fake bloom — gaussian 3×3 sur la texture de fluide
	vec4 bloom = vec4(0.0);
	float total_weight = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			float w = 1.0 / (1.0 + float(abs(x) + abs(y)));
			bloom += texture(fluid_texture, uv + vec2(float(x), float(y)) * px * 2.0) * w;
			total_weight += w;
		}
	}
	bloom /= total_weight;

	// 3. Combiner fluide net + bloom
	vec4 result = fluid * brightness + bloom * bloom_strength;

	// 4. Booster l'alpha pour la visibilité (le fluide basse résolution peut être très subtil)
	result.a = clamp(result.a * alpha_boost, 0.0, 1.0);

	// 5. Sortie — blend additif géré par render_mode blend_add
	COLOR = result;
}
