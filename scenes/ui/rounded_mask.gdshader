shader_type canvas_item;

// Rounded-corner alpha mask for menu tiles/cards (SDF on the control rect).
// Works in LOCAL PIXEL coordinates (varying from VERTEX), so it stays correct
// whatever the texture stretch mode (KEEP_ASPECT_COVERED crops UVs, which
// breaks UV-based masks like brick_rounded.gdshader).
uniform vec2 rect_size = vec2(340.0, 150.0);
uniform float radius_px = 12.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 b = half_size - vec2(radius_px);
	vec2 d = abs(local_pos - half_size) - b;
	float dist = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius_px;
	COLOR.a *= 1.0 - smoothstep(-1.0, 1.0, dist);
}
