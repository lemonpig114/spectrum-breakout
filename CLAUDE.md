# CLAUDE.md

Guidance for Claude Code in this repository.

## Project

Godot **4.4.1** (Forward Plus, Windows) 2D minimalist neon top-down arena survivor, project name `光谱突围`.
Geometry remains procedural; round 9 adds a shared generated radial texture and pooled local energy-veil shader (no external image assets). The look depends on the
black background, the grid shader, HDR colors (>1.0) and `WorldEnvironment` glow. `rendering/viewport/hdr_2d=true`.

- Git repository with public remote `lemonpig114/spectrum-breakout`. Do not delete files destructively; read `HANDOFF.md` before changing behavior.
- Android touch input creates the joystick at the touch point; the base stays there until release by default, with
  optional base-follow behavior in the phone settings page.
  The joystick and touch color gestures live in `MobileControls`; movement state and the saved preference live in
  `GameInput`. Phone aiming stays automatic. Test/export notes: `docs/MOBILE.md` and `plan.md` §17.
- `ContentDB` must enumerate exported resources with `ResourceLoader.list_directory()`. `DirAccess` failed in the
  Android package, leaving characters/enemies/skills/relics empty. Recheck an exported `.pck` after content changes.
- Auto aim is limited to the camera view and 620 world units. `RunState` emits staggered global DoT ticks.
  Pickup caps preserve visible old ground drops, merge close same-kind drops first, and evict only offscreen currency.
- Ordinary triangle/square/hexagon enemies are drawn through `EnemyBatchRenderer` MultiMeshes; ordinary bullets through
  `ProjectileBatchRenderer`. Enemy AI, health bars, statuses and projectile Area2D collision remain per node. Boss,
  planes, exploding rounds, empowered squares and heavy bullets retain custom draws. Projectile active-list release
  uses swap removal with `active_index`. Benchmark with `tests/_perf_probe.tscn -- --projectiles=300`; use
  `--no-enemy-batch` / `--no-projectile-batch` for visual or performance comparisons.
- Continuous timed survival (no waves). Color cycle RED → GREEN → BLUE; switching costs 1 energy, or 2 with Shield Generator.
- 19 skill branches × 4 tiers = **76 nodes**, **51 relics**, shop, luck/chests, manual pause, altars, audio.
- Startup: `scenes/boot.tscn` (~1.8 s loading) → `scenes/character_select.tscn` → `scenes/main.tscn`.
  Selection is stored in `RunState.selected_character_id`; running `main.tscn` directly falls back to `prism`.
- Three units (`prism`, `bulwark`, `falcon`) share `CharacterResource.BASE_WEAPON_ID = basic_bolt`; their differences
  are only the `damage_multiplier` / `fire_rate_multiplier` / `projectile_size_multiplier` MULTIPLY modifiers
  (source `character_*`) plus absolute health/speed.

Current rules (round 20 + follow-up):

- Spawns 0–360 s and beyond: 3/4/6/13/6/8/12/6/8 per second. 120–180 s and 300–360 s use surround rings with an
  independent random color per enemy (no same-color packs); the former has a 100-enemy cap, while the usual cap grows 40→80.
- HP steps ×0.8 (0–15 s), ×1 (15–60 s), ×1.5 (60 s), ×2 (120 s), ×2.5 (180 s), ×3.5 (240 s), ×5 (270 s), ×6 (300 s). Boss at 180 s:
  50,000 ×2.5 = 125,000. Plane at 240 s (3 s shots, 340 px preferred); exploding round from 270 s.
- Enemy shape is independent of color: triangle 25 HP / 1 XP, square 60 HP / 1.5 XP, hex 200 HP / 5 XP / 5 gold / 30% armor.
  Contact and ranged damage rise from 0.5 to 1 heart at 240 s.
- The exploding round has no center dot and sheds sparse movement sparks. Its death blast is the only permitted
  death ring: a wave to the exact 64 px damage radius plus fracture rays. All other deaths are shatter-only.
- XP: 6/12/20/30 for the first four levels; L5–30 `8 + 6L + round(0.50*(L-5)²)`; from L31 add `10*(L-30) + round(0.70*(L-30)²)`.
- Luck +12/+12/+16; chest cap 6%, relic conversion 20%; Koi +6 luck / 60 s on chest discovery (refresh only).
  Relic rewards queue in the 420 px top strip (5 s auto-take); pending copies reserve uniqueness/stack limits.
