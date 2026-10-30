# 音效系统与素材

> 当前 24 个音效。多数来自 Kenney 的 CC0 素材；`hit` / `weak_hit` / `crit` / `soul` /
> `level_up` / `super_crit` / `chest` 使用项目生成的 WAV，和代码里的合成兜底保持一致。
> 代码层仍保留运行时合成兜底：删掉同名外部文件即可回到内置合成音。

## 1. 运行时

`Audio` 自动加载（`scripts/autoload/Audio.gd`）在启动时做三件事：

1. 为 `SOUND_DEFS` 里的每个 id 查找 `assets/audio/sfx/<id>.wav`，其次是 `.ogg`；找不到就调用 `_synth()` 现场合成一段 PCM16 / 22050 Hz / 单声道 WAV。同名时 WAV 优先，便于用生成音覆盖旧素材而不删文件。
2. 预建 **20 个固定 `AudioStreamPlayer` 声部**，播放时轮询空闲声部；全忙时抢占下一个，声部数永远恒定。
3. 从 `user://audio.cfg` 读取主音量与静音状态，写回同一文件。

播放接口：

```gdscript
Audio.play(&"hit")                       # 返回 false 表示静音、id 不存在或仍在冷却
Audio.play(&"gold", -2.0, 1.05)          # 额外音量(dB)、音高倍率
Audio.set_muted(true)                    # 同时写配置
Audio.toggle_muted()
Audio.set_volume(0.6)                    # 0..1，映射到 Master 总线
```

`SOUND_DEFS` 中每个音效有：

- `cooldown`：毫秒级节流，抑制霰弹/连射/成群击杀造成的同帧叠音。
- `jitter`：随机音高抖动比例，避免重复音机械。
- `db`：相对音量偏移，用来压住高频的命中/拾取音。

暂停面板里按 `M` 可切换静音；右侧的“设置”页可调主音量（`− / +`，方向键也可）与静音切换。设置会持久化到 `user://audio.cfg`。`Audio` 的 `process_mode = ALWAYS`，所以暂停时 UI 音仍可播放。

性能约定：命中/拾取只在池化声部上换 `stream`，不创建节点或 Tween；冷启动第一次播放某个 OGG 时约 1.4 ms，之后同 id 的节流检查约 0.01 ms。不要在每个命中里 `load()` 音频。

> `--headless` 下跑 `audio_test` 时，退出阶段可能打印 `ObjectDB instances leaked` / `resources still in use`。这是 dummy 音频驱动没有及时回收 OGG 播放对象导致的无害提示，测试退出码仍为 0；`Audio.shutdown()` 已会停止声部并解除流引用。真实设备下若仍出现，再排查播放对象回收。

## 2. 音效表

| id | 触发点 | 素材（Kenney） | 时长 |
| --- | --- | --- | --- |
| `shoot` | 每次普通开火（多弹丸只响一次） | Sci-Fi / `laserSmall_000` | 0.239 s |
| `shoot_heavy` | 重型处刑弹开火 | Sci-Fi / `laserLarge_000` | 0.677 s |
| `hit` | 普通命中 | 生成 WAV：185→92 Hz 方波 + 低通 | 0.075 s |
| `hit_heavy` | 重型弹命中 | Impact / `impactPunch_medium_000` | 0.431 s |
| `weak_hit` | 颜色克制命中 | 生成 WAV：196→294 Hz 双音方波 | 0.063 s |
| `crit` | 暴击 | 生成 WAV：262→392→523 Hz 三音方波 | 0.082 s |
| `super_crit` | 超级暴击 | 生成 WAV：140→58 Hz 冲击 + 1.8/2.6 kHz 闪光 + 噪声起音 | 0.240 s |
| `kill` | 敌人死亡 | Impact / `impactSoft_medium_001` | 0.183 s |
| `soul` | 灵魂震荡每次脉冲 | 生成 WAV：82 Hz 双失谐低音 + 4 Hz 颤音 | 0.620 s |
| `gold` | 金币抵达玩家 | RPG / `handleCoins2` | 0.338 s |
| `xp` | 经验抵达玩家 | Interface / `pluck_002` | 0.165 s |
| `chest` | 开宝箱（由 `Skills.open_chest()` 触发） | 生成 WAV：C5→E5→G5→C6 柔和钟音 + 130 Hz 托底 | 0.520 s |
| `heal` | 治疗/回复类遗物 | Digital / `phaserUp1` | 0.496 s |
| `hurt` | 玩家受伤 | Impact / `impactPunch_heavy_002` | 0.457 s |
| `dodge` | 闪避成功 | Digital / `phaseJump2` | 0.392 s |
| `level_up` | 升级 | 生成 WAV：C5→E5→G5→C6 上行四音 | 0.225 s |
| `color_switch` | 确认切色（开局那次不响） | Digital / `phaserUp4` | 0.366 s |
| `merchant` | 商人出现 | Digital / `threeTone2` | 0.866 s |
| `shop_open` | 靠近商人打开商店 | Interface / `open_002` | 0.314 s |
| `altar_spawn` | 祭坛出现 | Sci-Fi / `forceField_000` | 0.954 s |
| `altar_trade` | 祭坛交易完成 | Digital / `lowDown` | 0.784 s |
| `ui_click` | 普通 UI 点击/离开/选择 | UI / `click1` | 0.094 s |
| `ui_buy` | 购买/捐款/重掷成功 | Interface / `confirmation_001` | 0.290 s |
| `game_over` | 玩家死亡 | Digital / `lowThreeTone` | 1.019 s |

