# Spot map

A local page for placing LEAPOI encounter spots. It draws every spot in `configs/coordinates.lua` over the campaign's own minimap, previews
a minimum-spacing trim, takes manual additions and deletions, and writes them back to `coordinates.lua`.

## Run

```
cd helper_scripts
python -m tools.spot_map            # opens http://127.0.0.1:8765/
python -m tools.spot_map --port 9000 --no-browser
```

Only the standard library is used. The first run extracts each campaign's minimap and `prebattle_map.png` with `rpfm_cli` into
`_diag/spot_map/`.

## Campaigns

| Campaign | Map source | Spots from |
|---|---|---|
| Immortal Empires | `data_maps.pack` | `M.immortal_empires` |
| Immortal Empires Expanded | `!cr_immortal_empires_expanded.pack` (Workshop 3007996493) | `M.immortal_empires` + `M.immortal_empires_expanded` |
| Realm of Chaos | `data_maps.pack` | `M.realm_of_chaos` |
| The Old World | `!cr_oldworld_campaign.pack` (Workshop 3081800026) | `M.old_world`, seeded from `data/oldworld_draft.json` until the first export creates it |

Pack paths and map folders are in `campaigns.py`. The newest numbered map folder in a pack is used.

The minimap is stretched from the logical map: `prebattle_map.png` has the logical size, so logical x maps across the minimap's width and
logical y (south to north) is flipped and stretched to its height.

## Settlements

Press F4 in game with the `debug_coordinates` mod. Its `debug_settlements.tsv` in the game folder is saved to
`data/settlements_<campaign>.json` for the campaign its header names, on every start and every Reload. Immortal Empires Expanded uses
Immortal Empires' settlements until it has its own dump. Spots and new points are matched to provinces by their nearest settlement.

## Editing

- **Plant:** pick a type under "Click plants" (encounter spot, tower site, smithy, tavern), then click empty ground. A new entry takes the
  zone and area of the nearest spot; smithies and taverns pre-fill their owners from the nearest settlement's owner. Zone, area, owners
  and a tavern's culture can be changed in the pending list.
- **Delete:** click a spot, smithy or tavern to mark it; click again to undo. Click a dashed (disabled) entry to switch it back on.
- **Move:** drag a spot, smithy, tavern or pending entry. A moved entry is pending (never trimmed) and shows a dashed line to where it was;
  on export its line is rewritten in place with the new coordinates and `manual = true`, so its index does not change.
- New, moved and switched-back-on entries are **pending** until exported (kept per campaign in the browser). The spacing trim never removes
  them, but they hold their space: neighbours too close to them are trimmed, like "Smithies count as spots".
- Exported entries are written with `manual = true` and come back as **manual**: never trimmed and holding their space as well, unless you
  tick **Trim manual spots too**. LEAPOI ignores the flag.
- **Export** writes the changes to `coordinates.lua` after a backup in `_diag/spot_map/backups/`:
  - new spots go at the end of their zone, under a `--- Area` comment; a tower site is a spot written as `{x, y, tower = true}`;
  - new smithies and taverns go into `points_of_interest.<zone>.smithies` / `.taverns`, creating the list or zone when needed;
  - deleted entries stay in place with `disabled = true`. Towers, marker ids and smithy saves use an entry's index, so lines are never
    removed;
  - tick **Include spacing trim in export** to also disable every spot the trim removes.
- Try exports on a copy with `--coordinates path/to/copy.lua`.

## History

- **Queue order:** the pending list shows the newest change on top, and moving an entry again brings it back to the top.
- **Undo / redo:** **Undo** and **Redo**, or Ctrl+Z and Ctrl+Y / Ctrl+Shift+Z, step through every change to the open queue, including
  Clear. Edit existing and Clean slate keep a separate history per campaign. The history lasts for the browser session, and an export or a
  Reload starts it over.
## Clean slate

Switch the toolbar from **Edit existing** to **Clean slate** to build a layout from scratch: existing spots and points of interest are hidden,
only the minimap and settlements stay, and provinces with no spot in the layout are ringed. Planting, dragging and click-to-remove work as
in Edit existing, but on a separate queue: the campaign's layout in `data/layouts/<campaign>.json`, saved half a second after each change.

**Export draft block** writes the layout to `coordinates.lua` as `M.<campaign>_draft` (for IE Expanded, one draft per block its entries
belong to), replacing the previous draft. LEAPOI never reads draft blocks. When a campaign has no layout file but has a draft block, the
layout starts from that block. Promoting a draft to the live block is a separate step, not done by the tool yet.

## Suggestions

An LLM can propose where to put taverns, smithies or tower sites. The script gathers the facts and the LLM makes the picks. There is no API
key: you ask Claude Code in a session.

1. `python -m tools.spot_map.suggest brief --campaign ie` writes `_diag/spot_map/brief_ie.md`. For each zone it lists the zone's cultures
   (settlements belong to the zone of their nearest spot) and its points of interest. Each enabled spot also gets its nearest settlement,
   the cultures of the 3 nearest settlements, how crowded it is and how far it is to the nearest smithy.
2. The LLM reads the brief and writes `data/suggestions/<block>.json`, one file per coordinates.lua block (e.g. `immortal_empires.json`):
   `{"suggestions": [{"type", "lua", "zone", "spot", "fields", "reason"}]}`. A suggestion always takes over an existing enabled spot, which is known to be reachable land, so it never lands in the sea.
3. `python -m tools.spot_map.suggest check --campaign ie` reports a missing or disabled spot, a spot named twice, an unknown type or an
   unknown culture.

The page draws suggestions as dashed outlines of their type (the **suggested** chip) and lists them with their reasons in the Suggestions
card. Click one, or **Accept** it in the card, to queue it:
- the new entry goes on the spot's coordinates, with its owners taken from the nearest settlement;
- the spot itself is marked for deletion, so it leaves the encounter pool.

Removing the pending entry undoes both. Once exported, a suggestion shows as "placed". A campaign shows the suggestions of every block it
draws, so IE Expanded shows IE's.

## What LEAPOI does with it

- `disabled = true` spots never become encounters, new towers or tower battlefields; an encounter active on one in a save is removed on load.
- Spot state is saved by coordinates, so a moved spot starts fresh in an existing save; on load every inactive spot's marker is removed, so
  nothing is left behind at the old position.
- A zone with `tower = true` spots places its new tower on one of them instead of a random spot. Towers already in a save stay where they are.
- `disabled = true` smithies lose their marker and per-turn upkeep but keep their save record.
- Taverns are written for the Taverns sub-project; LEAPOI does not read them yet.

## Adding a new type

Add a row to `SPOT_TYPES` in `campaigns.py`: `"storage": "spot"` with an optional `"flag"`, or `"storage": "poi"` with its `"list"` and
`"fields"` ("owner" and "culture" fields get inputs, other values are written as given). Give it a shape and colour in `TYPE_LOOK` in
`static/index.html`, or it is drawn as a grey circle.
