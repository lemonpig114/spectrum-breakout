# 交接记录 — 2026-10-22（第八轮）

> 只记录状态、结论和下一步，不包含完整代码。项目不是 git 仓库，改动前先读本文件。
> 设计看 `plan.md` §1–15；第一至七轮实现细节看 `docs/HISTORY.md`；音效看 `docs/AUDIO.md`。

## 0. 一句话

第八轮做的是**反馈与可读性打磨**：暂停面板的技能路线改为「只画已选路线」的菱形图（1 连 2/3，2/3 连 4），
HUD 克制三角改为直边 + 中段大箭头，并提前到右键选择时与轮盘同时出现（高亮候选色），确认后渐隐；
暂停面板滚动改为快速缓动；命中/灵魂/升级/超暴击/开箱音效重做（见 §2.3）；
散布改为每颗子弹的随机方向偏差，散弹线加大散布、`裂片`大幅削弱；主菜单新增空的
**图鉴 / CODEX** 占位页；商人提前到 1:20，触碰后先击退敌人、吸完全屏经验/金币再开店。
`Audio` 现在 24 个音效（新增 `soul`）。幸运线收尾：掉箱上限 12%→9%、宝箱遗物率上限 75%→50%、
金块 2000→500，压住后期遗物喷泉。

## 1. 本轮要求

> “技能路线画大一点，菱形路线，1 连 23、23 连 4，只有选择的路线才放进去。”
> “命中的音效太清脆、太高、太吵，简单低频的 8BIT 感更好。灵魂最好是低声的嗡鸣感。”
> “属性克制图放在切换颜色右方，或者更直观的方式。”
> “散射线第一阶加大散布（约 10°），弹幕扩散至少 7°，扩容弹匣也加一点；主菜单可以做图鉴，先空着。”
> “裂片太强，爆出的子弹射程和速度大幅削减，不继承穿透和暴击。”
> “散布是射击偏差：往一个方向射，两次不一样，给子弹方向加随机数。”
> “菜单滑动要平滑动画，可以快；以后可能上安卓/TapTap，记得在 plan 里留优化空间；
> 属性克制只在换色后 3 秒出现再渐隐，删掉大部分文字和数值。”
> “开宝箱的声音太难听了，换一下。”
> “商人首次出现提升到 1 分 20 秒，触碰时击退附近敌人并吸取全屏经验和金币，吸完或延迟后进商店。”
> “重新设计克制图标：现在不清晰、反映不出克制关系，箭头小而且重叠了。”

## 2. 本轮实现

### 2.1 技能路线菱形图（`scripts/ui/PausePanel.gd`）

- `_rebuild_cache()` 只收录**本局至少点过 1 个节点**的分支；未选择的 14−N 条线完全不占版面。
  焦点兜底也改成“必须已解锁”，避免指向被过滤掉的锁定节点。
- 单张卡内是菱形：I 左中、II 上中、III 下中、IV 右中；连线为 `I→II`、`I→III`、`II→IV`、`III→IV`。
- 节点半径 `clampf(h × 0.09, 14, 22)`，节点内用罗马数字 `I/II/III/IV`，节点下方写技能名；
  三态颜色（已解锁 / 可解锁 / 锁定）沿用旧配色，图标仍是 `SkillGlyph`。
- 自适应网格：主区宽 <1000 用 3 列，否则 4 列；可见 1–2 行，超出部分用滚轮 + 右侧滚动条；
  `open()` 与切页时重置 `_route_scroll` 并夹到 `max_scroll`。
- 空态：一个节点都没点时显示提示，而不是画 14 张空卡。
- 标题栏改显示 `N 条已选路线 · M 个节点 · 悬停查看详情`。
- 滚动改为“目标位置 + 快速缓动”：滚轮只改 `_route_scroll_target` / `_relic_scroll_target`，
  `_process()` 里用 `1 − exp(−18δ)` 逼近，足够近时吸附；不再一整格瞬移。

### 2.2 HUD 属性克制图（`scripts/ui/HUD.gd`）

- `_draw_color_selector()` 之后调用 `_draw_color_relation()`：切色条右侧的克制三角。
- 三角循环 RED（上）→ GREEN（右下）→ BLUE（左下）；直边 + **中段**大箭头（8–9.5 px），箭头指向被克制的
  颜色，不再压住端点色球；底色用克制方颜色。
- 当前颜色的出边最亮最粗（它克制谁），指向当前颜色的边次之（谁克制它），第三条压暗；当前节点套白环，
  背后一层淡暗圆保证亮弹幕上可读。
