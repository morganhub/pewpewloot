shader_type spatial;

uniform sampler2D tex1;
uniform sampler2D tex2;
uniform sampler2D tex3;
uniform sampler2D tex4;
uniform sampler2D tex5;
uniform sampler2D tex6;
// Répétition verticale uniquement (de bas en haut) ; n'affecte pas le nombre de tranches (toujours 6).
uniform float uv_scale = 1.0;
uniform float uv_offset_u = 0.0;
uniform float uv_offset_v = 0.0;
// Tranche de bordure entre chaque niveau : largeur en part 0-1 de la largeur d'une tranche, couleur.
uniform float texture_border_width = 0.0;
uniform vec3 texture_border_color = vec3(0.1, 0.1, 0.18);

vec4 sample_sector(int sector, vec2 uv) {
	if (sector == 0) return texture(tex1, uv);
	if (sector == 1) return texture(tex2, uv);
	if (sector == 2) return texture(tex3, uv);
	if (sector == 3) return texture(tex4, uv);
	if (sector == 4) return texture(tex5, uv);
	return texture(tex6, uv);
}

void fragment() {
	// 6 tranches fixes : pas de scale sur X (un seul tour = 6 niveaux).
	float u = fract(UV.x + uv_offset_u);
	float v = UV.y + uv_offset_v;
	int sector = int(clamp(floor(u * 6.0), 0.0, 5.0));
	// Coordonnée horizontale dans la tranche (0..1).
	float sector_u = fract(u * 6.0);
	// Répétition verticale de bas en haut dans chaque tranche.
	float sector_v = fract(v * uv_scale);
	vec2 scaled_uv = vec2(sector_u, sector_v);

	vec4 color = sample_sector(sector, scaled_uv);

	// Bande de bordure entre les tranches (gauche et droite de chaque secteur).
	bool in_border = texture_border_width > 0.001 && (sector_u < texture_border_width || sector_u > 1.0 - texture_border_width);
	ALBEDO = in_border ? texture_border_color : color.rgb;
}
