"""The catalog a skill planner picks from: every effect that characters' skills use, with its in-game text and icon, the effect scopes with their text,
and every skill icon. Used by a project's gallery generator for the modding workbench's Skills tab.
"""

import re
from collections import Counter
from typing import Dict, List

from ttc.ttc_data import resolve_loc
from ttc.unit_panel import inline_image_path

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Tables the catalog reads.
SKILL_CATALOG_TABLES = ["character_skills_tables", "character_skill_level_to_effects_junctions_tables", "effects_tables", "ui_tagged_images_tables"]

# Loc key prefixes it reads.
EFFECT_TEXT_PREFIX = "effects_description_"
SCOPE_TEXT_PREFIX = "campaign_effect_scopes_localised_text_"
CATALOG_LOC_PREFIXES = (EFFECT_TEXT_PREFIX, SCOPE_TEXT_PREFIX)

# Folders of the skill icons and the effect icons.
SKILL_ICON_FOLDER = "ui/campaign ui/skills"
EFFECT_ICON_FOLDER = "ui/campaign ui/effect_bundles"

# An inline image in loc text.
INLINE_IMAGE = re.compile(r"\[\[img:([^\]]+)\]\]")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Catalog


def skill_catalog(tables: Dict[str, List[Dict[str, str]]], loc: Dict[str, str]) -> Dict:
    """Builds the catalog.

    Args:
        tables (Dict[str, List[Dict[str, str]]]): `SKILL_CATALOG_TABLES` rows.
        loc (Dict[str, str]): Loc key to text, with `CATALOG_LOC_PREFIXES`.

    Returns:
        Dict: `effects` (effect key -> `text`, `icon` path, `good` (whether a positive value is good) and `uses` by skills, most used first),
        `scopes` (scope key -> `text` and `uses`, most used first) and `icons` (skill icon file names, sorted).
    """
    tagged = {row["key"]: row.get("image_path", "") for row in tables["ui_tagged_images_tables"] if row.get("key")}
    images = lambda text: INLINE_IMAGE.sub(lambda m: f"[[img:{inline_image_path(m.group(1), tagged)}]]", text or "")
    junctions = tables["character_skill_level_to_effects_junctions_tables"]
    effect_uses, scope_uses = Counter(r["effect_key"] for r in junctions), Counter(r["effect_scope"] for r in junctions)
    rows = {r["effect"]: r for r in tables["effects_tables"]}
    effects = {}
    for key, uses in effect_uses.most_common():
        row = rows.get(key)
        if row:
            effects[key] = {"text": images(resolve_loc(loc.get(EFFECT_TEXT_PREFIX + key, ""), loc) or key), "icon": f"{EFFECT_ICON_FOLDER}/{row['icon']}".lower() if row.get("icon") else "",
                            "good": row.get("is_positive_value_good") != "false", "uses": uses}
    scopes = {key: {"text": images(resolve_loc(loc.get(SCOPE_TEXT_PREFIX + key, ""), loc) or ""), "uses": uses} for key, uses in scope_uses.most_common() if key}
    icons = sorted({r["image_path"].lower() for r in tables["character_skills_tables"] if r.get("image_path", "").lower().endswith(".png")})
    return {"effects": effects, "scopes": scopes, "icons": icons}


def catalog_art(catalog: Dict) -> List[str]:
    """Every image the catalog shows: the skill icons, the effect icons and the icons inside effect and scope texts.

    Args:
        catalog (Dict): A `skill_catalog` result.

    Returns:
        List[str]: Lowercase pack paths.
    """
    paths = [f"{SKILL_ICON_FOLDER}/{name}" for name in catalog["icons"]] + [e["icon"] for e in catalog["effects"].values() if e["icon"]]
    for text in [e["text"] for e in catalog["effects"].values()] + [s["text"] for s in catalog["scopes"].values()]:
        paths += [name.lower() for name in INLINE_IMAGE.findall(text)]
    return sorted(set(paths))
