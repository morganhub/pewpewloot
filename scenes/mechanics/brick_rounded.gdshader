shader_type canvas_item;

// Rounded-corner alpha mask for breakout bricks (SDF on the brick rect).
// One ShaderMaterial instance is shared by every brick of the wall (all
// bricks have the same size), so batching is preserved.
uniform vec2 rect_size = vec2(96.0, 40.0);
uniform float radius_px = 6.0;

void fragment() {
	vec2 p = UV * rect_size;
	vec2 half_size = rect_size * 0.5;
	vec2 b = half_size - vec2(radius_px);
	vec2 d = abs(p - half_size) - b;
	float dist = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius_px;
	COLOR.a *= 1.0 - smoothstep(-1.0, 1.0, dist);
}
