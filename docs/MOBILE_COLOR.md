# 手机与电脑配色排查（Godot 4.4.1）

## 已确认

- 项目桌面默认使用 Forward+，Android 默认使用 Mobile；`rendering/viewport/hdr_2d=true`，主场景启用 Glow。
- 旧蓝色 `Color(0.45, 0.85, 1.0)` 本身偏青，是代码配色问题；现统一为 `Color(0.24, 0.48, 1.0)`，局内 HDR 倍率为 `1.9`，并使选角、局内和选择器保持一致。
- 敌人本体和血条通过同一取色函数轻压非主色通道，绿色的蓝通道再略低一些；玩家、子弹的颜色不随此项改变。
- 原版灵魂法阵 `Color(1.4, 1.1, 2.6)` 在同一台电脑的 Forward+ 截图是亮紫，在 Mobile 渲染器截图呈灰粉。关闭 Glow 后差异仍在，因此仅调 Glow 不能解决主要色差。电脑端法阵和伤害数字已恢复原版配色。
- 两个自定义 CanvasItem 着色器的颜色 uniform 已有 `source_color` 标记；本项目没有发现漏标导致的直接证据。

## 对照包

- `build/spectrum-breakout-android-debug.apk`：正常 Mobile 渲染器。
- `build/spectrum-breakout-forwardplus-test.apk`：仅将 Android 渲染器临时改为 Forward+ 的对照包。项目配置已恢复，正式导出仍使用 Mobile。

两个包的 Android 包名相同，需要依次安装、分别截图；对照同一场景的蓝色、灵魂、金币和红色效果，再比较帧率与发热。调试包启动时日志会打印实际渲染器、驱动和 HDR 2D 状态。Forward+ 在手机上可能明显更耗电、掉帧，不能只按颜色决定是否采用。不同手机屏幕的显示模式也会造成剩余差异。

## 后续选择

若 Forward+ 包颜色明显接近电脑且性能可接受，再考虑切换 Android 默认渲染器。若性能不佳，保持 Mobile，并依据实机截图给 Mobile 单独做配色校准；优先修正使用高于 `1.0` 的 HDR 特效。无法仅靠同一个 RGB 值保证不同手机屏幕完全一致。

参考：[Godot 4.4 渲染器](https://docs.godotengine.org/en/4.4/tutorials/rendering/renderers.html)、[HDR 2D 与 Glow](https://docs.godotengine.org/en/4.4/tutorials/3d/environment_and_post_processing.html#using-glow-in-2d)、[Android Glow 差异讨论](https://github.com/godotengine/godot/issues/103512)。
