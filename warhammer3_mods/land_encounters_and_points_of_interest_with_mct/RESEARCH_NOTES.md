# LEAPOI research notes: engine lessons from the spot events build

What we learned about the Total War: Warhammer III scripting engine while building LEAPOI spot events, Ally in Peril battles
and Battle Modifiers. The work ran on branch `leapoi-spot-events`, plus the MCT pages work that
merged as PR #20. This doc records what works, what silently does nothing, what we tried, the workaround we kept, and what is
still open.

Sources: the tester's in-game tests and script logs, code comments on the branch, and the backlog notes.
Where those disagreed, the newer code comment wins, and the conflict is called out.

**Status tags** used on every finding:

| Tag | Meaning |
|---|---|
| `[game]` | Tester saw it in game. |
| `[log]` | `script_log_*.txt` shows it. |
| `[code]` | The code or CA's docs say so. Not checked in game on its own. |
| `[untested]` | An assumption we have not checked. |

**Path shorthands:** `M/` is `warhammer3_mods/land_encounters_and_points_of_interest_with_mct/`. `L/` is `M/script/land_encounters/`.
`B/` is `M/script/battle/mod/`. `gen/` is `helper_scripts/generators/`.

**Related docs:**
- Exact signatures are in `docs/research/60-wh3-lua-api/` (start at `00-index.md`).
- The older builder-dilemma research is in `docs/research/01-synthesis.md`.
- The end-to-end dilemma UI flow is in `docs/research/40-dilemma-incident-pipeline.md`.
- Event art is catalogued in `docs/research/80-event-pictures.md`.

---

## Contents

0. The twenty things to know first
1. Campaign Lua: environment and lifecycle
2. Campaign Lua: API behaviour
3. Effect bundles and effects
4. Dilemmas, incidents, payloads, loc and tooltips
5. Allied armies and reinforcements
6. In-battle scripting
7. AI control in battle
8. Army generation
9. MCT
10. Tooling and workflow
11. Dead ends
12. Still open

---

## 0. The twenty things to know first

1. **Campaign scripts reload after every battle.**
   - Anything that is not saved is gone: manager fields, cached characters, plain Lua counters.
   - Re-find things through saved data. For example, find the ally through its saved invasion record. `[game]`
2. **Game listeners are not saved.** A battle that is pending when the game saves needs its `BattleCompleted` handlers registered again on load. `[code]`
3. **Campaign and battle talk only through svr strings.**
   - Use `core:svr_save_string` / `core:svr_load_string`.
   - Every `B/*.lua` script runs in every battle, so each one checks its own key.
   - The campaign must clear the keys after the battle. `[game]`
4. **An auto-resolved battle runs no battle script.** Missions come back "untracked", and stakes are refunded. `[code]`
5. **`owner_only` bundles are invisible on AI and allied armies.** Their stats still apply. Announce changes as battle notices instead. `[game]`
6. **Unit-set effects list the viewer's own roster in the tooltip**, even on an enemy army. Nothing hides the list, so those bundles carry a disclaimer. `[game]`
7. **Unit-class stat effects never apply.** The tooltip looks clean, but nothing changes in battle. Use the vanilla type-based unit sets. `[game]`
8. **`cm:trigger_dilemma` shows every registered choice. The dilemma builder shows only the choices given a payload.** Build every multi-choice dilemma in script. `[game]`
9. **Choice labels over about 30 characters shrink, then get cut off.** `[game]`
10. **Never start a battle before its result incident fires.** Hovering an incident while a battle is pending froze the game. `[game]`
11. **An ally only joins on the attacking side.** In ambushes and in battles we defend, the ally is left out. `[game]`
12. **The game's own ally reinforcement timer is about 90 s.**
    - It can be shortened (a bundle, or the grouped script call), but not held back.
    - At -100%, units jump to the map centre and back. `[game]`
13. **`heal_hitpoints_unary` heals TO a level, while `reduce_hitpoints_unary` takes BY an amount.** Both, and `has_attribute`, read back stale right after the call. `[game]`
14. **`trigger_projectile_launch` does nothing.** `spawn_vortex` only takes Storm of Magic keys. `[game]`
15. **Invisible units can still be targeted, and there is no "hide from the enemy only".** `[game]`
16. **The player can override any scripted order on their own units.**
    - Scripted charges on player units are pointless.
    - After a scripted change on any unit, call `release_control()`. Otherwise AI units can stay under script control. `[game]`
17. **Repeating battle timers keep firing after the battle is decided.** Remove every process at `VictoryCountdown`. `[code]`
18. **The battle API cannot change speed, charge, leadership or other stats.** Do it with a campaign bundle before the battle. `[code]`
19. **Unit experience from campaign script is ranks, not XP.** Lords take XP points. Unit ranks are silently capped at 9. `[code]`
20. **Never redeploy while the game is running.** The write fails silently, and the game keeps the pack it loaded. `[log]`

---

## 1. Campaign Lua: environment and lifecycle

### 1.1 The entry script has a private environment `[code]`
- **What happens:** with the mixer framework and pj_error_wrapping loaded, `script/campaign/mod/*.lua` sees `cm`, `core`, `out`, `random_army_manager`, `invasion_manager`, `mission_manager` and `get_mct`, but they are not in `_G`. Modules loaded with `require` run in `_G`, so they crash on their first `cm:` call.
- **Workaround:** copy each global into `_G` before the first `require` (`M/script/campaign/mod/land_encounters.lua:4-17`).
- **CA campaign helpers:** functions such as `get_random_ancillary_key_for_faction` live only in the entry script's environment. The entry script passes `getfenv(1)` to the module that needs them (game Lua is 5.1, so `getfenv` exists).
- **UI helpers:** `find_uicomponent` and `UIComponent` live in `core:get_env()`.

### 1.2 Register save/load callbacks at module load `[code]`
- `cm:add_saving_game_callback` and `cm:add_loading_game_callback` must be registered before CA's `LoadingGame` fires.
- Persistent listeners registered at module load survive the campaign -> battle -> campaign restart.

### 1.3 Campaign scripts reload after every battle `[game]`
- **Symptom:** Relief Column's reward never fired. The log said `no allied unit survived to join us` although the ally was alive. The allied force id lived only in a manager field.
- **Fix:** find the ally again through `invasion_manager:get_invasion(id):get_general()`. Find the player lord again with `cm:get_closest_character_to_position_from_faction` near the spot.
- **Rule:** anything needed after a battle must be in saved state: the saved event or delve tables, or svr strings.
- **Saving whole tables:** `battle_spot` saves its whole cached event, and the tower saves its whole `delve` table. A new field (`event.modifiers`, `delve.modifiers`) survives a load with no extra save code.
- **Plain module variables reset on every load.** The allied-army test's "next setup" counter restarted on reload, so the second setup never ran. `[log]`

### 1.4 Game listeners and some character states are not saved `[code]`
- **Pending battle at save time:** the `BattleCompleted` result listener and the floor-army cleanup must be registered again on load. Otherwise a tower floor that was pending when the game saved never resolves.
- **Frozen lords:** `cm:disable_movement_for_character` does not survive a save. The camp list is saved, and lords are frozen again in `cm:add_first_tick_callback`.
- **Timed per-turn effects** (reveals, dividends) are saved lists of `{faction, turns, ...}`, counted down at the human faction's turn start.

### 1.5 Touching the lord during the battle sequence breaks it `[game]`
- **What happens:** teleporting or killing the delving lord from a `BattleCompleted` handler leaves the game on a stale pre-battle screen.
- **Workaround:** do it from a one-shot `ScriptEventPlayerBattleSequenceCompleted` listener.

### 1.6 Changes land a moment after the call `[code]`
- Ranks, unit strengths and bundles read back straight after the call show the old value.
- To verify, log the value again from a 0.5 s `cm:callback`. Battle reads behave the same way (see 6.5).

