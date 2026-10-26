shader_type canvas_item;

// 超级暴击数字的琉璃渐变（单 Label 完成全部效果）。
//
// 之前把“黑描边 / 冷色散 / 暖色散 / 白高光 / 渐变色身”拆成五个错位 Label，
// 半透明层叠在一起会把主体洗白，且绘制层级不稳定。现在只用一个 Label：
// - 黑色外描边交给 Label 自带的 outline（shader 识别黑色字体色后原样输出）；
// - 色身颜色按字形在 Layout 内的局部坐标连续取色，字符内部和字符之间都连续；
// - 白色镜面边和冷/暖色散在 shader 里对字体图集做邻域采样得到。
//
// 亮度刻意压在 HDR 泛光阈值附近，避免 Glow 把字洗成纯白。

// 冰蓝、紫罗兰、樱粉、香槟金、薄荷、蓝紫。
const vec3 C0 = vec3(0.05, 0.95, 2.20);
const vec3 C1 = vec3(1.20, 0.08, 2.05);
const vec3 C2 = vec3(2.15, 0.12, 0.90);
const vec3 C3 = vec3(2.15, 0.80, 0.03);
const vec3 C4 = vec3(0.05, 2.00, 0.40);
const vec3 C5 = vec3(0.35, 0.50, 2.25);

// 数字整体的宽高，用来把局部坐标归一化到 0..1。
uniform vec2 text_size = vec2(80.0, 48.0);
// 每个数字的起始相位，避免同屏多个数字完全同色。
uniform float phase = 0.0;
// 色带沿字符串流动的速度。
uniform float flow_speed = 0.30;
// 白色镜面边与色散边的强度，留出调试余量。
uniform float rim_strength = 0.5;
uniform float fringe_strength = 0.55;

vec3 palette(float t) {
	t = fract(t) * 6.0;
	float i = floor(t);
	float f = smoothstep(0.0, 1.0, fract(t));
	if (i < 0.5) {
		return mix(C0, C1, f);
	} else if (i < 1.5) {
		return mix(C1, C2, f);
	} else if (i < 2.5) {
		return mix(C2, C3, f);
	} else if (i < 3.5) {
		return mix(C3, C4, f);
	} else if (i < 4.5) {
		return mix(C4, C5, f);
	}
	return mix(C5, C0, f);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Label 的描边层用黑色字体颜色绘制；保持纯黑，避免渐变染到描边上。
	float tint = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	if (tint < 0.02) {
		COLOR.rgb = vec3(0.0);
		COLOR.a = tex.a * COLOR.a;
	} else {
		// 字符串局部坐标：横向为主、纵向为辅，字符内部也有斜向色相变化。
		vec2 p = VERTEX / max(text_size, vec2(1.0));
		float t = p.x * 0.62 + p.y * 0.22 + phase + TIME * flow_speed;
		vec3 col = palette(t);

		// 明暗流动，让同一字符内部不是一整块亮度。
		float shade = 0.86 + 0.14 * sin((p.x * 2.6 - p.y * 4.4) * 3.14159 - TIME * 1.3);
		col *= shade;

		// 左上镜面边：当前像素有覆盖、左上邻域没有覆盖的地方提亮。
		vec2 texel = TEXTURE_PIXEL_SIZE;
		float rim = clamp(tex.a - texture(TEXTURE, UV - texel * 1.8).a, 0.0, 1.0);
		col += vec3(1.7) * rim * rim_strength;

		// 斜向流动的镜面带：像光扫过琉璃表面，只在很窄的一条上提亮。
		float sheen = pow(clamp(0.5 + 0.5 * sin((p.x * 3.4 + p.y * 2.6) * 3.14159 - TIME * 2.0), 0.0, 1.0), 14.0);
		col += vec3(1.5) * sheen * 0.22;

		// 冷/暖色散边：对图集做轻微左右偏移采样，只在字形边缘露出。
		float left_a = texture(TEXTURE, UV - vec2(texel.x * 2.2, 0.0)).a;
		float right_a = texture(TEXTURE, UV + vec2(texel.x * 2.2, 0.0)).a;
		col += vec3(0.25, 0.45, 1.25) * clamp(left_a - tex.a, 0.0, 1.0) * fringe_strength;
		col += vec3(1.25, 0.25, 0.85) * clamp(right_a - tex.a, 0.0, 1.0) * fringe_strength;

		COLOR.rgb = clamp(col, vec3(0.0), vec3(3.0));
		COLOR.a = tex.a * COLOR.a;
	}
}