- Damage numbers: elemental/weakness/crit captions combine when multiple tags apply; super crit omits weakness and uses the rainbow gradient. No marker toggle.
- Performance: 200-enemy basic probe 60 FPS; all-skills immortal ~37–42 FPS; 70-enemy all-skills ~51 FPS.
  `EnemyFlock` spatial-hash separation stays on.
- Ground gold/XP left idle for 10 seconds merge with nearby same-kind drops within 80 px once per second, preserving uncollected value and scaling the icon by merged count.
- After every skill/relic edit, run `res://tests/export_design_tables.tscn` and update `docs/SKILLS.md` /
  `docs/RELICS.md`. Rounds 1–19 details: `docs/HISTORY.md`; current round: `HANDOFF.md`.

## Docs

| File | Purpose |
| --- | --- |
| `HANDOFF.md` | **Read first.** Current round, acceptance results, next steps, constraints. |
| `plan.md` | Design (§1–15) + concise current handoff (§16). |
| `docs/HISTORY.md` | Compact archived details of rounds 1–19 (round 20 lives in HANDOFF). |
| `docs/AUDIO.md` | 24 sound ids, source mapping, CC0 licenses, replacement convention. |
| `docs/SKILLS.md` | All 76 implemented skill nodes by branch: prerequisites, effects, runtime mechanics. |
| `docs/RELICS.md` | All 51 relics by quality/side: base price, tags, effects, acquisition rules. |
| `docs/DESIGN_NOTES.md` | Quality names, shop/luck/altar economy, design-vs-implementation deltas. |
| `人类用.md` | User's active design list; implemented items are marked **[complete]**. Re-read before editing because Claude Code may update it. |

## Commands

```bash
GODOT="D:/Install/Godot_v4.4.1-stable_win64.exe/Godot_v4.4.1-stable_win64.exe"
# Use Godot_v4.4.1-stable_win64_console.exe in the same folder if stdout must appear.

# Run / editor
"$GODOT" --path "C:/Users/11257/Documents/光谱突围"
"$GODOT" --headless --editor --quit --path "C:/Users/11257/Documents/光谱突围"   # import + class cache

# Headless regression (all exit 0, print SUITE PASS/FAIL)
"$GODOT" --headless --fixed-fps 60 --path "..." res://tests/smoke_test.tscn
"$GODOT" --headless --fixed-fps 60 --path "..." res://tests/skills_test.tscn
"$GODOT" --headless --fixed-fps 60 --path "..." res://tests/autoplay_test.tscn
"$GODOT" --headless --fixed-fps 60 --path "..." res://tests/menu_test.tscn
"$GODOT" --headless --fixed-fps 60 --path "..." res://tests/relics_test.tscn
"$GODOT" --headless --fixed-fps 60 --path "..." res://tests/pickups_test.tscn
"$GODOT" --headless --fixed-fps 60 --path "..." res://tests/merchant_test.tscn
"$GODOT" --headless --fixed-fps 60 --path "..." res://tests/audio_test.tscn
"$GODOT" --headless --fixed-fps 60 --path "..." res://tests/altars_test.tscn
"$GODOT" --headless --fixed-fps 60 --path "..." res://tests/boss_test.tscn

# Debug run flags go after --:
# --force-super-crit | --relic=dust_knife --relic=dust_apple | --merchant | --boss | --levels=10

# Screenshot (needs a real window/GPU, not --headless)
"$GODOT" --path "..." res://tests/screenshot.tscn -- <mode> [--character falcon] [--shot res://tests/out.png]
# modes: selector levelup panic fx supercrit switch styles hearts pickups merchant
#        merchant_arrow shop shop_full pause pause_build pause_relics pause_settings
#        pause_quit shotgun
"$GODOT" --path "..." res://tests/menu_screenshot.tscn -- --mode boot --shot res://tests/screenshot_boot.png
"$GODOT" --path "..." res://tests/menu_screenshot.tscn -- --mode codex --shot res://tests/screenshot_codex.png
"$GODOT" --path "..." res://tests/gradient_text.tscn -- --shot res://tests/gradient_text.png
"$GODOT" --headless --path "..." --script res://tests/zoom_screenshot.gd -- in.png out.png 4 x y w h
```

