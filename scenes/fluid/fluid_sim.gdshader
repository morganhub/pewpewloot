shader_type canvas_item;

// Simulation de fluide 2D Eulerienne — Advection + Diffusion + Curl Noise + Decay
// Ping-pong : ce shader lit la frame précédente (previous_frame) et écrit le résultat.
// Les emitters frais sont lus depuis un viewport séparé (emitter_texture).

uniform sampler2D previous_frame : hint_default_transparent, filter_linear;
uniform sampler2D emitter_texture : hint_default_transparent, filter_linear;
uniform float delta_time : hint_range(0.0, 0.1) = 0.016;
uniform float diffusion_rate : hint_range(0.0, 0.2) = 0.02;
uniform float decay_rate : hint_range(0.8, 1.0) = 0.97;
uniform float curl_strength : hint_range(0.0, 5.0) = 1.5;
uniform float global_time = 0.0;

// ---------- Simplex-like noise (procédural, sans texture) ----------

vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289_2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289((x * 34.0 + 1.0) * x); }

float snoise(vec2 v) {
	const vec4 C = vec4(0.211324865405187, 0.366025403784439,
						-0.577350269189626, 0.024390243902439);
	vec2 i = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;
	i = mod289_2(i);
	vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;
	vec3 x_vec = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x_vec) - 0.5;
	vec3 ox = floor(x_vec + 0.5);
	vec3 a0 = x_vec - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}

// Curl noise 2D : renvoie un vecteur perpendiculaire au gradient du bruit
vec2 curl_noise(vec2 uv, float t) {
	float eps = 0.001;
	float n1 = snoise(uv + vec2(eps, 0.0) + vec2(t * 0.3, t * 0.2));
	float n2 = snoise(uv - vec2(eps, 0.0) + vec2(t * 0.3, t * 0.2));
	float n3 = snoise(uv + vec2(0.0, eps) + vec2(t * 0.3, t * 0.2));
	float n4 = snoise(uv - vec2(0.0, eps) + vec2(t * 0.3, t * 0.2));
	float dndx = (n1 - n2) / (2.0 * eps);
	float dndy = (n3 - n4) / (2.0 * eps);
	// Curl = (-dndy, dndx) — perpendiculaire au gradient
	return vec2(-dndy, dndx);
}

void fragment() {
	vec2 uv = UV;
	vec2 pixel_size = TEXTURE_PIXEL_SIZE;

	// 1. Curl noise advection — déplacer l'UV de lecture
	vec2 curl = curl_noise(uv * 4.0, global_time) * curl_strength * pixel_size.x;
	vec2 advected_uv = uv + curl;

	// 2. Lire la frame précédente à la position advectée
	vec4 prev = texture(previous_frame, advected_uv);

	// 3. Diffusion (Jacobi simplifié : moyenne des 4 voisins)
	vec4 left  = texture(previous_frame, advected_uv + vec2(-pixel_size.x, 0.0));
	vec4 right = texture(previous_frame, advected_uv + vec2( pixel_size.x, 0.0));
	vec4 up    = texture(previous_frame, advected_uv + vec2(0.0, -pixel_size.y));
	vec4 down  = texture(previous_frame, advected_uv + vec2(0.0,  pixel_size.y));
	vec4 diffused = mix(prev, (left + right + up + down) * 0.25, diffusion_rate);

	// 4. Decay — le fluide s'estompe progressivement
	diffused.rgb *= decay_rate;
	diffused.a *= decay_rate;

	// 5. Lire les emitters frais (dessinés dans le viewport AVANT ce sprite, via screen_texture)
	vec4 emitter = texture(emitter_texture, uv);

	// 6. Combiner : emitters frais + fluide décayé
	vec4 result = diffused;
	result.rgb = result.rgb + emitter.rgb * emitter.a * (vec3(1.0) - result.rgb);
	result.a = clamp(result.a + emitter.a * (1.0 - result.a), 0.0, 1.0);

	// Clamp de sécurité
	result = clamp(result, vec4(0.0), vec4(1.0));

	COLOR = result;
}
