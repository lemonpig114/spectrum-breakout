shader_type canvas_item;
render_mode unshaded, blend_add;

// 局部能量薄雾：不采样屏幕，不扭曲 HUD；随池内爆点一起回收。
uniform vec4 tint : source_color = vec4(1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float effect_style = 0.0;
uniform float phase = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float t = progress;
	float expansion = 1.0 - pow(1.0 - t, 3.0);
	float radius = mix(0.12, 0.76, expansion);
	float soul = step(2.5, effect_style) * (1.0 - step(3.5, effect_style));
	float splash = step(1.5, effect_style) * (1.0 - step(2.5, effect_style));
	float shatter = step(4.5, effect_style);
	float filaments = sin(angle * 7.0 + r * 24.0 - t * 9.0 + phase)
		* sin(angle * 3.0 - r * 17.0 + t * 5.0);
	float band = exp(-pow((r - radius) / 0.065, 2.0));
	float mist = exp(-pow((r - radius * 0.85) / 0.20, 2.0));
	float structure = mix(0.55 + 0.45 * filaments, 0.45 + 0.55 * abs(sin(angle * 6.0 + r * 14.0 - t * 5.0)), soul);
	float core = exp(-r * r * 30.0) * pow(1.0 - t, 3.0);
	float fade = pow(1.0 - t, 1.7) * smoothstep(0.0, 0.045, t);
	float strength = (band * 0.24 + mist * structure * 0.22 + core * 0.7) * fade;
	strength *= mix(1.0, 0.55, shatter);
	strength *= mix(1.0, 0.60, splash) * mix(1.0, 0.85, soul);
	strength *= 1.0 - smoothstep(0.85, 1.0, r);
	COLOR = vec4(tint.rgb, strength * tint.a);
}
