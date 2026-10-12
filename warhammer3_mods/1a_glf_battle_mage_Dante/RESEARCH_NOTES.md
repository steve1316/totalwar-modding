# GLF Battle Mage research notes: giving lords and heroes a ranged spell attack

These notes cover how GLF Battle Mage (Workshop 3387635246) makes vanilla lords and heroes fire a magic missile, and the problems
we hit along the way. The 2026-10 work ran on branches `glf-battle-mage-anims` (PR #33) and `glf-ranged`. It covers patch 7.x and the dlc29 lords.

Sources:
- The Dev Notes on the two Workshop pages, kept word for word in the [Dev Notes](#dev-notes-from-the-workshop-pages) section.
- In-game tests during the 2026-10 sessions.
- The generator report (`helper_scripts/_diag/glf_ranged_generate_report.txt`).

**Status tags** used on every finding:

| Tag | Meaning |
|---|---|
| `[game]` | Tested in game and confirmed. |
| `[data]` | The game files show it (tables, animation sets, metas). Not checked in game on its own. |
| `[untested]` | An assumption we have not checked. |

**Path shorthands:** `M/` is `warhammer3_mods/1a_glf_battle_mage_Dante/`. `T/` is `helper_scripts/tools/glf_ranged/`.

---

## Contents

1. [How a character fires](#how-a-character-fires)
2. [The tools](#the-tools)
3. [Animation findings](#animation-findings)
4. [Data findings](#data-findings)
5. [Per-unit fixes](#per-unit-fixes)
6. [Known gaps](#known-gaps)
7. [File formats](#file-formats)
8. [Dev Notes from the Workshop pages](#dev-notes-from-the-workshop-pages)

---

## How a character fires

A lord or hero fires a spell projectile when three things line up:

1. **Data.** Their `land_units_tables` row has a GLF `primary_missile_weapon` and `primary_ammo` of 20. GLF also sets `ai_usage_group` to
   `hybrid_mage_highvalue`. The missile is `glf_mage_{lord|hero}_{lore}_missile` or a named special like `glf_skv_lord_skrolk_missile`. `[game]`
2. **A fire animation.** The animation set the character actually plays has a filled fire slot:
   - `FIRE_LEVEL` on foot.
   - `RIDER_FIRE_FORWARD_LEVEL` plus `RIDER_SHOOT_TURN_LEFT_90` and `RIDER_SHOOT_TURN_RIGHT_90` for riders. `[game]`
3. **A fire marker.** The animation's `.anm.meta` has a `FIRE_POS` tag, which sets when and where the projectile spawns. `[game]`

Fire whilst moving (FWM) adds two more things:

- **The attribute.** `mounted_fire_move` goes in the unit's attribute group. It is used for infantry and cavalry alike. `[game]`
- **Moving fire slots:**
  - On foot and flying: `MOVING_FIRE_FORWARD/LEFT/RIGHT/BACKWARD_LEVEL`, plus `SHOOT_*` stances copied from `STAND`, `WALK_1` and `RUN_1`.
  - Riders: `RIDER_FIRE_LEFT/RIGHT/BACK_LEVEL`. `[game]`

---

## The tools

| Command (run from `helper_scripts/`) | What it does |
|---|---|
| `python -m tools.glf_rebuild_animpack [--dry-run] [--source-ids-rev <schemas commit>]` | Rebuilds every GLF animation set on top of current vanilla, keeping GLF's own fire slots. Run it first after a game patch. |
| `python -m tools.glf_ranged` | Picker page on `http://127.0.0.1:8766/`. Lists every vanilla lord and hero by faction with card art. Tick Ranged and FWM, then Save & apply. |
| `python -m tools.glf_ranged.generate [--dry-run] [--deploy]` | Writes everything from `T/selection.json`: land units, rider personalities, attribute groups, chariot arcs, fire slots and fire markers. `--deploy` also copies the changed files into the subscribed Workshop pack. |

- **Report:** `_diag/glf_ranged_generate_report.txt`. Its "Needs a manual animation" list is the to-do list for sets the rules cannot fix.
- **Picker rules:**
  - The picker builds its catalog once at start, so restart it after any catalog change.
  - Ctrl-click a base unit's FWM tick to set every mount too.
  - Click Mark as published after each Workshop upload.
- **Overrides:** Per-unit animation fixes the rules cannot work out live in two tables in `T/generate.py`:
  - `FIRE_ANIM_OVERRIDES`: set name to an animation path, or to a slot name in the set whose animation and meta to reuse.
  - `FIRE_SLOT_DONORS`: set name to another set whose fire slots fill the gaps.

---

## Animation findings

### Slots and sets

- **CA renumbers slot ids between patches.** In 2026-10, GLF's animpack was still in patch 7.0 numbering, so every mounted caster's
  `RIDER_FIRE_FORWARD_LEVEL` read as a different slot. The rebuild tool translates ids by slot name. Pass the schemas commit the pack was last
  saved with. On-foot `FIRE_LEVEL` (1557) never moved. `[game]`
- **GLF's animpack holds full copies of vanilla sets**, which override vanilla wholesale. A CA patch that changes a set leaves GLF's copy stale
  until the rebuild tool runs. `[data]`
- **T-pose after firing means `FIRE_LEVEL` without `COMBAT_READY`.** The generator copies `COMBAT_READY*` from the standing and movement slots when
  they are missing. Fimir mages were the original case. `[game]`
- **Vanilla sometimes ships fire slots with no animation in them.** These never play, and they used to count as present:
  - The Skink Priest on a Stegadon had empty `RIDER_FIRE_*` slots.
  - Neferata's Zombie Dragon had an empty `FIRE_LEVEL`.

  The generator now drops empty fire slots and fills them again. `[game]`
- **A set that only has rider casts is a rider set**, even with no mount and no `RIDER_STAND`. The Wu Xing War Compass Astromancer got no fire slots
  until this rule went in. `[game]`

### Which set a character really plays

- **A hero riding a war machine animates from his rider personality's set, not the land unit's `man_animation`.** To find it:
  1. Look up the land unit in `land_units_to_battle_personalities_junctions_tables`.
  2. Find that personality in `battle_personalities_tables`.
  3. Read its `man_animations_table`.

  That set needs `RIDER_FIRE_*` slots. Lord Skrolk on his Cauldron, the Plague Furnace priest, Mazdamundi on his Stegadon and Neferata on the
  Coven Throne all work this way. This is the "chariot" problem from the Dev Notes. `[game]`
- **Heroes attached as `officer` behave like autonomous riders.** Settra on his Warsphinx is one. `[game]`
- **A hero standing on a war machine with no rider cast can reuse his on-foot `FIRE_LEVEL` for the rider slots.** He is standing anyway. Settra on
  the Warsphinx and Neferata on the Coven Throne are examples. `[game]`

### Standing up, facing and freezing

- **A rider stands up to fire when the rider fire slots play an on-foot cast.** The generator swaps in a seated cast, meaning one under a `/rider/`
  folder, when the set has one that faces forward. Elspeth on her Carmine Dragon and her warhorse were fixed this way. `[game]`
- **Some "rider" casts are on-foot casts in all but name.** The Moon Bird Astromancer's casts have the same length and size as his on-foot ones.
  When a rider has no seated cast, these work instead:
  - A seated attack from `RIDER_ATTACK_*`, as for the Moon Bird and Neferata's horses.
  - The set's own seated stand, as for Dieter and Neferata's Zombie Dragon.

  The Dev Notes reached the same answer for Egrimm van Horstmann. `[game]`
- **A seated cast borrowed from a different mount can lift the rider off the seat.** Dieter on his Manticore with the generic horse cast hovered
  above his saddle. His own seated stand fixed it. `[game]`
- **A fire animation whose static animroot rotation is not identity plays turned around.** Yuan Bo's short cast is rotated 180 degrees, so he
  turned around and fired backwards. The tool rejects these and only uses casts it can read as facing forward. `[game]`
- **Many casts move their animroot, so their facing cannot be read.** The tool skips those, leaving a "Needs a manual animation" note, unless an
  override names them. Settra's chariot cast and Bloab's seated attacks are examples. `[data]`
- **A fire slot plays the whole animation.** Neferata's "short" cast is 8 s long with the shot at 1 s, so she froze for 7 s after each shot. Check
  the animation length against the `FIRE_POS` time before picking a cast. Her 6 s medium cast fixed it. `[game]`
- **A missing aim stance (`AIM_LEVEL`) was not the cause of that freeze.** Adding it to 120 sets did nothing, so it was backed out. `[game]`
- **The wrong meta can dock a weapon in the wrong place.** The Eshin Sorcerer fired with the generic Skaven cast and its meta, which moved his
  weapon far to his side. His own cast and meta fixed it. `[game]`

### Fire markers

- **A fire animation with no `FIRE_POS` still fires standing still but spawns no projectile on the move.** The Fimir Balefiend was the case. Every
  fire slot in a set that fires while moving now points at a GLF copy of its meta with a marker:
  `glf_<anim>_fire.anm.meta`, next to the animation. `[game]`
- **Default marker:** the median `FIRE_POS` of GLF's existing metas for the same skeleton, otherwise 45% of the animation at (0, 1.2, 0.5). `[data]`

---

## Data findings

- **Rider personalities.** Monster-mount riders fire through an `autonomous_rider` personality.
  - When GLF adds a unit, the personality gets `battle_entity_stats` set to the missile, plus a matching `battle_entity_stats_tables` row.
  - The generator only adds the row when no regular unit shares the personality.
  - A hero personality with empty `battle_entity_stats` already fires the land unit's missile. A missing personality row is not why a hero
    cannot fire, so check the animation set first. `[game]`
- **Crews keep their own weapons.** A crew personality that has its own `battle_entity_stats` in vanilla must never get the lord's missile.
  Mazdamundi's skinks did, so they fired his spell all round, which looked like a 360 degree arc on him. `[game]`
- **Fire whilst moving attribute.** If the unit's attribute group is shared with other units, the unit gets its own `glf_<unit>` group. The group
  copies the vanilla attributes plus `mounted_fire_move`, so the other units do not gain it. `[game]`
- **Where the firing arc comes from** (`battle_entities.fire_arc_close`): `[game]`
  - Cavalry use their mount's body. Vanilla horses are already 360.
  - Chariots use the chariot's own body, its `articulated_entity`.
  - On foot, the unit's own body, usually 60. Unchanged.
- **Chariots that fire while moving get a 360 degree arc** through a `glf_` copy of the chariot record:
  - Copy its `land_unit_articulated_vehicles` row, every one of its `articulation_nodes_in_land_articulated_vehicles` rows, and a `glf_` copy of the
    body with `fire_arc_close` 360. `[game]`
  - **Never copy a chariot record without its articulation nodes.** The game crashed when we did. `[game]`
  - **Never copy the rider or draught mount entities.** The chariot stopped firing when we did. `[game]`
- **Quest battle, boss and custom battle copies** (`_qb`, `_boss`, `_mp`, and `_qb_` mid-key) are separate land units:
  - Custom battles field the `_mp` ones. Neferata had no ranged stats in custom battles until her `_mp` copies were covered.
  - Each copy is matched to its campaign twin by key, also ignoring the game prefix. Matched copies follow the twin's picks and are hidden in the
    picker.
  - Copies with no twin, such as the Cygor and Treeman bosses or Arkhan's `_mp` units, are normal picker rows.
  - Greenskin `_big_boss` units are real heroes, not boss copies. `[game]`
- **The 2x unit size compat conflicts with GLF.** Its `land_units` rows sort above GLF and wipe the GLF missile and ammo. We accepted the conflict
  on 2026-10-10: there is no bridge pack, and GLF is not baked into the compat, so non-GLF users do not get missile lords. `[game]`
- **Vanilla `campaign_character_arts_tables` is still v0** even though the schema lists v7. Do not bump it. `[data]`

---

## Per-unit fixes

These were added by hand in `T/generate.py` after the rules could not work them out. All confirmed in game on 2026-10-12.

| Unit | Set | Fix |
|---|---|---|
| Astromancer on Great Moon Bird | `hu1e_dlc24_bi1_eagle_mage_hero` | Seated staff swing (`..._attack_01`). His rider casts stand him up. |
| Eshin Sorcerer | `hu17_skaven_eshin_staff_and_sword` | His own `CAST_SPELL_UP_SHORT` and meta, instead of the generic Skaven cast. |
| Settra, Chariot of the Gods | `hu1_settra_wm_tomb_chariot01_2handed_halberd` | His chariot `RIDER_CAST_SPELL_FORWARD_SHORT`. Its facing cannot be read. |
| Dieter Helsnicht on Manticore | `hu1_dlc29_dieter_bc3_manticore_wb_staff_and_sword` | His seated `STAND` (dragon rider hover). No seated cast exists for the skeleton. |
| Neferata on foot and Coven Throne | `hu1ba_dlc29_vmp_neferata_staff_and_sword` | `CAST_SPELL_FORWARD_MEDIUM` (6 s, shot at 3 s). The short cast froze her for 7 s. |
| Neferata on Barded Nightmare and Hellsteed | `hu1ba_dlc29_vmp_hr1_*_neferata_*` | Seated horse swing (`hu1ba_hr1_neferata_rider1_attack_02`). |
| Neferata on Dread Abyssal | `hu1ba_dlc29_vmp_bc3c_dread_abyssal_neferata_staff_and_sword` | Seated swing (`..._rider1_attack_01`). Her seated cast is 8 s too. |
| Neferata on Zombie Dragon | `hu1ba_dlc29_vmp_dr1_zombie_dragon_wb_neferata_sword_and_staff` | Seated hover `STAND`. No seated cast or swing exists. |
| Bloab Rotspawned on Bilespurter | `hu13f_dlc29_bloab_hu18e_pox_maggoth_scythe` | Seated attack `..._poxmaggoth_attack_01`. None of his seated attacks shows a clear swing. |
| Skink Priest on Stegadons | `hu7_skink_hq1_stegadon_wb_staff_and_club` | Borrows the skink crew's seated throws from `hu7_skink_hq1_stegadon_wb_javelin` (`FIRE_SLOT_DONORS`). |
| Yuan Bo (human form) | `hu1e_dlc24_yuan_bo_dragon_jade` | Long cast for `FIRE_LEVEL`. His short cast is rotated 180 degrees. Fixed in PR #33. |

---

## Known gaps

- **Nurgle Sorcerer on his steed** (`hu1c_dlc25_nurgle_sorcerer_hr1_large_warhorse_staff_and_mace`) still stands up to fire. His seated casts move
  their animroot, so their facing cannot be checked. `[data]`
- **Mazdamundi on his Stegadon** shows as "Needs a manual animation" for fire whilst moving. His land unit set reads as on foot. He fires through
  his rider slot and works in game. `[game]`
- **Dynasty of the Damned** (modded, from the old Dev Notes): those characters stand up to fire whatever is changed. Not looked at in 2026-10.
  `[untested]`

---

## File formats

- **Animpack:** the WH3 animpack container. Set files are `.bin` animation sets, v4.3. Slot ids are per patch: see
  `helper_scripts/schemas/anim_ids_warhammer_3.csv`. `[data]`
- **`.anm.meta`:** `u32 2`, `u32 tag count`, then each tag is `string name, u32 version, f32 start, f32 end, u16 flags`, then the tag body.
  `FIRE_POS` is v10. Its 26-byte body is start, end, 6 zero bytes, then x, y (up), z (forward). `[data]`
- **`.anim` v8 header:** the static animroot rotation tells which way the animation faces. A non-identity rotation means it plays turned around.
  An animated animroot cannot be read from the header. `[data]`
- **Card art:** unit, then agent subtype (`associated_unit_override`), then `campaign_character_art_sets`, then portrait settings in `ui.pack`,
  then `ui/portraits/units`. `[data]`

---

## Dev Notes from the Workshop pages

Kept word for word, so they survive any edit to the Workshop pages.

### [GLF] Battle Mage (3387635246)

From https://steamcommunity.com/sharedfiles/filedetails/?id=3387635246:

> Continuing off of the Dev Notes from https://steamcommunity.com/sharedfiles/filedetails/?id=3003028979 with some re-iteration from the original Dev Notes:
>
> The following are just a mish-mash of what I learned in no particular order. I am no expert as I am completely self-taught on this through trial and experimentation to see what works and what doesn't.
>
> A Python script was used to automate updating all values in land_units_table to the latest stat values of patch 6 and will be used to keep the table up to date if/when CA balances the stats of these characters in the future. Most likely will be repurposed to keep the stat values of my other mods up to date as well.
>
> All of the RIDER_CAST_* animations handle characters that are sitting down on their mounts (horse, dragon, etc.) and standing up on their mounts (chariots, warshrines, etc.). The FIRE_LEVEL, RIDER_FIRE_FORWARD_LEVEL, RIDER_SHOOT_TURN_LEFT_90 and RIDER_SHOOT_TURN_RIGHT_90 that allows the character to fire projectiles.
>
> If the character on foot is T-posing after firing, they are missing their COMBAT_READY animation slot. I set it to the standing around or idling animation to get past it (I am looking at you, Fimir mages).
>
> Regarding characters on chariots especially for Tomb Kings, their land_units_table entry shows they are using their on-foot animation set. Ran into this issue in the past when attempting to fix it before that no matter what changes I made, the characters on chariots would not fire. But on closer inspection, their on-foot animation sets are actually being overridden with their chariot-specific animation sets via several database tables in RPFM. I addressed them all by doing any of the following:
>
> 1. land_units_to_battle_personalities_junctions_tables -> Reference the "Land Unit" key and look at the corresponding "Battle Personality" key. I then use that key and look at battle_personalities_tables and find the relevant row. You may or may not find that the on-foot animation set is overwritten with a mount-specific one in the "Man Animations Table" column and you can use AssetEditor or RPFM itself to grab that set and add the required animation sets for ranged attacks.
>
> 2. Sometimes there is an existing `*chariot*` set in the existing game animation sets and you can repurpose that instead.
>
> These are the required animation slots that you need to add to enable ranged attacks to trigger.
>
> Add FIRE_LEVEL for on-foot characters. CAST_FORWARD_* or CAST_UP_* animations are perfect to replace the "Instance" with.
>
> Add RIDER_FIRE_FORWARD_LEVEL, RIDER_SHOOT_TURN_LEFT_90 and RIDER_SHOOT_TURN_RIGHT_90 for mounted characters. You may need to substitute the animations for something else.

```xml
  <Animation Slot="FIRE_LEVEL" BlendId="0.2" SelectionWeight="1" WeaponBone="True, True, True, True, False, True" Unk="false">
	<Instance File="" Meta="" Sound="" />
  </Animation>

  <Animation Slot="RIDER_FIRE_FORWARD_LEVEL" BlendId="0.5" SelectionWeight="1" WeaponBone="True, True, True, True, True, True" Unk="false">
	<Instance File="" Meta="" Sound="" />
  </Animation>
  <Animation Slot="RIDER_SHOOT_TURN_LEFT_90" BlendId="0.5" SelectionWeight="1" WeaponBone="True, True, True, True, True, True" Unk="false">
	<Instance File="" Meta="" Sound="" />
  </Animation>
  <Animation Slot="RIDER_SHOOT_TURN_RIGHT_90" BlendId="0.5" SelectionWeight="1" WeaponBone="True, True, True, True, True, True" Unk="false">
	<Instance File="" Meta="" Sound="" />
  </Animation>
```

### Mod compatibilities submod for GLF Battle Mage, outdated (3003028979)

From https://steamcommunity.com/sharedfiles/filedetails/?id=3003028979:

> Adding the corresponding missile weapon defined in GLF into their "Primary Missile Weapon" column and adding a value of 20 for their "Primary Ammo" column to their "land_units_tables" tables will allow that character to be able to fire projectiles as a spellcaster. But you also need to make sure their animation set allows it as well.
>
> Adding the FIRE_LEVEL animation slot to the character's animation set via AssetEditor is usually good enough. For modded characters with custom animations, I would encounter T-posing for unmounted characters. Fixing that usually meant I had to add their missing COMBAT_READY animation slots.
>
> For mounted characters like warhorses and dragons, usually they do not fire at all. I would substitute the chosen spell casting animation with their idle animation (like for Arkhan from Legions of Nagash). Otherwise, they would be missing their RIDER_FIRE_* animation slots so I would take those from their same skeleton class (warhorses or dragons) and then use their attack animations if the spellcasting animations did not fix it as well.
>
> In addition, some would stand up while firing (like Egrimm van Horstmann). In that case, I would substitute the animations for their RIDER_FIRE_* with the ones from their RIDER_ATTACK_* slots. Although the ones from the Dynasty of the Damned mod truly makes me sad as I cannot fix theirs. For some reason, they already have animations to fire projectiles without me touching it and those cause them to stand up. And any changes I make does not stop them from doing so.
>
> Let's not talk about the ones with chariots. Those are a whole mess to work with. Arkhan, Mortarch of Sacrament from the Legions of Nagash - Game 3 mod was lucky enough to reuse the Liche Priest's chariot animations but I cannot replicate that same success with the rest of the spellcasters that use chariot mounts.
>
> For flying characters like Ariel, adding FLY_COMBAT_READY_* and FIRE_LEVEL animation slots was enough to allow her to fire projectiles.