### 低频 8-bit 命中音

普通命中不再使用清脆的撞击采样：`hit.wav` 是 185→92 Hz 的低频方波，配一节 1.5 kHz 低通，
时长 75 ms；`weak_hit.wav` 与 `crit.wav` 用同一种方波音色做 2～3 个低音级进，
保持“8-bit、短、闷”的家族感。音频层仍按 `Audio` 的 `cooldown` 合并同帧多弹丸。
`hit.wav` 峰值归一化到约 0.92，因此 `SOUND_DEFS.hit.db = -8.0` 压低了 3 dB。

### 灵魂嗡鸣

`soul` 由灵魂震荡每次脉冲触发（`SkillSystem._do_soul_pulse()`），冷却 400 ms。
`82.41 Hz` 的两个略微失谐低音产生缓慢拍频，再叠 4 Hz 颤音、慢起慢收和 1.2 kHz 低通，
听感是持续的低声嗡鸣，而不是打击音。`_synth()` 里有等价的 `_hum()` 兜底。

### 升级音：短促上行

`level_up.wav` 是 C5 → E5 → G5 → C6 的四音上行，每音 55 ms、间隔 40 ms，总长 225 ms；
最后一音带 6% 的上滑，明确收在“升级完成”的方向，不再使用原先那段从高到低的下行采样。
方波与正弦各占一半，既有 8-bit 的颗粒感，又不至于像命中音那样刺耳。`_synth()` 用同样的
`_sequence([523.25, 659.25, 783.99, 1046.5], 0.040, 0.055, ...)` 兜底。

### 超暴击：低频 + 高频双层

`super_crit.wav` 在同一个起音上叠三层：140→58 Hz 的低频冲击提供“重”，1.8 kHz / 2.6 kHz
的高频方波闪光提供“亮”，前 22 ms 的噪声裂口提供“脆”。总长 240 ms，峰值归一化到 0.92。
`_synth()` 里的 `_impact_shine()` 是等价兜底。

### 开箱音：柔和上行钟音

`chest.wav` 用 C5 → E5 → G5 → C6 四颗钟音依次展开（每颗 320 ms 指数衰减），下面垫一层
130.81 Hz 的短促暖音，尾部加一点很轻的 2093 Hz 闪光。总长 520 ms，替换原先 1.2 s 的
Digital `powerUp1` 长上扬采样。`_synth()` 用同音高的 `_sequence()` 兜底。

低频全局事件由 `EventBus` 统一接到 `Audio`：`player_damaged`、`player_dodged`、`player_died`、`level_up`、`color_changed`、`merchant_spawned`、`merchant_reached`、`altar_spawned`。命中、开火、拾取、UI 点击等高频事件由各自的调用点直接 `Audio.play()`。