- **右键选择阶段就显示**：`color_switch_preview(true)` 与轮盘同时打开，`_relation_color` 跟随拖拽方向高亮
  候选颜色（无方向时高亮当前色）；松开后 `_relation_preview` 关闭，只保留 **1.2 秒**确认渐隐。
  快速点击没有预览阶段，`color_changed` 仍补一次 1.2 秒显示。无文字/数值，不参与输入。

### 2.3 音频（`scripts/autoload/Audio.gd`）

- `hit` / `weak_hit` / `crit` 换成**低频 8-bit 方波**：`hit` 185→92 Hz、75 ms、1.5 kHz 低通、`db = -8`；
  `weak_hit` 196→294 Hz 双音，`crit` 262→392→523 Hz 三音。
- 新增第 24 个 id `soul`：`_do_soul_pulse()` 触发；`_hum` 双失谐低音 + 4 Hz 颤音，合成兜底；冷却 400 ms。
- `level_up` 改为 **225 ms 上行四音**（C5→E5→G5→C6，末音上滑），替换原下行采样。
- `super_crit` 改为 **240 ms 低频 + 高频双层**：140→58 Hz 冲击 + 1.8/2.6 kHz 闪光 + 22 ms 噪声裂口；
  合成兜底为 `_impact_shine()`。
- `chest` 改为 **520 ms 柔和上行钟音**（C5→E5→G5→C6 + 130 Hz 托底），替换原 `powerUp1`。
- 外部加载顺序改为 **`.wav` > `.ogg`**，生成音放在
  `assets/audio/sfx/{hit,weak_hit,crit,soul,level_up,super_crit,chest}.wav` 直接覆盖旧 OGG，旧文件保留不删。
  `docs/AUDIO.md` 已同步 24 个 id 与两套来源。

### 2.4 散布与裂片

| 节点 | 变化 |
| --- | --- |
| `shotgun_1`（散射） | 新增 `+10° 射击散布`（除 +1 弹丸、伤害倍率 −20% 外） |
| `fire_3`（弹幕扩散） | 散布 4° → **7°** |
| `shotgun_3`（扩容弹匣） | 新增 `+5° 射击散布`（除 +1 弹丸、+1 穿透外） |
| `shotgun_2`（裂片） | 速度 ×0.50、存活 ×0.45（射程约剩两成）、不继承穿透、不继承暴击 |

- `ProjectileManager.fire()` 增加 `speed_scale / lifetime_scale / allow_crit`，透传到 `Projectile.setup()`。
- `Skills.build_hit_context(...)` 增加独立 `allow_crit` 参数：雪片既不参与普通暴击，也不触发超暴击。
- `Projectile.setup()`：`damage_scale < 0.99` 时强制 `pierce = 0`（裂片不再继承穿透）。
- **散布改为真正的射击偏差**：每颗子弹方向都加 `randf_range(-spread/2, +spread/2)`，同一方向连射两次
  不会走同一条线；`Player._shot_jitter()` 负责取样，`spread = 0` 时不消耗随机数。
- 多弹丸保留 `18° + 5°×(count−2)`（上限 50°）的基础扇面用于铺开，每颗弹丸再独立叠随机偏差；
  散布不再加宽扇面，因此 `fire_3` / `shotgun_1` / `shotgun_3` 都会让弹道更“飘”，而不是把扇面撑大。

### 2.5 主菜单图鉴占位（`scripts/menu/CharacterSelect.gd`）

- 右上 `图鉴 / CODEX` 按钮（`C` 开），压暗背景 + 空面板底纹，文字“图鉴内容尚未录入 / 待补充”，底部“返回”。
- `Esc` / `Enter` / `Space` / `C` / 点外部 / 返回均可关闭；打开时不响应角色卡。内容待后续指定。

### 2.6 商人节奏与吸附（`Director.gd` / `Main.gd` / `PickupField.gd`）

- 首商固定 **1:20**；之后按 `Skills.merchant_interval()`（基础 **120 秒**、怀表 ×0.8、最低 30 秒）。
- 隐藏机制：一次到访买空整排货架，下一只提前 **10 秒**（`SHELF_CLEAR_BONUS`）；`open()` 内只发一次
  `shelf_cleared`，重 roll 后再买空也不叠加，UI 不提示。
