// The Edit inspector tab: a form's stats, melee weapon, missile weapon and attributes, written as registry values (dotted paths the project config
// lists as `editable`). The gallery's `manifest.editor` gives each form's values as built (`forms`) and the attribute catalog (`attributes`).
//
// Unit stats are set for every form of a weapon (its base on foot; mounts add their vanilla difference) or for one form only (an override).
// The melee weapon, missile values and attributes belong to the weapon. Edits preview at once in the Stats tab: each panel number moves by the
// change of the value behind it. Saved edits keep previewing until a rebuild bakes them into the gallery.

// Unit stats: [field, label, panel stat]. `armour` is an armour value, the rest are land unit columns.
const UNIT_FIELDS = [["melee_attack", "Melee Attack", "melee_attack"], ["melee_defence", "Melee Defence", "melee_defence"], ["charge_bonus", "Charge Bonus", "charge_bonus"],
  ["morale", "Leadership", "leadership"], ["armour", "Armour", "armour"], ["bonus_hit_points", "Health bonus per model", "hp"]];
// Melee weapon: [field, label]. Damage and armour-piercing damage add up to Weapon Strength.
const MELEE_FIELDS = [["damage", "Base damage"], ["ap_damage", "Armour-piercing damage"], ["bonus_v_large", "Bonus vs large"], ["bonus_v_infantry", "Bonus vs infantry"]];
// Missile weapon: [field, label, panel stat]. `ammo` is the land unit's, the rest the projectile's.
const MISSILE_FIELDS = [["damage", "Missile damage", "missile_strength"], ["ap_damage", "Missile armour-piercing", "missile_strength"],
  ["effective_range", "Range", "range"], ["base_reload_time", "Reload time (s)", null], ["ammo", "Ammunition", "ammunition"]];