## Architecture

### Autoloads (order matters; later ones reference earlier ones)

`GameInput` → `EventBus` → `ContentDB` → `RunState` → `Skills` → `Pickups` → `FX` → `Audio` → `Director`.

- **GameInput** — runtime input actions (`move_*`, `dash`/`switch` placeholders, `pause` = Esc).
- **EventBus** — global signals: color/energy/health, gold/xp/level, `run_started/ended`, `player_died`,
  `player_damaged/dodged`, `merchant_spawned/reached/despawned`, `altar_spawned/reached/despawned`.
- **ContentDB** — recursively indexes every `Resource` under `data/` by `id`; add a `.tres` to register content.
- **RunState** — single source of run truth: elapsed, color/energy, gold/xp/level, arena, color rules, fractions,
  `spend_gold/refund_gold`, `selected_character_id`. Pause reasons: `&"level_up"`, `&"shop"`, `&"manual_pause"`,
  `&"altar"`; `request_pause(reason)`/`release_pause(reason)` releases only when the set is empty.
- **Skills** (`scripts/autoload/SkillSystem.gd`) — skill tree, relics, modifiers, special combat resolution, shop
  pool/slots/rerolls, luck/chests, pickup radius, side-relic altar grants. Catalog is code-built in
  `scripts/skills/SkillCatalog.gd` (not `.tres`): edit that file to add/retune nodes or relics.
- **Pickups** — `spawn_gold/spawn_xp/spawn_chest`, plus `vacuum_all()` / `currency_count()` for the merchant;
  forwards to `PickupField`, falls back to direct credit when absent.
- **FX** — pooled floating damage text, hit sparks, shards, six `EnergyBurst` styles, camera trauma, grid ripple,
  low-frequency hit-stop, `glow_pulse()` for rare punctuation.
- **Audio** — 24 sound ids; `Audio.play(&"id")`; external `.wav` > `.ogg` > synth. See `docs/AUDIO.md`.
- **Director** — continuous spawner (usual max 80 enemies, 100 during 120–180 s), merchant timing (first at 1:20, base 90 s; clearing a whole
  shelf pulls the next one 10 s earlier, once per shop), altar timing, and a one-shot 180 s boss
  (`spawn_boss_now`; merchant/altar spawn entries are public/test too).

### Menu flow

`MenuScreen` is the shared `Control` base (CJK font, bold `FontVariation` with integer `WGHT_AXIS = 0x77676874`,
grid backdrop, fade transition). `BootScreen` is skippable after 0.25 s. `CharacterSelect` builds cards from
`ContentDB.get_characters()` with `CharacterVisual.draw_unit` and writes `RunState.selected_character_id`.
It also has a top-right **图鉴 / CODEX** button (`ui/CodexPanel.gd`, searchable categories and details; `C` opens, Esc/back closes).
Both use `assets/environments/neon.tres`.

### Data (`data/`)

- `colors/default_color_rules.tres` — advantage ×1.5, same ×0.7, reverse ×1.0, HDR boost 2.4.
- `weapons/basic_bolt.tres` — shared base attack; `heavy_bolt` / `rapid_bolt` unused, reserved for fusion.
- `characters/*.tres` — `CharacterResource`; a fourth unit is just a new `.tres`.
- `enemies/*.tres` — `EnemyTypeResource`; triangle/square/hex, timed ranged plane, exploding round, and the 180 s `square_boss`.
- `upgrades/*.tres` — legacy/unused; do not delete in this non-git project.
- Skill nodes/relics live in `SkillCatalog.gd`; `WeaponTraitResource`/`FusionRuleResource` are fusion stubs.

### Modifier pipeline

`StatBlock` = `(base + flat) × (1 + Σadd%) × Πmultiply`, sorted by priority. `ModifierPipeline` stages:
`ON_FIRE → ON_SPAWN → ON_TRAVEL_TICK → ON_HIT → ON_KILL → ON_EXPIRE`. `WeaponRuntime` binds core + stats + pipeline
+ traits. `DamageContext` carries source/target/amount/color relation/multiplier/hit position/tags/crit/kill flags.
Every modifier source must be unique per instance (`character_*`, `relic_<id>_<n>`, `altar_demon_<n>`).

