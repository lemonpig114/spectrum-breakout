shader_type canvas_item;
render_mode unshaded;

uniform float phase = 0.0;
uniform float opacity = 1.0;
uniform float pulse = 0.0;
varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 p = local_position;
	float c = cos(-0.28), s = sin(-0.28);
	vec2 q = mat2(vec2(c, -s), vec2(s, c)) * p;
	q.y /= 0.62;
	float r = length(q);
	float a = atan(q.y, q.x);
	float band = exp(-pow((r - 0.56) / 0.14, 2.0));
	float flow = 0.5 + 0.5 * sin(5.0 * a + 8.0 * r - phase * 1.8);
	float threads = pow(flow, 5.0);
	float haze = exp(-r * r * 3.8) * (0.25 + 0.3 * flow);
	float core = smoothstep(0.20, 0.32, length(p));
	float rim = exp(-pow((length(p) - 0.245) / 0.018, 2.0));
	vec3 violet = mix(vec3(0.32, 0.12, 0.65), vec3(1.9, 1.1, 2.6), threads);
	vec3 rgb = violet * (band * (0.7 + threads) + haze * 0.4) * core;
	rgb += vec3(1.4, 0.75, 2.0) * rim * (0.5 + pulse);
	float alpha = clamp((band * 0.75 + haze) * core + rim * 0.6, 0.0, 0.94);
	alpha *= 1.0 - smoothstep(0.85, 1.0, length(p));
	// Circular gameplay boundary: 1.5 * body radius / 1.65 quad half-extent.
	// Keep it dim and thin so the central accretion disk remains the focal point.
	float outer = exp(-pow((length(p) - 0.90909) / 0.012, 2.0));
	float outer_haze = exp(-pow((length(p) - 0.895) / 0.035, 2.0));
	float outer_flow = 0.6 + 0.4 * sin(atan(p.y, p.x) * 7.0 - phase * 0.55);
	rgb += vec3(0.19, 0.09, 0.34) * outer * outer_flow + vec3(0.028, 0.012, 0.06) * outer_haze;
	alpha = max(alpha, outer * 0.52 + outer_haze * 0.08);
	COLOR = vec4(rgb, alpha * opacity);
}