export class EditTab {
  constructor(studio) {
    this.studio = studio; this.scope = "weapon"; this.filter = "";
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
  // The attribute lists with the pending edits.
  attributeLists(f) {
    const p = this.pending(), base = `weapons.${f.weapon}.`;
    return { added: p[base + "attributes"] || f.attributes, removed: p[base + "attributes_removed"] || f.attributes_removed };
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
    const { added, removed } = this.attributeLists(f), catalog = this.editor.attributes;
    const keys = new Set(panel.attributes.map(a => a.key));
    f.attributes.filter(a => !added.includes(a)).forEach(a => keys.delete(a));
    added.forEach(a => keys.add(a)); removed.forEach(a => keys.delete(a));
    const attributes = [...keys].map(a => panel.attributes.find(x => x.key === a) || { key: a, name: catalog[a] ? catalog[a].name : a, text: catalog[a] ? catalog[a].text : "" });
    return { ...panel, stats, attributes };
  }

  // Records an edit and refreshes the previews.
  set(path, value) { this.studio.edits.registry[path] = value; this.studio.changed(); }

  render(container) {
    const entry = this.studio.stage.entry, f = entry && this.form(entry.unit);
    if (!this.enabled() || !f) { container.innerHTML = '<div class="note">Nothing to edit on this entry. Pick an Advisor form.</div>'; return; }
    // Vanilla numbers show only while the Stats tab compares.
    const { esc } = window.UnitPanel, vanilla = this.studio.compare ? this.studio.manifest.panels[entry.versus] : null;
    const weaponName = entry.name.split(" - ")[0], formName = entry.name.split(" - ")[1] || f.mount;
    const p = this.pending(), number = v => Math.round(v * 100) / 100;
    const row = (label, value, hint, path, extra = "") => `<div class="erow" data-path="${path}"><label>${esc(label)}</label>
      <input type="number" step="any" inputmode="decimal" value="${number(value)}"><span class="hint">${hint ?? ""}</span>${extra}</div>`;

    let html = `<div class="tools seg"><button data-scope="weapon" class="${this.scope === "weapon" ? "on" : ""}">All ${esc(weaponName)} forms</button>
      <button data-scope="form" class="${this.scope === "form" ? "on" : ""}">${esc(formName)} only</button></div>
      <div class="note">Unit stats: ${this.scope === "weapon" ? `typing a value here moves every ${esc(weaponName)} form by the same amount` : `this form keeps its own value`}.${vanilla ? ` Grey numbers are ${esc(vanilla.name)}.` : ""}</div>
      <div class="p-head">Unit</div>`;
    for (const [field, label, stat] of UNIT_FIELDS) {
      const formPath = `weapons.${f.weapon}.forms.${f.mount}.${field}`;
      const own = (formPath in p) ? p[formPath] !== null : f.overrides.includes(field);
      const reset = own ? `<button class="mini" data-reset="${formPath}" title="Use the weapon's value again">form ×</button>` : "";
      html += row(label, this.unitValue(f, field), vanilla && field !== "bonus_hit_points" ? vanilla.stats[stat] : "", `unit.${field}`, reset);
    }
    const meleeNote = f.own_melee ? `Its own melee weapon, copied from ${esc(f.melee_template)}.` : `Uses the vanilla ${esc(f.melee_template)}. Editing gives it its own copy.`;
    html += `<div class="p-head">Melee weapon</div><div class="note">${meleeNote} Shared by every ${esc(weaponName)} form.</div>`;
    for (const [field, label] of MELEE_FIELDS) html += row(label, this.meleeValue(f, field), field === "damage" && vanilla ? `${vanilla.stats.weapon_strength} total` : "", `melee.${field}`);
    if (f.missile) {
      html += `<div class="p-head">Missile weapon</div>`;
      for (const [field, label, stat] of MISSILE_FIELDS) html += row(label, this.missileValue(f, field), stat && vanilla && vanilla.stats[stat] !== undefined ? vanilla.stats[stat] : "", `missile.${field}`);
    }
    const { added, removed } = this.attributeLists(f), shown = this.preview(entry.unit).attributes;
    html += `<div class="p-head">Attributes</div><div class="note">Shared by every ${esc(weaponName)} form. Tap one to remove it.</div>
      <div class="chips">${shown.map(a => `<span class="chip" data-attr="${esc(a.key)}" title="${esc(a.text)}">${esc(a.name)} ×</span>`).join("") || "<span>None</span>"}</div>
      <input class="attrSearch" placeholder="Add an attribute (type to search)" value="${esc(this.filter)}"><div class="attrList"></div>`;
    container.innerHTML = html;

    container.querySelectorAll("[data-scope]").forEach(b => b.onclick = () => { this.scope = b.dataset.scope; this.render(container); });
    container.querySelectorAll(".erow input").forEach(input => input.onchange = () => {
      if (input.value === "" || !isFinite(+input.value)) return;
      this.edit(f, input.closest(".erow").dataset.path, +input.value);
      this.render(container);
    });
    container.querySelectorAll("[data-reset]").forEach(b => b.onclick = () => { this.set(b.dataset.reset, null); this.render(container); });
    // Attributes: removing one the weapon added drops it from its list, any other goes on its removed list. Adding works the other way round.
    const base = `weapons.${f.weapon}.`;
    container.querySelectorAll("[data-attr]").forEach(chip => chip.onclick = () => {
      const key = chip.dataset.attr;
      if (added.includes(key)) this.set(base + "attributes", added.filter(a => a !== key));
      else this.set(base + "attributes_removed", [...removed, key]);
      this.render(container);
    });
    const search = container.querySelector(".attrSearch"), list = container.querySelector(".attrList");
    const showList = () => {
      this.filter = search.value;
      const have = new Set(shown.map(a => a.key)), q = search.value.toLowerCase();
      const hits = q ? Object.entries(this.editor.attributes).filter(([k, a]) => !have.has(k) && (a.name.toLowerCase().includes(q) || k.includes(q))).slice(0, 12) : [];
      list.innerHTML = hits.map(([k, a]) => `<button data-add="${esc(k)}" title="${esc(a.text)}">${esc(a.name)}</button>`).join("");
      list.querySelectorAll("[data-add]").forEach(b => b.onclick = () => {
        const key = b.dataset.add;
        if (removed.includes(key)) this.set(base + "attributes_removed", removed.filter(a => a !== key));
        else this.set(base + "attributes", [...added, key]);
        this.filter = ""; this.render(container);
      });
    };
    search.oninput = showList;
    showList();
  }

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