### 1.7 Randomness and multiplayer `[code]`
- **Synced dice:** `cm:random_number(max, min)` (max first) is synced across multiplayer clients. It returns 0 for bad input.
- **Never `math.random` for anything that changes game state.** It would desync clients. In single player it is clock-seeded, so a reload rolls new numbers.
- **Deterministic order:** never trust `pairs()` order. Sort faction lists by key, and walk tiers, roles and zones in a fixed order. Check every human faction, not the local one.
- **Local-only work:** `cm:get_local_faction_name(true)` is only for UI-only work, such as greying dilemma buttons.
- **Battle side:** in battle, `bm:random_number(min, max)` is the synced call.
- **Tests:** adding a new roll shifts the random sequence and breaks seeded harness tests. A roll at chance 0 returns without calling the RNG.

### 1.8 Lua 5.1 gotchas `[code]`
- **No `goto`:** it is a syntax error in game Lua.
- **Method checks:** you cannot test whether a method exists with `:`. Write `bm.get_player_alliance_num`, not `bm:get_player_alliance_num and ...`.
- **Fractions in `%d`:** `string.format("%d", 0.5)` errors on fractions. Use `math.floor` first.
- **Require cycles:** `core/managers` cannot require `core/offer_effects`, because that module pulls `core/army`, which requires the manager back. Shared helpers go in a leaf module (`features/tower_army`).
- **No `require` in battle scripts:** `B/*.lua` are autoloaded and use no `require`. Whether a pure campaign module can be required in battle is untested.

### 1.9 World-map scans are expensive, and every multiplayer client pays for them `[code]`
- **The cost:** each treasure-site draw ran the full eligibility check on about 50 offers to show 2-3. That was about 21 walks of the region list, on the order of 100k interface calls in Immortal Empires.
- **The fix:**
  - The draw picks a weighted offer first, then checks only that one, and rerolls if it fails.
  - `nearest_regions` and `nearest_factions` walk the map once.
  - "Biggest faction" is a single-pass max, not a sort.

---

## 2. Campaign Lua: API behaviour

### 2.1 Calls that work, with the signatures that worked `[game]` / `[log]`
These were proven by the realm test (2026-10-02): each call ran under `pcall` with a list of candidate signatures, and the log recorded which one changed state.

| Call | Notes |
|---|---|
| `cm:apply_effect_bundle_to_region(bundle, region_key, turns)` | Own and enemy regions. |
| `cm:apply_effect_bundle_to_faction_province(bundle, region_obj, turns)` | Own and enemy provinces. |
| `cm:apply_effect_bundle(bundle, faction, turns)` | Also works on another faction. |
| `cm:add_development_points_to_region(region_key, n)` | Enough to upgrade afterwards. |
| `cm:instantly_set_settlement_primary_slot_level(settlement, level)` | 1-based: read-back 1 -> 2 matched the UI. Cap 5 for a province capital, 3 for a minor settlement. |
| `cm:heal_garrison(region:cqi())` | Ran without error. No read-back is possible, and the effect itself was never proven. |
| `cm:make_region_visible_in_shroud(faction, region_key)` | Takes no duration, so the reveal is applied again at each turn start. Never proven on a shrouded region. |
| `cm:apply_dilemma_diplomatic_bonus(a, b, steps)` | Steps from -6 to +6. Works between two non-player factions. See 2.3. |
| `cm:force_attack_of_opportunity(attacker_cqi, target_cqi, is_ambush)` | Starts every encounter fight: ambush, interception, relief column (ally attacks) and allied attack. |
| `cm:set_unit_hp_to_unary_of_maximum(unit, 0..1)` | Strength carries into battle: 782 of 1562 men at 50%. |
| `cm:teleport_to` + `cm:find_valid_spawn_location_for_character_from_position(faction, x, y, same_region, radius)` | The second call returns `-1, -1` on failure. |
| `cm:add_agent_experience(lookup, n[, true])` | XP points, or levels with `true`. |
| `cm:add_experience_to_unit(unit, n)` | Adds RANKS, silently capped at 9. |
| `cm:grant_unit_to_character`, `cm:treasury_mod(faction, gold)` | `treasury_mod` shows no message to the player. |
| `cm:show_message_event_located(...)` | Located event-feed message. Image id 1017. Loc-only (three loc rows, no DB). |

### 2.2 Units take ranks, lords take XP `[code]`
- **The limit:** the unit call grants ranks only. "+1000 XP" on units cannot be built, so unit rewards are ranks.
- **Rank grants:** they go through `tower_army.rankable_units(general_cqi, ranks, cap)`, which caps at rank 9. That keeps the log honest about what was actually granted.
- **Lords:** lords and heroes sit in `force:unit_list()` with `unit_class() == "com"`. Identify them that way, never by `_cha_` in the key.

### 2.3 Relations come in uneven steps `[log]`
- **What we saw:**
  - A +3 step between the player and the Empire moved standing 1 -> 21.
  - A -3 step between two other factions moved it -98 -> -128.
  - A designed "+20" logged as `+2`.
- **Reading:** vanilla gifts give +10/+20/+30, so one step is about 10, but the scale is not symmetric.
- **What the text does:** offer text says "better / worse relations" or uses the step value. Nobody has checked the attitude tooltip number.

### 2.4 Other API behaviour `[code]`
- **Already at war:** `FactionLeaderDeclaresWar` never fires between factions already at war, for example on a tower's second floor. Check `faction:at_war_with(other)` first and engage directly if true.
- **Targeting an invasion:** `invasion:set_target("CHARACTER", ...)` sets a movement target only. War needs `cm:force_declare_war(a, b, false, false)`, and the ally needs its own declaration too.
- **Fresh invasion generals:** a newly spawned invasion general is not ready at once. Traits and names go on 0.1 s after the `start_invasion` callback, and war is declared at 0.5 s.
- **Subtype-only generals:** a general created from a subtype alone gets a random name, even a legendary lord. Fix it with `cm:change_character_custom_name`.
- **Immortal lords:** killing an immortal lord (`cm:kill_character_and_commanded_unit`) wounds them instead.
- **Removing units:** `cm:remove_unit_from_character` removes by key, and the game picks which copy goes. Read the other copies' strengths first and restore them.
- **Silent removal of scripted forces:** mute `diplomacy_faction_destroyed` and `wh_event_category_character` with `cm:disable_event_feed_events`, kill the force, then unmute after 1 s.
- **Who won:** read `cm:pending_battle_cache_faction_is_attacker/defender` and `pending_battle_cache_attacker/defender_victory`.
- **Incidents:** they are fired only when `faction:is_human() and cm:is_human_factions_turn()`.
- **Garrisons:** a garrison is `region:garrison_residence():army()`. Null-check it.
- **Casters:** `character:is_caster()` exists. Walk `force:character_list()` for the lord plus embedded heroes.
- **Unit display names:** use `common.get_localised_string("land_units_onscreen_name_" .. key)`. It returns `""` when the key is missing.
- **Battle map:** the map comes from where the battle is fought. `set_battle_details_override_for_region` and scripted catchment tags had no effect `[game]`. The tower teleports the lord beside a random encounter spot before each floor.
- **Loaded packs:** `io.open("used_mods.txt")` works from script and lists the loaded packs.

---

## 3. Effect bundles and effects

### 3.1 `owner_only` hides a bundle on any army we do not own `[game]`
- **Scope:** every LEAPOI bundle is `owner_only = true`. On an AI or allied army the player cannot see it, even in battle.
- **The test:** a copy with `owner_only = false` (`land_enc_effect_ally_test_war_rites`) became visible on the ally. Its +10 melee attack, melee defence and leadership applied.
- **Still open:** whether the `owner_only` version also applies its stats on an AI army was never checked directly. Every enemy debuff relies on it.
- **Stat display:** on another army's unit, a bundle's stats show under "Other" in the stat tooltip, not under the bundle's name. The objectives panel and banners list only the player's own army's effects.
- **Workaround:** announce ally and enemy changes as battle notices (see 4.9).

