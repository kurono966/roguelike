shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float blur_radius = 0.9;
uniform float blur_strength = 0.85;

void fragment() {
	vec2 step_uv = SCREEN_PIXEL_SIZE * blur_radius;
	vec3 center = texture(screen_texture, SCREEN_UV).rgb;
	vec3 softened = center * 0.25;
	softened += texture(screen_texture, SCREEN_UV + vec2(step_uv.x, 0.0)).rgb * 0.125;
	softened += texture(screen_texture, SCREEN_UV - vec2(step_uv.x, 0.0)).rgb * 0.125;
	softened += texture(screen_texture, SCREEN_UV + vec2(0.0, step_uv.y)).rgb * 0.125;
	softened += texture(screen_texture, SCREEN_UV - vec2(0.0, step_uv.y)).rgb * 0.125;
	softened += texture(screen_texture, SCREEN_UV + step_uv).rgb * 0.0625;
	softened += texture(screen_texture, SCREEN_UV - step_uv).rgb * 0.0625;
	softened += texture(screen_texture, SCREEN_UV + vec2(step_uv.x, -step_uv.y)).rgb * 0.0625;
	softened += texture(screen_texture, SCREEN_UV + vec2(-step_uv.x, step_uv.y)).rgb * 0.0625;
	COLOR = vec4(mix(center, softened, blur_strength), 1.0);
}
