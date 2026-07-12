shader_type canvas_item;

// Pénombre "blackout" du pong : ColorRect plein écran, trous de lumière
// circulaires autour des objets de jeu (balles, raquettes, powerups, portails,
// météore, drones). Positions/rayons en PIXELS ÉCRAN, poussés chaque frame par
// PongManager._update_blackout (padding hors écran au-delà de light_count).

uniform float darkness : hint_range(0.0, 1.0) = 0.85;
uniform vec2 viewport_size = vec2(1080.0, 1920.0);
uniform int light_count = 0;
uniform vec2 light_pos[16];
uniform float light_radius[16];

void fragment() {
	vec2 p = UV * viewport_size;
	float visibility = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= light_count) {
			break;
		}
		float r = max(1.0, light_radius[i]);
		float d = distance(p, light_pos[i]);
		visibility = max(visibility, 1.0 - smoothstep(r * 0.55, r, d));
	}
	COLOR = vec4(0.0, 0.0, 0.0, darkness * (1.0 - visibility));
}