### 3.2 Unit-set effects list the viewer's own roster `[game]`
- **What happens:** a bundle with a unit-set effect (for example `wh3_dlc27_effect_force_stat_speed_cavalry_chariots`) on the enemy fills its "units that will receive bonuses" list from the viewing player's roster. Boris's units showed on a Khorne army's bundle. It is UI only: the effect still applies to the army carrying the bundle.
- **Tried, did not hide the list:**
  - the `army_to_army_own_unseen` scope (as on Tomb Kings stance bundles);
  - `owner_only`.
- **Final:** keep the vanilla effects and add a paragraph to the bundle description: "The units listed below come from your own roster, but only this army's units are affected."
- **Which bundles need it:** only bundles with a unit-set effect show a list. Ability-grant bundles show none, and on our own army an `all_units` list is correct anyway.

### 3.3 Unit-class stat effects never apply `[game]`
- **What we tried:** our own effects through `effect_bonus_value_unit_class_stat_modifiers_junctions` on `cav_shk`, `cav_mel`, `cav_mis` and `chariot`, using `mod_speed_scalar` and `mod_charge_bonus`.
- **Result:** the tooltip was clean, but Bretonnian Yeomen stayed at their vanilla 9.2 m/s.
- **Vanilla:** the only vanilla row of that table is attached to nothing, so CA never used it.
- **Monsters:** monsters share class `inf_mel`, so there is no class route for them either.
- **Shipped instead:** the vanilla type-based effects:
  - `wh3_dlc27_effect_force_stat_speed_cavalry_chariots`: Wolf Raiders ran 9.2 -> 7.8 m/s at -15.
  - `wh3_dlc27_effect_force_stat_charge_bonus_cavalry_chariots_add`.
  - The `cavalry_chariots` set matches by unit type, so modded riders are covered.
- **Conflict:** older backlog notes still say the class route shipped. The code comment in `gen/leapoi_tower_offer_text.py` is newer and correct.

### 3.4 Vanilla "all X" effects can be name lists `[code]`
- `wh2_twa03_effect_leadership_all_monsters` lists 135 named vanilla units, so it misses modded monsters.
- The type-based sets `caste_monsters`, `infantry_monstrous` and `cavalry_chariots` do cover modded units.

### 3.5 Granting abilities and attributes by bundle `[game]`
- **Recipe:** three rows.
  - An `effects_tables` row (category `battle`).
  - A `unit_set_unit_ability_junctions` row (ability key, unit set `all_units`).
  - An `effect_bonus_value_unit_set_unit_ability_junctions` row with bonus value `enable`.
- **Vanilla all-unit versions exist** for Frenzy, Berserk, Feasting on Fear and Pleasure Through Pain.
- **Our own versions** cover 8 more: regeneration, deathblow, strength_in_numbers, cloud_of_flies, aura_of_immolation, too_horrible_to_die, gorefeast, unholy_vigour.
- **Pick passives:** Killing Blow is an active ability, so every unit would get a button. Use the passive Deathblow.
- **Attribute effects:**
  - `wh3_main_effect_attribute_enable_silenced_enemy` (scope `force_to_force_own`, on the army being silenced).
  - `wh_main_effect_attribute_enable_immune_to_psychology`.
  - `wh3_dlc27_effect_attribute_enable_glorious_charge_cavalry_chaiots` (the typo "chaiots" is in the vanilla key).
  - `wh_main_effect_force_stat_enable_magic_attacks`.
- **Army abilities:** bundles can enable them, for example `wh3_main_effect_army_ability_enable_storm_of_fire`. CA's Changeling quest battle grants one by bundle, then the battle script fires it with `army:use_special_ability(key, pos)`. Its button shows on the owner's bar, so the owner, or the AI, can fire it too. We never built this route. `[untested]`

### 3.6 The reinforcement-time effect `[game]`
- **The effect:** `wh3_main_effect_own_reinforcement_time_percentage_mod` (scope `force_to_force_own`), shown as "Battle reinforcement time: %+n%".
- **Where it goes:** it changes when that army's reinforcements arrive, so it goes on the battle's main army. That is the ally in a relief column, and the player when we attack with an ally.
- **Vanilla uses:** -95% instant reinforcements, -50% on Kairos, +500% on Neferata.
- **Our results:**
  - At -50% the countdown stayed accurate.
  - At -100% every unit came in within 15 s, but some jumped to the map centre and back (see 5.5).
- **Silent:** applying or removing a bundle from script raises no campaign notification, so a one-battle bundle needs no suppression.

### 3.7 Other bundle facts `[code]` unless tagged
- **Duration:** `apply_effect_bundle_to_force(bundle, cqi, 0)` lasts until removed. One-battle bundles are removed in `BattleCompleted`, so a restarted battle keeps them. Removing an absent bundle does nothing.
- **Enemy bundles** are applied when the invasion general spawns (`weaken_invasion_force`). Ally bundles go on in `prepare_ally_force` with duration 1. Both carry into battle `[game]`.
- **Winds of Magic reserve:** it needs `wh3_main_effect_winds_of_magic_pool_min` and `_pool_cap` together, at the same value.
- **Garrisons:** no vanilla effect changes garrison size. The scope `region_to_force_own_regionwide_if_garrison` buffs a region's garrison. An enemy garrison is weakened by script with `set_unit_hp_to_unary_of_maximum`.
- **Scopes in use:**
  - `force_to_force_own`, `faction_to_force_own`, `faction_to_faction_own`, `faction_to_region_own`;
  - `region_to_force_own`, `region_to_province_own`, `province_to_province_own`, `province_to_region_own`;
  - `character_to_force_own`.
  - No scope filters by unit type. Narrowing must come from the effect's unit set.
- **Name colour:** a bundle's name colour in an incident is not set by effect order. Reordering Dishonor's effects to put the penalty first changed nothing `[game]`. There is no positive/negative field.
- **Display-only effects:** a custom effect with no bonus-value junction shows a number (dividends income) while the script pays the gold.
- **Number format:** effect values in TSVs are floats (`25.0000`). Search with that format.
- **Difficulty tiers:** effects that vary by difficulty are separate keys (`<key>_easy/_medium/_hard`). If Lua asks for a key the generator never wrote, the game silently has no bundle, so the generator fails on any missing referenced bundle.
- **Old rows:** when an offer moves to another bundle family, delete the old rows. A dead `land_enc_effect_tower_dividends` sat in the pack.
- **Description text:** the bundle description renders above the effect lines. Keep it flavour, and put exact numbers in the battle notice.

---

## 4. Dilemmas, incidents, payloads, loc and tooltips

### 4.1 `trigger_dilemma` vs the dilemma builder `[game]`
- **The bug:** 31 offer choices were registered on every battle dilemma. `cm:trigger_dilemma` then showed all 31 as blank buttons on the plain dilemma.
- **Why:** a dilemma fired from the DB shows every registered choice. A builder dilemma (`cm:create_dilemma_builder`, `builder:add_choice_payload(choice, payload)`, `cm:launch_custom_dilemma_from_builder`) shows only the choices given a payload.
- **Fix:** every battle dilemma is built in script. One dilemma key can then show a different subset of choices each time.
- **Lesson:** forcing offers in every test hid this, because the offer version was always the one tested.

### 4.2 Choice order, routing and labels `[game]`
- **Order:** the vanilla `FIRST` choice always sorts first. That pins the signature offer to the top, and an ineligible one leaves no blank button. The rest follow the `order` column of `cdir_events_dilemma_choices_tables` (Avoid 999, Walk away 998).
- **Routing:** route choices by key, never by index.
- **Label length:** labels over about 30 characters shrink, then get cut off. A harness test enforces 30.
- **Restacking:** taking a mission pays its stake, greys it as "Already taken." and relaunches the same dilemma, so missions stack before Fight.