- 触碰商人：击退 **340 px** 内敌人（760 / 0.42 s）→ `Pickups.vacuum_all()`（宝箱不参与）；`Main` 等到
  `currency_count() == 0` 或 **1.1 s** 才隐藏 HUD、暂停、开 `ShopPanel`。吸附期间正常游玩。
- 升级/祭坛/暂停时吸附停住，关闭后续吸；死亡清空。

## 3. 验收结果

- [x] `skills_test` 全绿：`fire_3` 7°、`shotgun_1` +10°、`shotgun_3` +5°、裂片速度 ≤55%、存活 ≤50%、
	  `pierce == 0`、禁止暴击。
- [x] `audio_test`：`sounds=24 voices=20`，24 个流均非空。
- [x] `screenshot_pause_build.png`：菱形卡、`I/II/III/IV`、连线、滚动条、已选路线数量均正确；
	  滚轮只改目标位置，`_process()` 缓动逼近，不再整格瞬移。
- [x] `screenshot_switch.png`：右键预览时克制三角与轮盘同时出现，箭头指被克色、不压色球，候选色出边最亮，
	  确认后 1.2 秒渐隐。
- [x] `merchant_test` / `pickups_test`：首商 `80.0`（1:20）、触碰后先吸附、HUD 保持、吸完才开商店；
	  `vacuum_all()` 只吸经验/金币、宝箱留在原地、奖励照常入账；买空货架 −10 秒且每次到访只一次。
- [x] `screenshot_select.png` / `screenshot_codex.png`：图鉴按钮与空面板正常，返回可关闭。
- [x] `plan.md` §17：Android / TapTap 的输入、分辨率、渲染、音频预留。
- [x] 九套无头测试全部退出码 0（smoke、skills、autoplay、menu、relics、pickups、merchant、audio、altars），含上限与金块 500 断言。

> `--headless` 跑 `audio_test` 退出时可能打印 `ObjectDB instances leaked` / `resources still in use`；
> 是 dummy 音频驱动的回收延迟，退出码 0。

## 4. 测试与截图

```bash
GODOT="D:/Install/Godot_v4.4.1-stable_win64.exe/Godot_v4.4.1-stable_win64_console.exe"

# 九套无头回归
for suite in smoke_test skills_test autoplay_test menu_test relics_test \
			 pickups_test merchant_test audio_test altars_test; do
  "$GODOT" --headless --fixed-fps 60 --path "C:/Users/11257/Documents/光谱突围" \
	"res://tests/${suite}.tscn" || break
done

# 截图（真实窗口）
"$GODOT" --path "..." res://tests/screenshot.tscn -- pause_build
"$GODOT" --path "..." res://tests/screenshot.tscn -- switch
"$GODOT" --path "..." res://tests/screenshot.tscn -- shotgun
"$GODOT" --path "..." res://tests/menu_screenshot.tscn -- --mode select --shot res://tests/screenshot_select.png
"$GODOT" --path "..." res://tests/menu_screenshot.tscn -- --mode codex --shot res://tests/screenshot_codex.png

# 新增音频/脚本后刷新导入
"$GODOT" --headless --editor --quit --path "C:/Users/11257/Documents/光谱突围"
```