## 3. 替换与新增

### 替换一个音效

把文件命名为 `<id>.ogg` 或 `<id>.wav`，放进 `assets/audio/sfx/`，然后刷新导入：

```bash
"$GODOT" --headless --editor --quit --path "C:/Users/11257/Documents/光谱突围"
```

同名 `.wav` 优先于 `.ogg`。不需要改代码，也不需要删除内置合成分支。建议：

- 短音效 ≤ 0.4 s，避免在 20 个声部里长时间占位。
- 命中/拾取类素材峰值不要高于 `crit`/`level_up`，否则会把稀有反馈淹没。
- 先按表里的 `db` 偏置试听；如果素材本身偏亮，再在 `SOUND_DEFS` 里调 `db`。

### 新增一个 id

1. 在 `SOUND_DEFS` 增加条目（`cooldown`、`jitter`、`db`）。
2. 在 `_synth()` 的 `match` 里加一个兜底音色（没有外部素材时也能响）。
3. 在调用点触发 `Audio.play(&"新id")`。
4. 放素材或直接依赖合成，再跑 `tests/audio_test.tscn`。

## 4. 素材来源与授权

除项目自行生成的 `hit` / `weak_hit` / `crit` / `soul` / `level_up` / `super_crit` / `chest` 外，其余素材来自 **Kenney**
（Kenney Vleugels，<https://kenney.nl>），授权为 **CC0 1.0**：

- Impact Sounds（130 个）：<https://kenney.nl/assets/impact-sounds>
- Interface Sounds（100 个）：<https://kenney.nl/assets/interface-sounds>
- Sci-Fi Sounds（70 个）：<https://kenney.nl/assets/sci-fi-sounds>
- Digital Audio（60 个）：<https://kenney.nl/assets/digital-audio>
- RPG Audio（50 个）：<https://kenney.nl/assets/rpg-audio>
- UI Audio（50 个）：<https://kenney.nl/assets/ui-audio>

CC0 允许个人、教育和商业使用，署名非强制。项目仍保留 `assets/audio/sfx/LICENSE_kenney_CC0.txt`，并建议在发布页写一句“Sound effects: Kenney (CC0)”。

Kenney 素材只挑选了 20 个 OGG（约 260 KB），加上 7 个生成 WAV（约 55 KB），共 24 个音效；
其中 `level_up.ogg` / `super_crit.ogg` / `chest.ogg` 已被同名生成 WAV 覆盖，旧文件仍保留在目录里以便回退。
没有把整包 400+ 个素材放进仓库。需要更多变体时按同一命名约定替换即可。

## 5. 其他可用的 CC0 来源

- **OpenGameArt — 512 Sound Effects (8-bit style)**，作者 SubspaceAudio，CC0：<https://opengameart.org/content/512-sound-effects-8-bit-style>
- **jsfxr**（在线 8-bit 音效生成器）：<https://sfxr.me/>
- **ChipTone**：<https://sfbgames.itch.io/chiptone>
- **Bfxr**：<https://www.bfxr.net/>
- **Freesound**：<https://freesound.org/> — 逐个文件确认授权，筛选 CC0；不要默认整站可商用。

生成器适合做更“电子/霓虹”的射击与切色音；Kenney 的撞击/硬币素材更适合命中、金币和开箱。

## 武器音效更新（2026-10-29）

新增 20 个内置合成音：basic/sword/scythe/wave/boomerang/sprite/star/lightning/cannon/black_hole 各有 weapon_<id> 发射或挥动音及 weapon_hit_<id> 命中音。保留外部同名 wav/ogg 优先约定。剑和镰刀使用不同长度的气流噪声。2026-10-30 根据用户反馈，基础弹已恢复旧 shoot/shoot_heavy 与 hit/weak_hit/crit/super_crit/hit_heavy；weapon_basic/weapon_hit_basic 仍保留在音库，但基础弹不再调用。新武器合成音暂作占位，待用户逐项选材。全音库共 44 项，仍由 20 个池化声部播放。

黑洞从武器移出后，weapon_black_hole / weapon_hit_black_hole 音频ID保留，改由独立黑洞技能的生成与结束爆炸使用。