### 4.3 Greying out choices `[game]`
- **The engine does not disable an unaffordable choice.**
- **How we grey them:**
  - Find the row under `events > event_layouts > dilemma_active > dilemma > background > dilemma_list`. Its id is `CcoCdirEventsDilemmaChoiceDetailRecord` + dilemma key + choice key.
  - On its `choice_button` child, call `SetState("inactive")` and `SetDisabled(true)`.
  - Run it from `PanelOpenedCampaign` (`context.string == "events"`) after a 0.1 s callback, so the panel exists.
- **UI only:** a greyed choice clicked anyway still reaches the script. The handler keeps a fallback: a site reopens, and a battle starts as it is.

### 4.4 Payloads and text lines `[game]`
- **Builder calls:**
  - `cm:create_payload()`, then:
    - `treasury_adjustment(gold)`;
    - `faction_ancillary_gain(faction, key)`;
    - `add_unit(force, key, count, xp)`, which shows a unit card and the unit joins;
    - `text_display(component)`;
    - `effect_bundle_to_force(force, bundle)`;
    - `clear()`.
  - Item cards render before text lines.
- **Line rows:** each `text_display` line needs a `campaign_payload_ui_details_tables` row (component, icon `ui/campaign ui/effect_bundles/<icon>`, `default`, 0) plus the loc `campaign_payload_ui_details_description_<component>`.
- **Line exists?** Check with `common.get_localised_string(...) ~= ""`. Note that the harness mock always returns text.
- **Colours:** red marks a cost, green a gain, and yellow a caution ("This may have unforeseen consequences." under Do nothing).
- **Shared lines:**
  - The vanilla line `dummy_wh2_dlc11_neo_counter_fight_chance` ("You may have to defeat a foe in battle", casualties icon) is reused on every offer that leads to a fight.
  - One shared red "We cannot afford this." row replaced 123 per-offer rows.
- **Extending vanilla choices:** a new DB payload row can add a line to an existing vanilla choice.

### 4.5 Rows a script-built dilemma still needs `[game]`
- A `dilemmas_tables` row with `ui_image`, `Event` and `UI_CAM_EVENT_Dilemma`.
- Option junctions `GEN_TARGET_NONE`, `VAR_CHANCE 100` and `VAR_FOLLOWUP_CHANCE 100`.
- One `FIRST` payload, `TEXT_DISPLAY LOOKUP[dummy_do_nothing]`.
- Loc for the title and description.
- **Per choice:** a choice row with an order, a `cdir_events_dilemma_choice_details` row, and the label loc `cdir_events_dilemma_choice_details_localised_choice_label_<dilemma><choice>`.
- **Row ids:** new ids continue fixed ranges.
- **Tower rows are hand-kept:** about 43 floor rows per choice. Spot rows are generated.

### 4.6 Incidents built in script `[game]`
- **Calls:** `cm:create_incident_builder(key)`, `set_payload`, `add_target("default", character)`, `cm:launch_custom_incident_from_builder(builder, faction)`.
- **DB rows:** each key still needs an `incidents` row, the `GEN_TARGET_NONE` and `VAR_CHANCE 100` junctions, and title and description loc.
- **Failure handling:** wrap the build in `pcall`. If it fails, grant the rewards in script and show the old message.
- **Payload replacement:** a builder payload replaces the incident's DB payload, so its DB gold is lost. The generator mirrors each victory incident's gold into `L/configs/victory_gold.lua`, and the script adds it back. Lua cannot read payload values at runtime.
- **Lord target:** tying a victory incident to the player's lord keeps his portrait. The `GEN_TARGET_MODEL` lord target was dropped on result incidents, as a precaution against silent failure (never tested).
- **Event-feed messages have no payload area,** so no cards or effect lines. Use an incident when results need cards.

### 4.7 Never start a battle before its incident `[game]`
- **What happened:** Wake the Guardian started its battle at 45.8 s and fired its result incident at 47.0 s. Hovering that incident froze the game.
- **Fix:** fire the incident first, then start the battle with `cm:callback(..., 0.5)`. The root cause is inferred from timing, and 0.5 s is a guess.

### 4.8 Live text in loc through context values `[game]`
- **Dilemma loc:** `{{CcoCampaignEventDilemma:ScriptObjectContext("key").StringValue}}` reads a value set with `common.set_context_value(key, string)` before launch.
- **Incident loc:** the same pattern uses `CcoCampaignEventIncident`. Vanilla Archaon incidents do this.
- **Values are global and read live:**
  - An old event in the feed shows the latest value. The tower also sets per-floor keys for this reason.
  - A plain dilemma must clear the value, or the last battle's missions show again.
- **One slot per description:** each description has one slot, so the "Modifier:" lines and the taken missions are joined into it. Lines are joined by `\n`, with `\n\n` after the block when it has lines.

### 4.9 Battle notices are scripted objectives `[game]`
- **Rows:** each notice is a `scripted_objectives_tables` row `land_enc_tower_buff_<name>` (objective line) plus `<name>_message` (banner), with loc `scripted_objectives_localised_text_<key>`.
- **Difficulty variants:** they get a `_<difficulty>` suffix, which the battle script strips to find the handler. Don't name a key that really ends in `_easy`/`_medium`/`_hard`.
- **Icons:** an icon path that does not exist renders as a plain horizontal line. Check icons against `bundle_icons.txt` from ui.pack. `mount.png` and `icon_stat_defence.png` exist.
- **Colour:** harmful notices show red and helpful ones green.

### 4.10 Loc formatting `[game]`
- **Line breaks:**
  - In a loc TSV, write `\\n` (two backslashes), and `\\n\\n` for a paragraph.
  - A single `\n` prints literally. A real newline splits the row (12 orphan half-rows once).
  - In Python source it is `"\\\\n"`.
- **Markup:** colour is `[[col:yellow]]...[[/col]]`. An inline icon is `[[img:ui/skins/default/icon_stat_attack.png]][[/img]]`.
- **Locations:** a region name in a line is `regions_onscreen_<key>`, and an item name is `ancillaries_onscreen_name_<key>`. One name per line.
- **Numbers:** loc cannot follow script numbers. "N turns left" needs one row per value (Smithy rows 1-35), and a hard-coded maximum silently breaks if a slider range grows.
- **Two copies of timings:** about 25 timings appear in both text and Lua constants, and nothing checks they agree. Prefer placeholders filled from config.
- **Format strings:** templates passed through `string.format` need `%%` for a literal `%`.
- **House style (vanilla-led):**
  - "1500 gold" (no separator).
  - Title-cased names.
  - Item tiers "Unique" and "Crafted".
  - No trailing colon above a unit card.
  - Timers in minutes when they convert cleanly.
- **Files:** new loc files copy an existing header so RPFM packs them the same way, and appended rows match the file's CRLF.

### 4.11 Event art `[game]`
- **Where it is set:** the `ui_image` column of `dilemmas_tables` / `incidents_tables`.
- **Where the files live:** PNGs are at `ui2.pack/ui/eventpics/<culture>/<name>.png`. Animated twins are at `movies_ev.pack/movies/eventpics/<culture>/<name>.ca_vp8`.
- **Per-culture art:** `land_victory`, `army_morale_up`, `messenger` and `faction` have a version in every playable culture, so each player sees their own.
- **Fallback:** vanilla rows prove that a bare name falls back to `all/`.
- **Avoid:** `all/story_panels/dlc25_nemesis_crown`. It is placeholder art with a magenta "PH".
- **Catalogue:** see `docs/research/80-event-pictures.md`.

---

## 5. Allied armies and reinforcements

