shader_type canvas_item;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(1.0);
uniform float progress = 0.0;
uniform float radius = 30.0;

vec2 turn(vec2 p, float a) {
	return mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * p;
}

float spike(vec2 p, float reach, float width, float base, float aa) {
	p = abs(p);
	float horizontal = (1.0 - smoothstep(width * (reach - p.x) / max(reach - base, 0.001), width * (reach - p.x) / max(reach - base, 0.001) + aa, p.y));
	horizontal *= smoothstep(base - aa, base, p.x) * (1.0 - smoothstep(reach, reach + aa, p.x));
	float vertical = (1.0 - smoothstep(width * (reach - p.y) / max(reach - base, 0.001), width * (reach - p.y) / max(reach - base, 0.001) + aa, p.x));
	vertical *= smoothstep(base - aa, base, p.y) * (1.0 - smoothstep(reach, reach + aa, p.y));
	return max(horizontal, vertical);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.6 * radius;
	float ease = 1.0 - pow(1.0 - progress, 3.0);
	float reach = radius * mix(0.35, 1.0, ease);
	float aa = max(0.6, fwidth(p.x));
	float primary = spike(turn(p, -0.22 - progress * 0.5), reach, reach * 0.15 * (1.0 - progress * 0.55), reach * 0.12, aa) * 0.42;
	float diagonal = spike(turn(p, -0.785398 - progress * 0.5), reach * 0.58, reach * 0.07 * (1.0 - progress * 0.5), 0.0, aa) * 0.28;
	vec2 box = abs(turn(p, -progress * 0.75));
	float edge = abs(max(box.x, box.y) - reach * 0.66468);
	float outline = (1.0 - smoothstep(0.8, 0.8 + aa, edge)) * 0.78;
	float core = (1.0 - smoothstep(radius * 0.14 * (1.0 - ease), radius * 0.14 * (1.0 - ease) + aa, length(p))) * 0.85;
	float alpha = max(max(primary, diagonal), max(outline, core)) * (1.0 - progress) * tint.a;
	vec3 color = mix(tint.rgb, vec3(1.0), core);
	COLOR = vec4(color, alpha);
}
