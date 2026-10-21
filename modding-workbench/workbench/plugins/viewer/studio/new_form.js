// The New form dialog and the forms still waiting for a rebuild or their animation sets.
//
// A new form is a new weapon in the registry (`weapons.<key>`), copied from one of the project's weapons, with an animation set per mount picked
// from the gallery's `manifest.editor.new_form`. A set on his own skeleton goes in the weapon's `sets` and builds on the next rebuild. A set on
// another skeleton waits in its `retarget` until Claude retargets it: "Hand off to Claude" marks it there with a note. The registry's weapons come
// through the API's `registry` values.

// Sets the picker lists at most.
const SET_HITS = 30;

export class NewForm {
  constructor(studio, onChange) {
    // `state` is the open dialog: {kind: "new", ...the fields} or {kind: "weapon", key}. `onChange` redraws the forms list.
    this.studio = studio; this.onChange = onChange; this.state = null;
    this.data = studio.manifest.editor && studio.manifest.editor.new_form;
    this.index = new Map((this.data ? this.data.sets : []).map(row => [row[0], row]));
    this.box = document.createElement("div"); this.box.className = "overlay"; this.box.hidden = true;
    this.box.onclick = e => { if (e.target === this.box) this.close(); };
    document.body.append(this.box);
  }

  // Whether the project can make forms: the gallery lists the sets and the API reads the registry's weapons.
  enabled() { return !!(this.data && this.studio.tuning && this.studio.tuning.registry && this.studio.tuning.registry.weapons); }

  // The registry's weapons with the saved and unsaved edits: whole weapons, and their `retarget.<mount>` and `arts.<slot>` entries.
  weapons() {
    const all = structuredClone(this.enabled() ? this.studio.tuning.registry.weapons : {});
    for (const [path, value] of Object.entries(this.studio.pending())) {
      const [root, key, field, mount, ...rest] = path.split(".");
      if (root !== "weapons" || rest.length) continue;
      if (field === undefined) { if (value === null) delete all[key]; else all[key] = structuredClone(value); }
      else if ((field === "retarget" || field === "arts") && mount && all[key]) {
        all[key][field] = { ...all[key][field], [mount]: value };
        if (value === null) delete all[key][field][mount];
      }
    }
    return all;
  }

  // Forms the gallery does not show yet: {weapon, name, mount, state}, state being "rebuild", "retarget" or "handoff".
  waiting() {
    if (!this.enabled()) return [];
    const built = new Set(Object.values(this.studio.manifest.editor.forms).map(f => `${f.weapon}|${f.mount}`)), out = [];
    for (const [key, weapon] of Object.entries(this.weapons())) for (const mount of Object.keys(this.data.mounts)) {
      if (built.has(`${key}|${mount}`)) continue;
      const retarget = (weapon.retarget || {})[mount];
      if ((weapon.sets || {})[mount]) out.push({ weapon: key, name: weapon.name, mount, state: "rebuild" });
      else if (retarget) out.push({ weapon: key, name: weapon.name, mount, state: retarget.handoff ? "handoff" : "retarget" });
    }
    return out;
  }

  openNew() {
    const from = Object.keys(this.weapons())[0];
    this.state = { kind: "new", name: "", description: "", from, sets: {}, picking: null, filter: "", any: false };
    this.render();
  }
  openWeapon(key) { this.state = { kind: "weapon", key, confirm: false }; this.render(); }
  close() { this.state = null; this.box.hidden = true; this.box.innerHTML = ""; }
  // Records registry edits, then redraws the dialog and the forms list.
  edit(changes) { Object.assign(this.studio.edits.registry, changes); this.studio.changed(); this.onChange(); }

  render() {
    this.box.hidden = false;
    this.box.innerHTML = `<div class="dialog">${this.state.kind === "new" ? this.newHtml() : this.weaponHtml()}</div>`;
    if (this.state.kind === "new") this.wireNew(); else this.wireWeapon();
  }

  // A set's line: its name, whether it is on his skeleton, and the vanilla units that play it.
  setHtml(name) {
    const { esc } = window.UnitPanel, [, skeleton, mount, users] = this.index.get(name) || [name, "?", "", []];
    const fits = skeleton === this.data.skeleton ? '<span class="ok">his skeleton</span>' : `<span class="warn">${esc(skeleton)}: needs retargeting</span>`;
    return `<span class="set"><span>${esc(name)}</span>${fits}${mount ? `<span class="note">rides ${esc(mount)}</span>` : ""}
      ${users.length ? `<span class="note">Played by ${[...new Set(users.map(u => u[1]))].map(esc).join(", ")}</span>` : ""}</span>`;
  }