### 5.1 An ally only joins when its side attacks `[game]`
- **The test (`ambush_ally`):** a generated ally spawned right beside the player. The `PendingBattle` showed no secondary defenders, so only the ambushers and the player fought.
- **Likely reason:** the ally shares a war with the enemy but has no alliance with us. Joining an attack only needs a shared enemy. `[untested]`
- **Consequence:** every allied battle is our attack, or the ally's. "Ambushed on the Road" became "Turn the Tables", where we strike first with the escort.
- **How we checked:** a `PendingBattle` listener logging `attacker()`, `defender()`, `secondary_attackers()` and `secondary_defenders()` is the reliable way to see who joins.

### 5.2 Two working shapes `[game]`
- **Side by side:**
  - We attack with the ally spawned next to us. The ally is a secondary attacker.
  - On the game's own timer, all its units march in from the map edge 75-90 s after the start.
- **Relief column:**
  - Our lord moves about 6 hexes back, and the ally attacks the enemy (`force_attack_of_opportunity(ally, enemy, false)`).
  - The ally deploys and starts the fight, and we arrive as its reinforcement (105-135 s on the game timer).
  - The ally's starting strength is set after spawn: a random 50%, 75% or 100%.

### 5.3 Allies are generated, under stand-in factions `[code]`
- **Never real armies:** allies are spawned by the invasion manager, under quick-battle `_qb1` factions.
- **Relations rewards** therefore go to the nearest living real faction of the ally's culture that is not at war with us (gold if none).
- **War declaration:** the encounter faction must `force_declare_war` on the ally's faction, or the ally does not fight.
- **When the faction is picked:**
  - Normally at battle start, so a dilemma cannot name a lore composition for an ally.
  - Allies in the Dark rolls the faction when the offer is drawn (`alliances.pick_for_subculture`), to name its theme.
  - `Army:new_from_event` demotes the battle to an interception when no ally faction is available. Ally notices must be set after `generate_battle`, behind `has_ally_reinforcements()`.

### 5.4 The game's reinforcement timer is short and cannot be held back `[log]`
- **The test:** Signal Fires wanted a 3-unit band at 3:00. The log had all 3 units on the field by about 90 s. The feature was dropped.
- **Lesson:** script can bring reinforcements in earlier, but not later.

### 5.5 Shortening the timer `[game]`
- **Two tools:**
  - A bundle on the main army (3.6). It is accurate up to -75%. At -100% units jump to the map centre and back.
  - The grouped script call. `land_enc_ally_arrives_now` (svr) holds the ally's faction key, and the battle script calls that army in at `Deployed` with `sunit:deploy_reinforcement(true)`.
- **Grouped call details:**
  - Groups of 4, polled every 500 ms, with a 15 s timeout per group.
  - Use "on the field" (deployed, routing or dead), so a unit that dies on entry does not hold its group.
  - It also works on the player's own reinforcing army. That is how Relief Column brings us in 20 s after the enemy reaches the ally, at 90 s at the latest.
- **What ships:** every allied battle rolls a cut of 0/25/50/75/100% with `random_number`. 25-75% uses `land_enc_effect_spot_reinforcement_time_<n>`, and 100% uses the grouped call. The roll itself is untested in game.
- **Timing rules:**
  - Reinforcements cannot enter while the deployment clock is paused, so call them from `Deployed`.
  - The game's own entry replaces an attack order given right after the last group is called. Wait 5 s before ordering.
  - Allied battles also need the MCT toggle "Allied reinforcement battles" (off by default).

### 5.6 Reaching reinforcement units in battle `[code]`
- A plain `bm:get_scriptunits_for_army(alliance, army)` misses reinforcement sets.
- Loop `r = 1 .. bm:num_reinforcing_armies_for_army_in_alliance(alliance, army)` with `get_scriptunits_for_army(alliance, army, r)`.
- A Relief Column copy without the loop never saw the marching units.

### 5.7 After the battle `[game]`
- **Survivors:** read the allied invasion general's `military_force():unit_list()` in `BattleCompleted`, before the encounter's forces are removed. Find the general through the saved invasion record (1.3).
- **Reward:** one surviving unit joins us if the allied lord lived and we have room. The incident shows it as a unit card.

---

## 6. In-battle scripting

### 6.1 The campaign-to-battle hand-off `[game]`
- **Into the battle:** the campaign writes comma lists or `key=value` pairs with `core:svr_save_string`. The battle reads them with `core:svr_load_string`. Keys:
  - `land_enc_tower_battle_buffs`: notice, trick and modifier names;
  - `land_enc_tower_mission_targets`: e.g. `divine_shield=420`;
  - `land_enc_tower_night_terrors`;
  - `land_enc_ally_arrives_now`;
  - `land_enc_relief_column`;
  - `land_enc_ally_test`.
- **Back out:** results return as `key=met|failed` in `land_enc_tower_mission_results`, and kill counts in `land_enc_tower_rival_kills`.
- **Every `B/*.lua` runs in every battle.** A key left over from an unfought battle can leak into the next one, so:
  - the campaign clears keys after the battle;
  - risky data is tied to something checkable, such as "only AI armies of this faction".
- **Cost:** an empty key costs one `svr_load_string`, and the script returns.
- **One source for numbers:** pass them as `key=value` rather than duplicating config in the battle script. A copied `DIVINE_SHIELD_MS` table drifted.
- **Tricks fire by name:** `TRICKS[base_name(name)]` runs for every received name, bundle names included. Renaming a bundle can silently drop a trick.

### 6.2 Battle script structure `[code]`
- **Entry:** register `bm:register_phase_change_callback("Deployed", fn)`. Inside it:
  - build script units for the player alliance (filtered on `army:is_player_controlled()`) and the enemy alliance;
  - set objectives and banners;
  - dispatch each name to its handler under `pcall`, so one failure is logged and the rest run.
- **Phases:** "Deployment", "Deployed" (battle start) and "VictoryCountdown" (battle decided).
- **Banners** queued during deployment play before the fight. Queue them from "Deployed".
- **Objectives and banners:**
  - `bm:set_objective(key[, a, b])`, where a and b show as live counters.
  - `complete_objective`, `fail_objective`, `remove_objective`.
  - `bm:queue_help_message(key, ms, fade_ms)`.
  - Several banners play one after another, so keep them short: 2 s plus a 1 s fade `[game]`.
- **Timers:**
  - `bm:callback(fn, ms[, name])`, `bm:repeat_callback(fn, ms, name)`, `bm:remove_process(name)`.
  - Wrap every timed step in a `pcall` helper (`safe`, `after`, `every`) that logs `"<name> failed: ..."`.
- **Stop timers at the end:** processes keep firing after the battle is decided (teleports, vortexes and polling ran on into the victory countdown). Collect every process name and remove them all in one `VictoryCountdown` callback.
- **One script per unit state:**
  - Each `script_unit:new` gets its own unit controller. Two scripts wrapping the same units can undo each other: `morale_behavior_default` undid Oath of No Retreat, and a timed end to invincibility undid Divine Shield.
  - All modifier handlers were merged into `land_enc_tower_buffs.lua`, so each unit state has one owner.
  - `keeps_out` stops conflicting offers from being drawn.

### 6.3 Health: heal TO, drain BY `[game]`
- **Heal:**
  - `unit:heal_hitpoints_unary(0.1)` heals TO 10%, so units above 10% did not change (26% -> 26%, 61% -> 61%).
  - Heal to `min(1, current + share)`, skip units at full strength, and pass `true` (`allow_resurrection`) so fallen men return.
- **Drain:** `unit:reduce_hitpoints_unary(share)` takes BY the share. At 1% a tick, a cannon went 100% -> 92% over 8 ticks.
- **Kill aura:** CA has `script_units:start_kill_aura(targets, range_m, share_per_s)`, which also hits routing units. Grim Presence uses its own loop instead (25 m, 0.5% a bite).

