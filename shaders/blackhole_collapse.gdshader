shader_type canvas_item;
render_mode unshaded;

uniform float progress = 0.0;
varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = local_position;
	float t = clamp(progress, 0.0, 1.0);
	float r = length(p);
	float a = atan(p.y, p.x);
	float fade = pow(1.0 - t, 1.5);
	float front = 0.82 * (1.0 - pow(1.0 - t, 3.0));
	float ripple = sin(a * 9.0 + t * 4.0) * 0.012 + sin(a * 17.0 - t * 7.0) * 0.009;
	float twisted = sin(a * 6.0 - r * 19.0 + t * 8.0) * 0.5 + 0.5;
	float edge = exp(-pow((r - front - ripple) / 0.025, 2.0));
	float smoke = exp(-pow((r - front * 0.78) / 0.15, 2.0)) * (0.25 + 0.75 * twisted);
	float haze = exp(-pow((r - front) / 0.09, 2.0));
	float sector = floor((a + 3.14159) * 5.0);
	float rays = pow(max(0.0, sin(a * 31.0 + hash(sector) * 5.0 + r * 8.0)), 16.0);
	rays *= exp(-pow((r - front * 0.95) / 0.15, 2.0));
	float core = 0.28 * pow(1.0 - t, 2.0);
	float core_rim = exp(-pow((r - core) / 0.012, 2.0));
	float void_mask = (1.0 - smoothstep(front * 0.72, front + 0.02, r)) * fade;
	vec3 rgb = vec3(0.012, 0.005, 0.025) * smoke;
	rgb += vec3(0.45, 0.24, 1.0) * (haze * 0.28 + smoke * 0.32);
	rgb += mix(vec3(0.5, 0.3, 1.3), vec3(2.2, 1.8, 2.8), pow(twisted, 3.0)) * edge;
	rgb += vec3(1.2, 0.7, 2.4) * rays * 0.6;
	rgb += vec3(1.5, 1.1, 2.1) * core_rim * pow(1.0 - t, 3.0);
	float alpha = max(void_mask * 0.92, clamp(haze * 0.35 + smoke * 0.6 + edge + rays + core_rim, 0.0, 1.0) * fade);
	COLOR = vec4(rgb * fade, alpha);
}
