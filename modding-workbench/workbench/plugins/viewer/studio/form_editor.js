// The form editor behind the Stats tab's unit card: a form's stats, melee weapon, missile weapon, attributes and abilities, written as registry
// values (dotted paths the project config lists as `editable`). The gallery's `manifest.editor` gives each form's values as built (`forms`) and the
// attribute and ability catalogs (`attributes`, `abilities`).
//
// Unit stats are set for every form of a weapon (its base on foot; mounts add their vanilla difference) or for one form only (an override).
// The melee weapon, missile values, attributes and abilities belong to the weapon. Edits show at once on the card: each panel number moves by the change of
// the value behind it. Saved edits keep showing until a rebuild bakes them into the gallery.

// Unit stats: [field, label, panel stat]. `armour` is an armour value, the rest are land unit columns.
export const UNIT_FIELDS = [["melee_attack", "Melee Attack", "melee_attack"], ["melee_defence", "Melee Defence", "melee_defence"], ["charge_bonus", "Charge Bonus", "charge_bonus"],
  ["morale", "Leadership", "leadership"], ["armour", "Armour", "armour"], ["bonus_hit_points", "Health bonus per model", "hp"]];
// Melee weapon: [field, label]. Damage and armour-piercing damage add up to Weapon Strength.
export const MELEE_FIELDS = [["damage", "Base damage"], ["ap_damage", "Armour-piercing damage"], ["bonus_v_large", "Bonus vs large"], ["bonus_v_infantry", "Bonus vs infantry"]];
// Missile weapon: [field, label, panel stat]. `ammo` is the land unit's, the rest the projectile's.
export const MISSILE_FIELDS = [["damage", "Missile damage", "missile_strength"], ["ap_damage", "Missile armour-piercing", "missile_strength"],
  ["effective_range", "Range", "range"], ["base_reload_time", "Reload time (s)", null], ["ammo", "Ammunition", "ammunition"]];

export class FormEditor {
  constructor(studio) {
    // Whether a unit stat edit is for every form of the weapon or this form only.
    this.scope = "weapon";
    this.studio = studio;
    this.editor = studio.manifest.editor || null;
    // Registry edits saved but not rebuilt yet: they keep previewing.
    studio.savedRegistry = {};
    studio.preview = key => this.preview(key);
  }

  enabled() { return !!this.editor && !!this.studio.tuning; }
  // Saved then unsaved edits, the later winning.
  pending() { return { ...this.studio.savedRegistry, ...this.studio.edits.registry }; }
  form(key) { return this.editor && this.editor.forms[key]; }
  // The weapon's form on foot, whose stats are the weapon's base.
  footForm(weapon) { return Object.values(this.editor.forms).find(f => f.weapon === weapon && f.mount === "foot"); }

  // A unit stat of a form with the pending edits: its own override, else the weapon's base plus what its mount adds.
  unitValue(f, field) {
    const p = this.pending(), formPath = `weapons.${f.weapon}.forms.${f.mount}.${field}`, basePath = `weapons.${f.weapon}.stats.${field}`;
    const foot = this.footForm(f.weapon) || f, mountAdds = f.overrides.includes(field) ? 0 : f.stats[field] - foot.stats[field];
    if (formPath in p && p[formPath] !== null) return p[formPath];
    if (f.overrides.includes(field) && !(formPath in p)) return f.stats[field];
    return (basePath in p ? p[basePath] : foot.stats[field]) + mountAdds;
  }
  meleeValue(f, field) { const p = this.pending(), path = `weapons.${f.weapon}.melee.${field}`; return path in p ? p[path] : f.melee[field]; }
  missilePath(f, field) { return field === "ammo" ? `weapons.${f.weapon}.missile.ammo` : `weapons.${f.weapon}.missile.projectile.${field}`; }
  missileValue(f, field) { const p = this.pending(), path = this.missilePath(f, field); return path in p ? p[path] : f.missile[field]; }
  // The weapon's added and removed lists of a kind ("attributes" or "abilities") with the pending edits.
  lists(f, kind) {
    const p = this.pending(), path = `weapons.${f.weapon}.${kind}`;
    return { added: p[path] || f[kind] || [], removed: p[path + "_removed"] || f[kind + "_removed"] || [] };
  }

  // A panel with the pending edits applied, for the Stats tab. Units without edit data come back as they are.
  preview(key) {
    const panel = this.studio.manifest.panels[key], f = this.form(key);
    if (!panel || !f) return panel;
    const stats = { ...panel.stats };
    for (const [field, , stat] of UNIT_FIELDS) stats[stat] += (this.unitValue(f, field) - f.stats[field]) * (field === "bonus_hit_points" ? stats.men : 1);
    stats.weapon_strength += this.meleeValue(f, "damage") - f.melee.damage + this.meleeValue(f, "ap_damage") - f.melee.ap_damage;
    if (f.missile) for (const [field, , stat] of MISSILE_FIELDS) if (stat) stats[stat] += this.missileValue(f, field) - f.missile[field];
    for (const k of Object.keys(stats)) stats[k] = Math.round(stats[k]);
    const out = { ...panel, stats };
    for (const kind of ["attributes", "abilities"]) {
      const { added, removed } = this.lists(f, kind), catalog = this.editor[kind] || {}, keys = new Set(panel[kind].map(a => a.key));
      (f[kind] || []).filter(a => !added.includes(a)).forEach(a => keys.delete(a));
      added.forEach(a => keys.add(a)); removed.forEach(a => keys.delete(a));
      out[kind] = [...keys].map(a => panel[kind].find(x => x.key === a) || { key: a, name: a, text: "", ...catalog[a] });
    }
    return out;
  }

  // Records an edit and refreshes the previews.
  set(path, value) { this.studio.edits.registry[path] = value; this.studio.changed(); }

  // Turns a typed value into registry edits.
  edit(f, path, value) {
    const [group, field] = path.split(".");
    if (group === "unit") {
      if (this.scope === "form") { this.set(`weapons.${f.weapon}.forms.${f.mount}.${field}`, value); return; }
      // The weapon's base moves by the change typed on this form, so every form without its own value moves the same way.
      const foot = this.footForm(f.weapon) || f, basePath = `weapons.${f.weapon}.stats.${field}`, p = this.pending();
      this.set(basePath, (basePath in p ? p[basePath] : foot.stats[field]) + value - this.unitValue(f, field));
    } else if (group === "melee") {
      // The first melee edit gives the weapon its own melee weapon, copied from the one it uses now.
      if (!f.own_melee && !(`weapons.${f.weapon}.melee.template` in this.pending())) this.set(`weapons.${f.weapon}.melee.template`, f.melee_template);
      this.set(`weapons.${f.weapon}.melee.${field}`, value);
    } else if (group === "missile") {
      this.set(this.missilePath(f, field), value);
    }
  }

  // The edits were saved: they keep previewing until a rebuild.
  saved() { Object.assign(this.studio.savedRegistry, this.studio.edits.registry); }
}