### 6.4 Attributes `[game]`
- **Calls:** `sunit:set_stat_attribute(key, bool)` sets one unit. `bm:set_stat_attribute(key, bool)` sets every unit. CA turns attributes off mid-battle too.
- **Use the DB keys, not the doc list:** the battle_unit doc's attribute list does not match `unit_attributes_tables`.
  - The doc has `fire_while_moving` and `run_amok`, which are not in the DB.
  - The DB has `silenced`, `glorious_charge` and `revealed`, which are not in the doc.
- **Keys used:** `causes_terror`, `cant_run`, `strider`, `fatigue_immune`, `rampage`, `mounted_fire_move`, `shoot_disabled`, `expendable`, `unbreakable`, `stalk`, `hide_forest`, `unspottable`.
- **Native traits:** skip units that already have the attribute in their DB data, so turning it off later does not strip a native trait.
- **In game:** attribute icons appeared on unit cards, and Terror worked. Each attribute's gameplay effect was not checked one by one.
  - `cant_run` let the tester run at the very start of a battle.
  - `mounted_fire_move` on foot archers is unconfirmed.

### 6.5 Read-backs are stale `[log]`
- `unit:has_attribute(key)`, heal and drain values read straight after the call return the old state. The logs said "93% -> 93%" and "set on N units, 0 report it".
- Log the intended value, or read again about 1 s later. Do not use an instant read-back as proof.

### 6.6 Teleports `[game]`
- **The call:** `sunit:teleport_to_location(pos, bearing_deg, sunit.unit:ordered_width())`. It works on units in melee too. In game, no unit got stuck, with 0 errors over many teleports.
- **Finding a spot:**
  - `get_position_near_target(pos, min, max)` can return an unreachable spot, so check `unit:can_reach_position(spot)` and retry.
  - For "behind their line", use `position_along_line(their_centre, our_centre, -80, true)`, then `battle:is_area_clear`, because it can land off the map.
  - There is no getter for map bounds or deployment zones. Spawn zones (`bm:reinforcements():spawn_zone(i):position()`) are the nearest thing.
- **No effect call at a position:** composite scenes play only at their baked positions. A real teleport effect would need an ability on every unit card.
- **Workaround:** hide the unit (`set_invisible_to_all(true, false)`), teleport, `release_control()`. After 1 s, show it and `add_ping_icon(nil, 3000)` over the landing spot. Wrap UI calls (ping, `highlight_unit_card`) in `pcall`. Lost in the Warp takes a unit out with `set_enabled(false)` and returns it with `set_enabled(true)`.
- **Fairness:**
  - Each repeating picker keeps its own "moved this round" list. One shared list let Scattered Ranks mark every enemy at the start, so Warp Shift only flung player units for 15-20 minutes.
  - Mission-marked units are never moved.
  - `track_missions` must run before `play_modifiers`, so marks exist first.
  - Only one teleport modifier rolls per battle.
- **Load:** Scattered Ranks runs up to 5 reachability checks per enemy unit in one frame. That was not measured. `[untested]`

### 6.7 Visibility `[game]`
- `set_invisible_to_all` hides a unit from everyone, but it can still be targeted and shot. There is no per-alliance visibility.
- `set_always_visible(true)` reveals units.
- The closest thing to hiding is `stalk` + `hide_forest` + `unspottable`, and no attribute hides units in the open.

### 6.8 Spells, storms and projectiles `[game]`
- **Vortexes:**
  - `bm:spawn_vortex(key, pos, dir_vec)` only takes Storm of Magic vortex keys: `tornado_base`, `supernova_base`, `barrier_base`, and the `tornado_upgrade_1..3` tiers.
  - Normal spell keys spawn nothing, with no error.
  - There is no way to set a duration or end a vortex early, and which side it hurts is up to the vortex. Only frequency, distance and tier can be tuned.
  - Storms within 30 m of a unit were "devastating". They now land 60-120 m away, every 3 minutes.
- **Projectiles:** `bm:trigger_projectile_launch(key, from, to)` does nothing. 4 lightning strikes, 12 shells and 1 comet were logged with 0 errors, but nothing appeared. CA never calls it, and an ownerless projectile seems never to launch.
- **Winds:**
  - `army:modify_winds_of_magic_current(n, true)` changes the spendable bar, and `modify_winds_of_magic_reserve(n)` changes the reserve. Negative values worked for Drained Winds.
  - The enemy pool is not set up at "Deployed", so wait 2 s.
  - `winds_of_magic_current()` can error, so wrap it in `pcall`.

### 6.9 Morale, invincibility, respawn, ammo `[code]` unless tagged
- **Morale:**
  - `morale_behavior_fearless()`, `_rout()`, `_default()`, `fearless_until_casualties(0.5)`.
  - There is no numeric leadership, no forced waver and no forced berserk.
  - A routed unit can rally, so missions remember beaten units instead of re-checking `is_routing()`.
- **Invincibility:** `lord:set_invincible(true)`, then `release_control()`.
- **Respawn:**
  - `sunit:respawn_in_start_location(true)` respawns at the pre-deployment position, at full strength.
  - Save positions at "Deployed" and call `unit:respawn(pos, bearing, width)`, then `reduce_hitpoints_unary(1 - strength)`.
  - "Gone" means no men left, or routing/shattered and `not unit:is_valid_target()` `[game]`.
- **Ammo:** `cache_ammo()` + `set_current_ammo_unary(0)`, then `restore_cached_ammo()`. Also `grant_infinite_ammo()` and `starting_ammo()` (0 for units with no ammo). Wet Powder was never seen in game, because the enemy never got into range at the test timing.
- **Fatigue:** `change_fatigue_amount(unary)` multiplies the current fatigue, so pass 0.01, never 0. It cannot tire a fresh unit.
- **Not possible at runtime:** spawning units, granting abilities, weather or fog, setting stats, and moving units between armies (`army:change_faction` is whole-army only).

### 6.10 Useful queries `[code]`
- **Unit worth:** `unit:strategic_value()`. Battle scripts cannot read unit cost.
- **Unit state:** `fast_speed()` (real m/s, which shows bundle slows), `number_of_enemies_killed()`, `initial_number_of_men()`, `number_of_men_alive()`, `unary_hitpoints()`, `is_shattered()`, `is_routing()`, `is_commanding_unit()`, `is_deployed()`, `is_in_melee()`.
- **Unit type:** `unit_class()` ("com", "mon", "minf" ...), `is_cavalry()`, `is_chariot()`, `is_war_beasts()`.
- **Armies:**
  - `bm:get_player_alliance()` / `get_non_player_alliance()` (and `_num`).
  - `army:is_player_controlled()` and `army:faction_key()` split the player's alliance.
  - `bm:alliances():item(id):armies()`.
- **Start position:** `script_unit:new` saves `start_position`, `start_bearing` and `start_width`.
- **Classification must match the campaign check:** a campaign check that counted `monstrous_cavalry` gave Monster Slayer to armies the battle could not hunt.
- **Logging:** `bm:out` and `out` both land in `script_log_*.txt`. One battle can span two log files, and the enemy makeup is in the campaign log written just before the battle.

---

## 7. AI control in battle

### 7.1 Use per-unit attack orders, not CA's planner `[game]`
- **The planner:** units given to CA's attack planner went to the side of the enemy line and waited in cover.
- **What works:** `sunit:start_attack_closest_enemy(5000)` on each unit, which re-picks the closest foe every 5 s.
- **Handing back:** on melee contact or a timeout, call `stop_attack_closest_enemy()` + `release_control()`, and the units return to the battle AI.
- **Shared helper:** `attack_until_contact(name, attackers, targets, delay_ms, timeout_ms, on_contact)` in `B/land_enc_ally_reinforcements.lua`. It keeps only fighting units and stops when either side has none left.
- **Timeouts:** attack orders last at most 180 s, or 90 s for a relief column's enemy, then the units go back to the battle AI.