### Gameplay (`scripts/game/Main.gd`)

`Main` starts `RunState`, spawns the player, configures camera/`Director`, plays the intro, then enables controls.
It owns modal routing and `_flush_pending_events()` (merchant first, then altar):

- Level-up: hide HUD, `&"level_up"` pause, `Skills.pick_options(3)`, unlock, resume.
- Merchant: on `merchant_reached`, hide HUD, `&"shop"` pause, `ShopPanel.open(player)`; close resumes and calls
  `merchant.leave()`.
- Altar: on `altar_reached`, hide HUD, `&"altar"` pause, `AltarPanel.open(altar, player)`; close releases and leaves.
- Manual pause: Esc / top-right `PauseButton`, `&"manual_pause"`, `PausePanel`.
- If a panel is already open, merchant/altar requests are queued. Death force-closes panels, clears queues,
  resets pause/`Engine.time_scale`, then after 0.6 s opens `GameOverPanel` with `&"game_over"` pause:
  **再来一局** (`R`/Enter, reloads the scene with the same character) or **返回主界面** (`Esc`, character select).
- `_return_to_menu()` is the single exit for game over and the pause menu: closes panels, `RunState.abandon_run()`,
  unpauses, then `change_scene_to_file("res://scenes/character_select.tscn")`.

### Key gameplay systems

- **Player** (`CharacterBody2D`) — reads selected character; hearts in units (1.0 = one heart, `snap_to_half`);
  contact costs 0.5. Auto-aims nearest enemy ignoring color; left mouse overrides aim and suppresses auto-aim 0.5 s.
  Right click: quick click cycles next color; hold ≥140 ms + ≥18 px horizontal drag previews prev/next; release
  commits; costs 1 energy. On commit: 0.22 s color crossfade, white core flash, ring, arcs, grid ripple. On damage:
  dodge first (60% cap, overflow becomes crit), else panic shockwave (kill ≤84 px, push ≤280 px) + shake/hit-stop.
  `pay_max_health()` is the demon-altar trade (never below 1 heart).
- **Firing** — `damage × damage_mult × damage_final`; rate capped at
  `core.fire_rate × character rate × Skills.fire_rate_cap_multiplier()`. `spread_degrees` is per-bullet aim
  deviation: one or 3+ pellets add `randf_range(−s/2, +s/2)`. Exactly two use zero angle offsets and separated muzzles. Three or more
  keeps a centered base fan (`18° + 5°×(n−2)`, cap 50°, odd counts center lane, even counts start at ±0.5 lane) and
  jitters each pellet independently; spread no longer widens the fan. Heavy tier 2 adds knockback against regular
  enemies; bosses are immune. Tier 4 keeps the five-second charged shot with doubled pre-fire charge interval.
- **Enemy** — independent scene per spawn; rotating polygon, chase, contact cooldown, elemental statuses (burn,
  stacking poison, slow ≤60%, ice), `take_true_damage()`, `execute()`, `force_kill()`. On death it scatters gold and
  XP to two points 9–26 px around the corpse through `Pickups`; rewards credit only on pickup. Death plays a
  0.10 s pause-safe body fade and independent `STYLE_SHATTER` fragments; no death ring, veil, grid ripple or hit-stop.
- **Projectiles** — pooled Area2D (512 max, 64 prewarmed). Hits use `Skills.build_hit_context()` (color/weakness,
  crit/super crit, ice); weakness may attach elements/execute; splash on first/last-pierce unless tier 4 fires on
  every hit. Charged heavy shots use `(raw + 40) × mult × final × 2.5` and 1.5× size. `fire()` takes
  `damage_scale / size_scale / speed_scale / lifetime_scale / allow_crit`; 裂片 passes `0.35 / 0.68 / 0.50 / 0.45 / false`,
  and any shot with `damage_scale < 0.99` is forced to `pierce = 0`.
