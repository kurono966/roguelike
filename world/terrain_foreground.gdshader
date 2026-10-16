shader_type canvas_item;

varying vec4 tile_tint;

void vertex() {
	tile_tint = COLOR;
}

void fragment() {
	vec4 tile = texture(TEXTURE, UV);
	// Keep terrain markings sharp, while the dark backing leaves the height
	// shading and slope gradient visible underneath.
	float brightness = max(tile.r, max(tile.g, tile.b));
	float marking = smoothstep(0.12, 0.28, brightness);
	COLOR = vec4(tile.rgb * tile_tint.rgb, tile.a * marking * tile_tint.a);
}