### 7.2 CA helpers that misbehave here `[code]`
- `has_deployed` turns false while a unit hides in cover. Use `sunit.unit:is_deployed()`, or routing/dead.
- `num_units_engaged` counts 0 for a plain list of script units. Check `is_in_melee()` on each unit.

### 7.3 Relief Column's scripted charge `[game]`
- **The sequence:**
  - At "Deployed" every enemy unit attacks its closest foe. We are still off the map, so that foe is the ally.
  - Contact came at about 55 s.
  - Our army is called in 20 s after contact, or at 90 s at the latest.
- **Charge delay:** a 3 s delay before the order made the charge look slow. The delay is now 0, and attack orders already make units run.
- **Hand back early:** hand control back once our arrival is called, or the forced orders override the AI for no reason.
- **Instant arrival:** an ally whose timer is cut by 100% is sent at the closest enemies until contact, then handed back.

### 7.4 Scripted orders on player units do not stick `[game]`
- Bloodlust ordered all 18 player units to charge, and the log showed all 18 started. Any player order cancels it. Bloodlust and Unruly Ranks were cut.
- `script_ai_planner:new(name, sunits)`, `alliance:create_ai_unit_planner()` and `alliance:force_ai_plan_type_attack/defend()` exist, but we did not use them. `[code]`

### 7.5 Always release control `[code]`
- Any unit-controller order or morale change takes script control of the unit. Without `release_control()`, the player cannot command their unit, and AI units can stay under script control.
- Last Stand's revert was missing it, and the gap was found in review.

### 7.6 Modifiers that touch the same state need conflict groups `[code]`
- Last Stand (enemy fearless), Hold Fast (resets everyone to default at its end), Grim Resolve and Panic (forced routs) all change morale behaviour.
- If Hold Fast and Last Stand rolled together, Last Stand would silently end for every enemy above half strength.
- Conflict groups keep them apart. The teleport group allows one per battle.

---

## 8. Army generation

`[code]` unless tagged.

- **Unit cap:** an army is capped at 20 units, lord and heroes included. Generated armies usually fill every slot, so "+2 enemy units" adds nothing. Bait and Switch became +25% budget at 75% strength.
- **Budget multipliers multiply:** a Bandits battle (0.8) with Bait and Switch (x1.25) logs `x1`. `[log]`
- **Costs:** Tomb Kings and most Beastmen units have `recruitment_cost` 0. Use `multiplayer_cost`.
- **RoR flags:** some mod Regiments of Renown carry no RoR flag. Also treat a key containing `_ror` as one.
- **Data quirks:**
  - War beasts (Salamanders, Razordons, Dire Wolves) sit in the cavalry role. Strip by unit type, not role. Cull the Beasts left them in when it stripped by role. `[game]`
  - Khorne has no missile infantry, missile cavalry or war machines, so it can never field a Gunline or fill a ranged spine slot.
- **Checking what a faction can field:**
  - Use the generator's own buyable filter (`army_generator.can_field`), not the raw roster. The raw roster ignores enabled origins, price > 0 and the RoR exclusion.
  - Offers check what the enemy faction can field, not the actual army. A Khorne army got Lame Their Mounts with no riders. `[game]`
- **Compositions:**
  - A composition swaps the random army recipe for a fixed one. The spine (2 frontline + 1 ranged/support) is still bought first.
  - A theme rolls only if the faction has 3 or more units of its role. Monster Horde vs Lizardmen had all six non-spine units on theme. `[game]`
- **Lore armies:**
  - 70% of unit slots are lore units, the budget is +50%, and they appear on medium/hard only.
  - Lore units cost about 1000-2600, so most hard lore armies hit the 20-unit cap with 33-70% of the budget left. Every 10% left gives +1 rank, up to +4. In 450 sampled hard armies, 316 reached +4.
  - Grave Horde had 14 of 18 units from its lore list. `[game]`
  - A strip offer can still remove the lore units. The army then builds as its fallback type, but still shows the lore notice.
- **Price cache:** the first `unit_price_by_key` call walks every faction x tier x type. Only call it when needed.
- **Item pool:** `get_random_ancillary_key_for_faction` covers every loaded mod, but can return a duplicate, an owned item or nothing. Reroll up to 5 times.
- **Debug switches skip the roll rules:** a forced lore army appears even on easy, so its rank step never ran in the test.

---

## 9. MCT

`[game]` unless tagged.

- **Locks reset on load:** MCT loads saved settings after the settings file runs, which resets every option lock. Reapply locks on `MctInitialized` and `MctPanelOpened`. For live changes, read `context:setting()` in `MctOptionSelectedSettingSet`, because `get_finalized_setting()` is stale until the panel closes.
- **Read-only text pages:**
  - The `Wiki` page type is an empty stub.
  - MCT skips a section with no options, so each guide section holds a hidden `dummy` option (`set_uic_visibility(false, false)`).
  - Section descriptions wrap to fit, and colour tags work.
  - Collapsing a section also hides its description.
  - Blank lines between guide entries look bad and were reverted.
- **Layout:**
  - Set the new default page first, then `remove()` the old one.
  - Sections fill two columns, 3 per side, in creation order.
  - There is no list widget, so long lists overflow a tooltip.
- **Where the settings file runs:** it runs in frontend, campaign and battle, so anything it requires must be safe at the main menu (pure-data configs, loc reads).
- **Option keys never change:** a rename loses players' saved values. Merging options or changing scope can reset a value once. `[untested]`
- **Sliders:**
  - `add_slider(key, section, text, tooltip, {min, max, step, precision}, default)`.
  - Read with `get_mct_settings().<key>`. Defaults live in `L/core/mct.lua`.
  - Labels are English strings in Lua, not loc.

---

## 10. Tooling and workflow

### 10.1 Redeploying `[log]`
- **Close the game first:** check for Warhammer3.exe in its own command, and stop if it is running. A write to an open pack fails silently, and the game keeps its loaded copy. The process can linger after closing.
- **From a worktree:**
  - `schemas/` is gitignored and missing in worktrees, so run from the main checkout's `helper_scripts`.
  - `MOD_SOURCE` is a module constant. Setting it as an environment variable silently packs the main checkout. Patch the constant: `PYTHONPATH=. python -u -c "import tools.redeploy_leapoi as r; r.MOD_SOURCE='../../<worktree>/warhammer3_mods/...'; r.main()"`.
- **Verify the pack:**
  - Check the pack timestamp, then `rpfm_cli pack list` or `pack extract`.
  - Check that the new files are present and every debug switch is empty.
  - Check `^db/.*\.tsv$` too. An empty `schemas/` makes `--tsv-to-binary` pack TSVs as raw text, which crashes the campaign load.
- **Script logs:** `F:/SteamLibrary/steamapps/common/Total War WARHAMMER III/script_log_*.txt`. Compare the newest log's time to the deploy time.

### 10.2 Vanilla data `[log]`
- `--tables-as-tsv` fails after a game patch until the rpfm schema is updated.
- A full vanilla db pull sits in `helper_scripts/_diag/vanilla_all/db`. Effects/abilities loc and `bundle_icons.txt` are in `_diag/vanilla_db`.
- chadvandy's page summaries lose detail. Method anchors in the raw HTML are `INTERFACEmethod`.

### 10.3 Generators `[code]`
- **Pure configs:** `update_leapoi_spot_offers.py`, `leapoi_tower_offer_text.py` and `leapoi_battle_modifiers.py` read the pure-Lua configs through one `lua -` subprocess (stdin; `lua -e code path` runs the path as a script). So `utils/steps.lua` and `configs/shared_offers.lua` must not touch `cm` or `common.lua`.
- **Idempotent:** a rerun must give byte-identical files.
- **Owning rows:**
  - Rows are owned by markers. Match markers against the key field only: a loose marker deleted the hand-made `land_enc_effect_spot_wound_owed`, and `_comp_` matched any row.
  - When an offer stops varying, its old tier rows stay unless removed.
  - A re-sort can look like lost rows. Check that the re-added rows match before panicking.
