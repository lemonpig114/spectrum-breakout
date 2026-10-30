# 光谱突围

Godot 4.4.1 制作的霓虹几何幸存者游戏，目前处于开发测试阶段。

## 下载 v0.2.0 测试版

[打开 GitHub 下载页面](https://github.com/lemonpig114/spectrum-breakout/releases/tag/v0.2.0)

- Windows 64位：下载 `spectrum-breakout-v0.2.0-windows-x64.zip`，完整解压，打开 `光谱突围.exe`。同名 `.pck` 必须保留在程序旁边。
- Android ARM64：下载 `spectrum-breakout-v0.2.0-android-arm64.apk` 并安装。此包使用现有调试签名，供实机测试；不是应用商店发行包。
- Windows使用Forward+，Android使用Mobile/Vulkan，需支持相应图形接口。安卓真实设备兼容性与流畅度仍需实机验收。

## 操作

电脑：WASD/方向键移动，左键瞄准，右键切换颜色，Esc暂停。调试包可按 `~` 使用控制台，`help`查看命令，Tab补全。

手机：左侧触点生成摇杆，操作期间基座默认不移动；战斗区点击切色，长按/滑动选择颜色。世界画面比桌面放大30%，UI保持原尺寸。

## 开发与记录

在Godot 4.4.1中导入 `project.godot`。[本版更新](docs/RELEASES.md)、[刷怪流程](刷怪浓度.md)、[遗物设计表](遗物设计表.md)、[技能设计表](技能设计表.md)、[安卓说明](docs/MOBILE.md)。

本地签名、导出配置与构建产物不提交源码；安装包通过GitHub Releases分发。