  // Whether a set suits a mount: riders of the same mount set, or for a mount carried as a prop (the disc), sets naming it.
  fits(row, mount) {
    const m = this.data.mounts[mount];
    if (row[2] !== m.mount) return false;
    return m.word ? row[0].includes(m.word) : !/_wm_/.test(row[0]);
  }

  newHtml() {
    const { esc } = window.UnitPanel, s = this.state, weapons = this.weapons();
    const rows = Object.entries(this.data.mounts).map(([mount, m]) => `<div class="mrow"><b>${esc(m.name)}</b>
        <div>${s.sets[mount] ? this.setHtml(s.sets[mount]) : '<span class="note">Not on this mount</span>'}</div>
        <span><button class="mini" data-pick="${mount}">${s.picking === mount ? "Close" : "Pick a set"}</button>${s.sets[mount] ? ` <button class="mini" data-clear="${mount}">×</button>` : ""}</span></div>
      ${s.picking === mount ? `<div class="picker"><label class="note"><input type="checkbox" data-f="any" ${s.any ? "checked" : ""}> Show sets for every mount</label>
        <input class="attrSearch" data-f="filter" placeholder="Search the game's sets or the units that play them (whip, slaanesh...)" value="${esc(s.filter)}"><div class="hits"></div></div>` : ""}`).join("");
    return `<div class="d-head"><b>New form</b><button class="mini" data-x="close">Close</button></div>
      <label>Name <input data-f="name" value="${esc(s.name)}" placeholder="Whip"></label>
      <label>Description <textarea data-f="description" rows="2" placeholder="A line for the campaign's loadout picker">${esc(s.description)}</textarea></label>
      <label>Start from <select data-f="from">${Object.entries(weapons).map(([k, w]) => `<option value="${esc(k)}" ${k === s.from ? "selected" : ""}>${esc(w.name)}</option>`).join("")}</select></label>
      <div class="note">It copies that weapon's models, stats, attributes, abilities and missile weapon. Change them on the new form after a rebuild.</div>
      <div class="p-head">Animation sets</div>
      <div class="note">Pick a set for each mount he should use the weapon on. A set on his skeleton (${esc(this.data.skeleton)}) builds as it is. A set on another
        skeleton needs retargeting first, so that mount waits until you hand it off to Claude and it is done.</div>
      ${rows}
      <div class="d-foot"><button data-x="create" class="on" ${s.name.trim() && Object.keys(s.sets).length ? "" : "disabled"}>Create form</button>
        <span class="note">Then Save, and Rebuild to see it.</span></div>`;
  }

  wireNew() {
    const s = this.state, q = sel => this.box.querySelector(sel), redraw = () => setTimeout(() => this.render());
    q('[data-x="close"]').onclick = () => this.close();
    q('[data-f="name"]').oninput = e => { s.name = e.target.value; q('[data-x="create"]').disabled = !(s.name.trim() && Object.keys(s.sets).length); };
    q('[data-f="description"]').oninput = e => { s.description = e.target.value; };
    q('[data-f="from"]').onchange = e => { s.from = e.target.value; };
    this.box.querySelectorAll("[data-pick]").forEach(b => b.onclick = () => { s.picking = s.picking === b.dataset.pick ? null : b.dataset.pick; s.filter = ""; s.any = false; redraw(); });
    this.box.querySelectorAll("[data-clear]").forEach(b => b.onclick = () => { delete s.sets[b.dataset.clear]; redraw(); });
    q('[data-x="create"]').onclick = () => this.create();
    const search = q('[data-f="filter"]');
    if (!search) return;
    const any = q('[data-f="any"]'), hits = q(".hits"), { esc } = window.UnitPanel;
    const list = () => {
      s.filter = search.value; const words = search.value.toLowerCase().split(/\s+/).filter(Boolean);
      const found = this.data.sets.filter(row => (s.any || this.fits(row, s.picking))
        && words.every(w => row[0].includes(w) || row[3].some(u => u[1].toLowerCase().includes(w))));
      // His own skeleton's sets first.
      found.sort((a, b) => (a[1] !== this.data.skeleton) - (b[1] !== this.data.skeleton));
      hits.innerHTML = found.slice(0, SET_HITS).map(row => `<button data-set="${esc(row[0])}">${this.setHtml(row[0])}</button>`).join("")
        + (found.length > SET_HITS ? `<div class="note">${found.length - SET_HITS} more. Type to narrow them down.</div>` : found.length ? "" : '<div class="note">No set matches.</div>');
      hits.querySelectorAll("[data-set]").forEach(b => b.onclick = () => { s.sets[s.picking] = b.dataset.set; s.picking = null; redraw(); });
    };
    any.onchange = () => { s.any = any.checked; list(); };
    search.oninput = list; list(); search.focus();
  }