- **New tables:** `write_rows` only creates loc files. New db tables need their header made by hand.
- **Fail loudly:** the generators fail on a referenced bundle that was not generated, and on a varying notice with no text.
- **Don't import `tools.simulate_leapoi_armies`:** it runs an rpfm schema update at import.

### 10.4 Test harness `[log]`
- **Running it:** `cd tests/leapoi_harness && LEAPOI_ROOT=<worktree mod>/ sh run_all.sh`. It is local-only, with 295 tests at the end. Pointing it at the main checkout gives false failures.
- **Debug switches:** `debug_switches_off` fails while any debug switch is set. Empty them before running and before committing. Temporary short test timings also fail checks, by design.
- **Reading failures:**
  - A suite that prints nothing has crashed, so run it alone.
  - Identical failures everywhere mean a syntax error in a test file.
  - Truncated output once hid 30 failures.
- **No `luac`:** syntax-check with `lua`.
- **Limit:** the harness only fakes the engine. Its `get_localised_string` always returns text, and every API claim still needs an in-game test.

### 10.5 Editing files from the shell `[log]`
- Heredocs and `sed` repeatedly broke on quotes, `\n` and `\t`. One wrote a real newline into a TSV.
- Write patch scripts to files with the Write tool:
  - assert each anchor matches once;
  - keep CRLF where a file uses it;
  - use `chr(92)` for backslashes;
  - chain steps with `&&` so a failed anchor stops the rest.
- Anchors must be unique: `MESSAGES = {` also matched `MISSION_MESSAGES`.

### 10.6 Testing practice `[game]`
- **One in-game test per session.** A battle dilemma offers 2 offers and only one can be taken, so force one with a debug switch.
- **Use Bandits fights** to test offers, because Battlefield fights also bring an ally.
- **Force factions:** `force_battle_faction` picks the enemy faction, for example Bretonnia for cavalry.
- **Temporary timings:** test timers at 30 s, then restore before committing.
- **Debug switches** in `L/configs/debug.lua`:
  - `spot_kind`, `force_battle_categories`, `force_spot_offers`, `force_treasure_site`, `force_offers`, `battle_event_rolls`;
  - `force_battle_faction`, `force_battle_modifiers`, `battle_difficulty`, `spot_cost`, `ally_test`, `realm_test`, ...
  - They ship empty.
- **Override at the source:** apply an override where the value is stored, not at each call site. A per-call `smithy_level` override took gold for an impossible upgrade.

### 10.7 Launch crashes `[log]`
- **Rule a pack out first:** if no Lua or MCT log was written, the game crashed before any script ran, so the pack is unlikely to be the cause.
- **Stack depth:** different stack depths across crashes mean different crash classes.
- **Load order:** `used_mods.txt` shows where each pack loads from.
- **Low memory:** "paging file is too small" errors appear while the game holds most of the RAM.
- **Keep the evidence:** save artifacts under `debugging/<date>-<scenario>/`.

---

## 11. Dead ends

| Tried | What happened | Replaced by |
|---|---|---|
| `bm:trigger_projectile_launch` for strikes and barrages | Runs, nothing appears `[game]` | Cut: Falling Star, Skyfire, Doomed Ground, Friendly Guns, Enemy Bombardment |
| `spawn_vortex` with spell vortex keys | Spawns nothing, no error `[game]` | Storm of Magic keys only |
| Setting a vortex's duration | No API `[code]` | Tune frequency, distance and tier |
| A teleport VFX at a position | No API; composite scenes are baked `[code]` | Vanish + ping marker |
| `set_invisible_to_all` as protection | Units still targeted `[game]` | Cut: Mirage |
| Hiding units from the enemy only | No per-alliance visibility `[code]` | Cut: Unseen Host |
| Scripted charges on player units | Player orders override `[game]` | Cut: Bloodlust, Unruly Ranks |
| CA's attack planner for allies | Units hid in cover `[game]` | Per-unit `start_attack_closest_enemy` |
| Unit-class stat modifiers | Never apply `[game]` | Vanilla `cavalry_chariots` unit-set effects |
| Hiding the unit-set tooltip list | `owner_only` / `army_to_army_own_unseen` do nothing `[game]` | Disclaimer paragraph |
| Reordering effects to recolour a bundle name | No change `[game]` | Not fixed (idea: split the bundle) |
| `heal_hitpoints_unary(share)` as "heal by" | Heals TO a level `[game]` | Heal to current + share |
| Instant read-backs as proof | Stale values `[log]` | Log the intended value, or read later |
| Changing speed/charge/leadership in battle | No API `[code]` | Pre-battle campaign bundles |
| "+N XP" on units | Ranks only `[code]` | Ranks for units, XP for lords |
| A vanilla garrison-size effect | None exists `[code]` | Garrison-scope stat buff; script sets enemy garrison HP |
| "+2 enemy units" | Armies already full `[code]` | +25% budget |
| A -100% reinforcement-time bundle | Units jump to the centre `[game]` | Grouped `deploy_reinforcement` |
| Holding an ally back to 3:00 | Game timer brings it by ~90 s `[log]` | Cut: Signal Fires |
| Allies in ambush or defence | Left out of the battle `[game]` | Allied battles are always attacks |
| Battle map region overrides / catchment tags | No effect `[game]` | Teleport the lord to a random spot |
| `cm:trigger_dilemma` with many registered choices | All show as blank buttons `[game]` | Dilemma builder |
| Event-feed messages for results | No payload area `[game]` | Script-built incidents |
| Battle before its result incident | Hover froze the game `[game]` | Incident first, battle 0.5 s later |
| Probing loc to pick a per-difficulty line | Silent fallback on a missing row `[code]` | Always generate all three |
| Killing Blow on every unit | Active ability = button on each card `[code]` | Passive Deathblow |
| Wounding the lord mid-delve | Would end the delve `[code]` | Tower wounds wait for the delve's end |
| MCT `Wiki` page type | Empty stub `[game]` | Sections with hidden dummy options |
| `goto` in game Lua | Lua 5.1 syntax error `[code]` | `if` blocks |
| A plain-text `string.find` in the marker parser | Crashed on entering a smithy, cause unknown `[game]` | Two-argument `string.find` only |

---

## 12. Still open

Things nobody has checked in game, or whose cause we only inferred:

- **Bundles and stats:**
  - Whether `owner_only` bundles apply their stats on AI armies. Every enemy debuff assumes they do.
  - Whether one relation step reads as 10 on the attitude tooltip.
- **Realm calls:** `heal_garrison` and `make_region_visible_in_shroud` on a damaged garrison and a shrouded region.
- **Allies:**
  - The random 0-100% reinforcement-timer roll, as one feature.
  - Whether vanilla's -95% (not -100%) staggers arrival enough to avoid the jump.
  - Why allies are left out of defensive battles (alliance vs shared war).
- **Battle attributes:** whether `cant_run` blocks running from the first second, and whether `mounted_fire_move` works on foot archers.
- **Wet Powder's** ammo hold and restore.
- **Batch 4 in game:**
  - Lore army ranks, and the rank-9 cap.
  - The unit-type strip offers.
  - The themed Allies in the Dark line.
- **Teleport load:** whether Scattered Ranks' per-unit reachability checks stutter on big armies.
- **The freeze on hovering an incident during a pending battle:** the cause is inferred from timing, and the 0.5 s delay depends on frame timing.
- **Army abilities granted by bundle:** whether the AI fires an army ability it gets that way on its own.
