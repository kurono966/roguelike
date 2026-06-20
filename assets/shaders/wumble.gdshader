shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Settings for a subtle, heavy-liquid style movement
uniform float speed : hint_range(0.0, 5.0) = 1.0;
uniform float frequency : hint_range(0.0, 10.0) = 2.0;
uniform float strength : hint_range(0.0, 0.05) = 0.005;

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// Create a gentle, large wave movement
	// Lower frequency means larger waves (not stripy)
	float offset_x = sin(uv.y * frequency + TIME * speed) * strength;
	float offset_y = cos(uv.x * frequency + TIME * speed * 0.8) * strength;
	
	uv.x += offset_x;
	uv.y += offset_y;
	
	vec4 color = texture(screen_texture, uv);
	
	// Optional: Very slight purple/blue tint drift for atmosphere
	float hue_drift = sin(TIME * 0.2) * 0.05;
	color.r += hue_drift;
	color.b -= hue_drift;
	
	COLOR = color;
}