- **Pickups** (`scripts/pickups/PickupField.gd`) — Packed arrays, no node per drop, one `_draw`. Kinds: gold ring,
  XP diamond, chest. Magnet `88 × Skills.pickup_radius_multiplier()` (xp_1/gold_1 +50% each, both kinds), collect at
  15 px, gold 25% slower (`GOLD_SPEED_SCALE`). 32 pooled `Line2D` streaks; merge within 12 px (chests never merge);
  caps 90 idle / 200 total / oldest uncollected currency discarded without credit. Chests call `Skills.open_chest()`. Paused with the tree.
  `vacuum_all()` sends every idle XP/gold drop (not chests) flying in; `currency_count()` excludes chests.
- **LevelUpPanel / ShopPanel / AltarPanel** — modal `PROCESS_MODE_WHEN_PAUSED` panels. Level-up cards show a
  procedural branch glyph (`scripts/ui/SkillGlyph.gd`) next to the branch label. Shop shelf is
  `min(14, 4 + shop_level)`; donation price `round(60 × clamp(1−elapsed/300×0.4,0.6,1) × (1+0.8L+0.18L³))`; rerolls
  `8 + 4×rerolls`; every card shows rarity/owned/unique/price. Altar: demon = 1 max heart, angel = 120 + 20/minute;
  after both side relics are owned, fallback is heal 2 hearts / gold gift.
- **PausePanel** — full-screen build overview. Left tabs switch between a **技能路线** diamond map and a
  **遗物清单** grid (rarity-sorted, quality colors, count badges, tags, wheel scroll, hover detail). The route map
  only lists branches with ≥1 unlocked node: each card is a diamond (I left, II top, III bottom, IV right) with
  `I→II/I→III/II→IV/III→IV` connectors, procedural `SkillGlyph` icons, tier numerals and unlocked/available/locked
  states. Cards lay out in 3 columns (4 when main width ≥1000), 1–2 rows visible, wheel-scrolled through an
  eased target (`1 − exp(−18δ)`) with a scrollbar, and an empty state when nothing is picked yet. Right column:
  run summary + `继续游戏 / 设置 / 返回主界面`; settings adjusts master volume ± and mute; the return entry asks for
  confirmation and emits `menu_requested` (Main goes back to character select instead of quitting the process).
  Esc backs out of subpages (otherwise resumes), Tab switches tab, M toggles mute.
- **GameOverPanel** — `PROCESS_MODE_ALWAYS` results card drawn in `_draw`; stats come from `RunState`, two clickable
  buttons, R/Enter retry, Esc menu. The old HUD game-over overlay was removed.
- **HUD** — custom `_draw` hearts (`1.0` per heart, empty outline, left-to-right clip, pulse below 30%), energy
  diamonds, crit/dodge/luck, color selector with a right-side textless **属性克制** triangle (RED→GREEN→BLUE,
  straight edges, mid-edge arrows pointing at the beaten color, current outgoing edge brightest) that opens with the
  right-click selection (highlighting the candidate color) and fades 1.2 s after commit, timer/level/gold,
  right-click wheel, damage edge flash, off-screen merchant/altar edge markers. F3 debug overlay: FPS, frame/physics
  time, enemies, drops, nodes.
- **Merchant/Altar** — Node2D actors, no physics. Merchant: gold coin, no face, 45 s lifetime, hop, `¥`; on touch
  it knocks enemies within 340 px back, `Pickups.vacuum_all()`, then `Main` opens the shop when
  `currency_count() == 0` or 1.1 s elapses (HUD stays visible during the vacuum). Altar:
  procedural demon inverted obelisk/eye vs angel obelisk/wings/halo, 45 s lifetime, side color. Both emit reach events
  once and `leave()` on close.

### Rendering / conventions

- HDR 2D must stay on; neon colors >1.0 drive glow; clear color pure black; `assets/environments/neon.tres`.
- `GridBackground` + `shaders/grid.gdshader` draw in local UV space and ripple 4 slots without distorting HUD.
- `CameraRig` follow lerp, trauma shake, arena limits, intro zoom.
- All paths `res://`; never hand-edit `.godot/` (generated). Godot 4.4 syntax only (no 4.5+).
- UTF-8 **without BOM**, LF, Chinese UI/comments. Do not name a variable/parameter `trait` (use `weapon_trait`).
- **60 FPS target** (`max_fps=60` + vsync). Pool effects; no per-hit node/Tween allocation; no per-hit
  `Engine.time_scale`. One death Tween per kill is acceptable. Enemy-enemy physics collisions stay off; `EnemyFlock` uses a 30Hz spatial hash plus 60Hz soft steering/correction.