## 5. 文件清单（第八轮）

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/PausePanel.gd` | 菱形路线图、只显示已选路线、3/4 列自适应、平滑滚动、滚动条、空态 |
| `scripts/ui/HUD.gd` | 右键选择时即显示的克制三角：直边、中段大箭头、候选色出边高亮，确认后 1.2 秒渐隐 |
| `scripts/game/Main.gd` | 商人吸附状态机：击退周围敌人 → 全屏吸取 → 吸完或 1.1 秒后开店 |
| `scripts/pickups/PickupField.gd` / `PickupSystem.gd` | `vacuum_all()` 全屏吸附、`currency_count()` 判断是否吸完 |
| `scripts/autoload/Director.gd` | 首商 120 → 80 秒 |
| `scripts/autoload/Audio.gd` | 低频 8-bit 命中三音、`soul` 嗡鸣、上行短升级音、低频+高频超暴击、WAV 优先 |
| `scripts/autoload/SkillSystem.gd` | `build_hit_context` 增加 `allow_crit`；裂片参数；灵魂脉冲发声 |
| `scripts/projectiles/ProjectileManager.gd` | `fire()` 增加速度/存活/暴击缩放 |
| `scripts/projectiles/Projectile.gd` | 缩放参数、`allow_crit`、小子弹强制零穿透 |
| `scripts/skills/SkillCatalog.gd` | `fire_3` 7°、`shotgun_1` +10°、`shotgun_3` +5° |
| `scripts/menu/CharacterSelect.gd` | 图鉴按钮与空面板占位（`C` 开、`Esc` 关） |
| `tests/skills_test.gd` | 随机散布、多弹丸不重样、裂片（速度/存活/穿透/暴击）断言 |
| `tests/audio_test.gd` | 新增 7 个生成音的合成兜底非空检查 |
| `tests/menu_screenshot.gd` | 新增 `codex` 截图模式 |
| `tests/merchant_test.gd` / `tests/pickups_test.gd` | 1:20 首商、吸附流程、买空货架奖励、`vacuum_all`、宝箱不参与 |
| `assets/audio/sfx/*.wav` | 新增 7 个生成音（`hit`、`weak_hit`、`crit`、`soul`、`level_up`、`super_crit`、`chest`） |
| `docs/SKILLS.md` / `docs/AUDIO.md` / `CLAUDE.md` / `plan.md` | 数值、音效与状态同步 |

## 6. 下一步

1. **图鉴内容**：范围确定后填充技能/遗物/敌人/颜色关系，复用 `SkillGlyph`。
2. **技能树交互**：升级流程补重 roll / 跳过与完整树选择页。
3. **武器融合**：第二把武器 → Trait 叠加 → 签名 `FusionRuleResource`。
4. **精英/Boss**：复用敌人数据 + 阶段脚本；死亡用 `FX.glow_pulse()` + 白闪 + 专属碎裂。
5. **数值/节奏调优**：散弹线强度、祭坛价格、商人间隔、刷怪密度、能量回复；彩票待重做为极低概率头奖。
6. **音频打磨**：为射击/切色生成更电子化的变体；按实际试听重调 `SOUND_DEFS.db` 与 `soul` 频率。
7. **性能**：只在 `MAX_ENEMIES` 提到 100+ 时再引入敌人对象池；继续用 F3 观察帧时间。
8. **安卓 / TapTap 预留**：按 `plan.md` §17 保持输入/渲染边界；不要在玩法里写平台分支；
   移动画质（关 Glow、降敌人上限、减声部）等确定移植时再做。

## 7. 约束与注意事项

- 项目不是 git 仓库；不要破坏性删除，不要手改 `.godot/`。新增脚本/资源后跑一次 headless editor 刷新导入。
- 保持 HDR 2D + Glow；目标 60 FPS；效果对象池化，不要恢复每命中节点/Tween 分配。
- 文件 UTF-8 无 BOM、LF；中文 UI/注释；Godot 4.4.1，避免 4.5+ 语法；不要用 `trait` 作变量名。
- **暂停 reason 必须分开**：`&"level_up"`、`&"shop"`、`&"manual_pause"`、`&"altar"`；任一个释放都不能误恢复。
- 新增模态面板时同时处理：`Main` 的排队、Esc 路由、死亡强制关闭、HUD 显示/隐藏。
- **音效不要逐命中创建节点**；新音效先加 `SOUND_DEFS` + `_synth()` 兜底，再放素材。
  素材替换只改 `assets/audio/sfx/`，同名 `.wav` 优先于 `.ogg`；不要把整包 Kenney 素材倒进项目。
- 裂片的削弱是三道锁：速度/存活缩放、`damage_scale < 0.99` 强制零穿透、`allow_crit = false`。
  调强时改数值即可，不要恢复暴击继承。
- 技能路线图只画已选分支；不要改回固定 14 卡，否则会撑爆暂停面板。
- 角色倍率必须是 MULTIPLY 层；遗物默认可重复，新增不可重复内容必须 `unique = true` 并在描述写“唯一”。
- 重型弹的双倍时间属于发射前蓄力（`_heavy_primed`），不要改回发射后冷却。
- 恶魔/天使遗物只通过“对应 2 阶已选择”进入商店；祭坛只在对应 3 阶后生成；不要恢复阵营权重加倍。
- 拾取范围只放在 `Skills.pickup_radius_multiplier()`，`PickupField` 每帧读取。
- 文档体积守则：轮次历史写 `docs/HISTORY.md`；`CLAUDE.md` 保持 < 20 KB、`plan.md` < 35 KB、本文件 < 15 KB。
- `人类用.md` 现在是三份文档的索引；原始设计条目在 `docs/SKILLS.md` / `docs/RELICS.md` /
  `docs/DESIGN_NOTES.md`，修改前先读最新内容。
