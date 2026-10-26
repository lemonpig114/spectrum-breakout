shader_type canvas_item;
render_mode unshaded;

uniform vec2 rect_size = vec2(2400.0, 1800.0);
uniform float shader_time = 0.0;
uniform float wall_visibility = 0.0;

uniform vec4 ripple0 = vec4(0.0);
uniform vec4 ripple1 = vec4(0.0);
uniform vec4 ripple2 = vec4(0.0);
uniform vec4 ripple3 = vec4(0.0);

uniform vec4 background_color : source_color = vec4(0.008, 0.01, 0.018, 1.0);
uniform vec4 minor_color : source_color = vec4(0.06, 0.085, 0.13, 1.0);
uniform vec4 major_color : source_color = vec4(0.12, 0.18, 0.28, 1.0);
uniform float minor_spacing = 16.0;
uniform float major_spacing = 64.0;
uniform float line_width = 1.0;

vec2 ripple_offset(vec2 p, vec4 r) {
	if (r.w <= 0.0) {
		return vec2(0.0);
	}

	float age = shader_time - r.z;
	float life = 0.9;
	if (age < 0.0 || age > life) {
		return vec2(0.0);
	}

	vec2 delta = p - r.xy;
	float dist = length(delta) + 0.001;
	float radius = age * 850.0;
	float band = exp(-pow((dist - radius) / 55.0, 2.0));
	float fade = 1.0 - age / life;
	return (delta / dist) * band * fade * r.w * 22.0;
}

float grid_line(vec2 p, float spacing, float width) {
	vec2 cell = abs(fract(p / spacing + 0.5) - 0.5) * spacing;
	float d = min(cell.x, cell.y);
	return 1.0 - smoothstep(0.0, width, d);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 offset = ripple_offset(p, ripple0)
		+ ripple_offset(p, ripple1)
		+ ripple_offset(p, ripple2)
		+ ripple_offset(p, ripple3);

	vec2 q = p + offset;
	float minor = grid_line(q, minor_spacing, line_width * 0.8);
	float major = grid_line(q, major_spacing, line_width * 1.4);

	vec3 col = background_color.rgb;
	col = mix(col, minor_color.rgb, minor * 0.7);
	col = mix(col, major_color.rgb, major * 0.95);
	float edge = min(min(p.x, p.y), min(rect_size.x - p.x, rect_size.y - p.y));
	float wall = (1.0 - smoothstep(0.0, 115.0, edge)) * wall_visibility;
	float flow = 0.72 + 0.28 * sin(shader_time * 4.0 + p.x * 0.025 + p.y * 0.035);
	col += vec3(0.10, 0.24, 0.36) * wall * flow;

	COLOR = vec4(col, 1.0);
}
