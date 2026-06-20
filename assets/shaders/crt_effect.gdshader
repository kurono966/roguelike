shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// CRT Effects
uniform float scanline_count : hint_range(0.0, 1080.0) = 400.0; // Finer scanlines
uniform float scanline_alpha : hint_range(0.0, 1.0) = 0.15; // Much lower alpha for subtelty
uniform float curvature : hint_range(0.0, 10.0) = 3.0; 
uniform float vignette : hint_range(0.0, 2.0) = 0.2; // Softer vignette

vec2 curve(vec2 uv) {
	// ... (unchanged)
	return uv;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// User requested straight screen (no curvature)
	vec2 r_uv = uv;
	vec2 g_uv = uv;
	vec2 b_uv = uv;
	
	// Boundary check
	// ...

	// Chromatic Aberration
	float aberration = 0.0005; // Very subtle aberration
	
	float r = texture(screen_texture, r_uv + vec2(aberration, 0.0)).r;
	float g = texture(screen_texture, g_uv).g;
	float b = texture(screen_texture, b_uv - vec2(aberration, 0.0)).b;
	
	vec3 color = vec3(r, g, b);
	
	// Scanlines
	// Sine wave based scanlines
	float scanline = sin(uv.y * scanline_count * 3.14159 * 2.0);
	color -= scanline * 0.05 * scanline_alpha; // Reduced intensity multiplier
	
	// Vignette
	float vig = (0.5 + 0.5*16.0*uv.x*uv.y*(1.0-uv.x)*(1.0-uv.y));
	// Clamp vignette to avoid too dark corners
	vig = clamp(pow(vig, vignette), 0.7, 1.0); 
	color *= vig;
	
	// Brightness boost to compensate for scanlines
	color *= 1.05;
	
	COLOR = vec4(color, 1.0);
}
