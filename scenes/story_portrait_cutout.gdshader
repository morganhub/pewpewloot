shader_type canvas_item;

// Rend le noir / zones sombres transparents (pour JPG de personnages sur fond noir).
uniform float cutoff : hint_range(0.0, 1.0) = 0.15;
uniform float softness : hint_range(0.001, 1.0) = 0.08;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float a = smoothstep(cutoff - softness, cutoff + softness, l);
	COLOR = vec4(c.rgb, c.a * a * opacity);
}