  // Adds the new weapon as an unsaved edit: the chosen weapon's copy with the new name, sets and vanilla equivalents (a unit playing each set).
  create() {
    const s = this.state, weapons = this.weapons(), weapon = structuredClone(weapons[s.from]);
    for (const field of ["sets", "vanilla", "forms", "retarget"]) delete weapon[field];
    // His missile weapon key comes from the new weapon's key.
    if (weapon.missile) delete weapon.missile.key;
    Object.assign(weapon, { name: s.name.trim(), description: s.description.trim() || weapon.description, workbench: true, sets: {}, retarget: {}, vanilla: {} });
    for (const [mount, name] of Object.entries(s.sets)) {
      const [, skeleton, , users] = this.index.get(name);
      if (skeleton === this.data.skeleton) weapon.sets[mount] = name; else weapon.retarget[mount] = { set: name, skeleton };
      if (users.length) weapon.vanilla[mount] = users[0][0];
    }
    for (const field of ["retarget", "vanilla"]) if (!Object.keys(weapon[field]).length) delete weapon[field];
    const base = s.name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "") || "form";
    let key = base;
    for (let n = 2; key in weapons; n++) key = `${base}_${n}`;
    this.edit({ [`weapons.${key}`]: weapon });
    this.openWeapon(key);
  }

  weaponHtml() {
    const { esc } = window.UnitPanel, key = this.state.key, weapon = this.weapons()[key];
    if (!weapon) return `<div class="d-head"><b>Form removed</b><button class="mini" data-x="close">Close</button></div><div class="note">Save to remove it from the registry.</div>`;
    const built = new Set(Object.values(this.studio.manifest.editor.forms).filter(f => f.weapon === key).map(f => f.mount));
    const rows = Object.entries(this.data.mounts).map(([mount, m]) => {
      const set = (weapon.sets || {})[mount], retarget = (weapon.retarget || {})[mount];
      if (!set && !retarget) return "";
      let state;
      if (built.has(mount)) state = '<span class="ok">Built. Open it from the Forms list.</span>';
      else if (set) state = '<span class="note">Builds on the next Save and Rebuild.</span>';
      else if (retarget.handoff) state = `<span class="warn">Handed off to Claude.</span><div class="note">Tell Claude "pick up the workbench hand-offs". Your note: ${esc(retarget.note || "none")}</div>
        <button class="mini" data-back="${mount}">Take it back</button>`;
      else state = `<span class="warn">Waiting for retargeting from ${esc(retarget.skeleton)} to ${esc(this.data.skeleton)}.</span>
        <textarea data-note="${mount}" rows="2" placeholder="Anything Claude should know (what to keep, what looks wrong...)"></textarea>
        <button class="mini" data-hand="${mount}">Hand off to Claude</button>`;
      return `<div class="mrow"><b>${esc(m.name)}</b><div>${this.setHtml(set || retarget.set)}<div>${state}</div></div><span></span></div>`;
    }).join("");
    return `<div class="d-head"><b>${esc(weapon.name)}</b><button class="mini" data-x="close">Close</button></div>
      <div class="note">${esc(weapon.description || "")}</div><div class="p-head">Mounts</div>${rows}
      ${weapon.workbench ? `<div class="d-foot"><button data-x="delete">${this.state.confirm ? "Click again to delete it" : "Delete this form"}</button></div>` : ""}`;
  }

  wireWeapon() {
    const key = this.state.key, q = sel => this.box.querySelector(sel), redraw = () => setTimeout(() => this.render());
    q('[data-x="close"]').onclick = () => this.close();
    const retargetOf = mount => this.weapons()[key].retarget[mount];
    this.box.querySelectorAll("[data-hand]").forEach(b => b.onclick = () => {
      const mount = b.dataset.hand, note = q(`[data-note="${mount}"]`).value.trim();
      this.edit({ [`weapons.${key}.retarget.${mount}`]: { ...retargetOf(mount), handoff: true, ...(note ? { note } : {}) } }); redraw();
    });
    this.box.querySelectorAll("[data-back]").forEach(b => b.onclick = () => {
      const { handoff, note, ...rest } = retargetOf(b.dataset.back);
      this.edit({ [`weapons.${key}.retarget.${b.dataset.back}`]: rest }); redraw();
    });
    const del = q('[data-x="delete"]');
    if (del) del.onclick = () => {
      if (!this.state.confirm) { this.state.confirm = true; redraw(); return; }
      const saved = this.studio.tuning.registry.weapons || {}, edits = this.studio.edits.registry;
      // A form that was never saved just drops its edits.
      for (const path of Object.keys(edits)) if (path === `weapons.${key}` || path.startsWith(`weapons.${key}.`)) delete edits[path];
      if (key in saved || `weapons.${key}` in this.studio.savedRegistry) edits[`weapons.${key}`] = null;
      this.studio.changed(); this.onChange(); this.close();
    };
  }
}