## Tests (21 headless suites)

| Suite | Covers |
| --- | --- |
| `smoke_test` | color multipliers, energy/cycle, ContentDB, 76/51, pause, glow pulse, panic shockwave, level-up flow, death→game-over panel/pause, HDR |
| `skills_test` | every branch, gating, demon/angel exclusion, caps, heavy charge, dodge/crit, elements, shotgun fan, luck, pickup radius |
| `autoplay_test` | 30 s random build + combat; unlocks consistent, director still spawning, run unpaused |
| `menu_test` | 3 characters, selection, boot→select, Main applies character multipliers to `basic_bolt`, game-over retry/menu buttons and pause-menu return signal |
| `relics_test` | all 51 relics, stacking/unique, apple, blunt blade, heart units, lucky tier, impact releaser synergy |
| `pickups_test` | magnet/arrival credit, scatter, merge, chests, clamped steps, radius growth, gold speed, merchant vacuum, streaks, pool caps |
| `merchant_test` | 1:20 timing, vacuum-before-shop, shelf-clear −10 s (once per visit), one-at-a-time, pause/shop, 4 slots, donation, unique exclusion, buy/reroll/heal/leave, side gating, 14-card layout |
| `audio_test` | ≥20 sounds, non-empty streams, synth fallbacks, throttle, mute, 20-voice cap, event wiring |
| `altars_test` | tier-3 gating, spawn/one-at-a-time, demon heart cost + relic, fallback gift, angel gold cost + relic |
| `visual_fx_test` | 12-veil budget, pooled expiry/reuse/color reset, star fallback, scene teardown |
| `relic_choice_test` | luck caps, chest-discovery Koi, pending rewards, discard/take, 5-second timeout, pause, queue limits, teardown |
| `xp_test` | early thresholds, gentle quadratic later levels, XP overflow and ordered level-up events |
| `flock_test` | 70-enemy crowd separation, player approach, spatial hash, freed cached neighbour skipped |
| `codex_balance_test` | codex entries/search/close, HP curve/spawn paths/resource isolation, dynamic modifier index |
| `dice_test` | two-copy cap and reservations, all six stacked results, actual face animation, reuse/follow/pause/cleanup |
| `enemy_design_test` | four enemy roles, independent colors, fractional XP, plane projectile and spawn exclusion |
| `spawn_phase_test` | exact time boundaries, 4:1 composition, same-color clusters, 240-second damage step and pressure math |
| `boss_test` | 180 s spawn-once and 1.5× health, enhance/summon/promote, hammer/dash telegraphs, damage and squash recovery |
| `reform_skills_test` | vulnerability, spirits, clones, ritual circle, growth, and their later-tier interactions |
| `new_relics_test` | 13 added relics, shop VIP purchase/cap, color shield, revolver, travel rewards, soul blade |
| `arena_wall_test` | doubled arena, player soft edge, enemy crossing, wall reveal, camera follow |

`tests/relics_test` has shown an occasional one-off failure followed by consecutive passes; if it fails, rerun and
inspect the printed line rather than assuming a regression. Screenshot scripts are standalone (no GUT/pytest).
`tests/screenshot.gd` modes include `styles`, `pickups`, `merchant`, `shop_full`, `pause`, `shotgun`, `wall`, plus
`pause_build` / `pause_relics` / `pause_settings` / `pause_quit` for the populated pause-menu pages.

## Change checklist

1. Read `HANDOFF.md`; check `plan.md` / `docs/HISTORY.md` for prior decisions.
2. Add scripts/resources → run the headless editor import; add tests for new behavior.
3. Run affected suites, then all 21 headless suites listed above.
4. Update `HANDOFF.md` (current round), `plan.md` §16 if state changed, `docs/AUDIO.md` for sound
   changes, and `docs/SKILLS.md` / `docs/RELICS.md` / `docs/DESIGN_NOTES.md` for content/economy changes.
5. Keep `CLAUDE.md` lean — archive round details in `docs/HISTORY.md` instead of growing this file.
