// The Stats inspector tab: the in-game unit card of the open form (`manifest.panels`, built by the project's generator with `ttc.unit_panel`).
// It shows the unit on its own. "Compare with ..." draws another unit into the bars (`studio.compare`): its vanilla equivalent, or on a mounted
// form the same weapon's form on foot. "Show ..." then swaps which unit the card is about.
//
// The project's own card is edited in place (through `FormEditor`): tap a number to change it. Weapon Strength and Missile Strength open into the
// values they add up from, and the health bar into the health bonus. Abilities and attributes come off with their x. "+ Ability" and "+ Attribute"
// open a picker with every one the game has. A unit stat change goes to every form of the weapon or to this form only, as picked at the top.
import { FormEditor, MELEE_FIELDS, MISSILE_FIELDS } from "./form_editor.js";

// Card rows that edit a unit stat: panel stat -> its field.
const UNIT_ROWS = { armour: "armour", leadership: "morale", melee_attack: "melee_attack", melee_defence: "melee_defence", charge_bonus: "charge_bonus" };
// Card rows that edit a missile value directly: panel stat -> its field.
const MISSILE_ROWS = { ammunition: "ammo", range: "effective_range" };
// The lists the card adds to and removes from: kind -> [button label, picker title, search hint].
const LISTS = { abilities: ["+ Ability", "Add abilities", "Search the game's unit abilities"], attributes: ["+ Attribute", "Add attributes", "Search the game's attributes"] };

// Loc text as one plain line: no markup tags, inline images or line breaks.
const plain = text => (text || "").replace(/\[\[[^\]]*\]\]|\{\{[^}]*\}\}/g, "").replace(/(\\+n)+/g, " ").replace(/\s+/g, " ").trim();
// Card rows that open into the values they add up from: panel stat -> [path group, fields].
const GROUPS = { weapon_strength: ["melee", MELEE_FIELDS], missile_strength: ["missile", MISSILE_FIELDS.filter(([field]) => !["effective_range", "ammo"].includes(field))] };

// One picker row's body: an ability's type, numbers and the effects of each phase, then its description. An attribute's text is its effect.
function pickBody(kind, a, art) {
  const { esc, markupHtml } = window.UnitPanel, t = kind === "abilities" ? a.tip : null;
  if (!t) return `<b>${esc(a.name)}</b>${a.text ? `<span class="fx-text">${markupHtml(a.text, art)}</span>` : ""}`;
  const phases = t.phases.map(p => {
    const head = p.name || p.duration ? `<span class="fx-sub">${markupHtml(p.name || "", art)}${p.duration ? ` ${p.name ? "for" : "For"} ${esc(p.duration)}` : ""}</span>` : "";
    const effects = p.effects.map(([label, value]) => `<span>${markupHtml(label, art)} <b class="${value.startsWith("-") ? "down" : "up"}">${esc(value)}</b></span>`)
      .concat(p.attributes.map(([name, good]) => `<span>${esc(name)} <b class="${good ? "up" : "down"}">${good ? "gained" : "lost"}</b></span>`));
    return head || effects.length ? `<span class="fx">${head}${effects.join("")}</span>` : "";
  }).join("");
  return `<span class="fx-title"><b>${esc(a.name)}</b><span class="note">${markupHtml(t.type, art)}${t.passive ? " · Passive" : ""}</span></span>
    ${t.numbers.length ? `<span class="fx-nums">${t.numbers.map(([label, value]) => `${esc(label)} <b>${esc(value)}</b>`).join(" · ")}</span>` : ""}
    ${phases}${t.text ? `<span class="note">${esc(plain(t.text))}</span>` : ""}`;
}

// Attribute chips. Against a compared unit: red for what only the card's unit has, green for what only the compared unit has. `removable` adds
// an x to each of the card unit's own.
function attributeChips(u, o, art, removable) {
  const { attributeHtml, esc } = window.UnitPanel;
  const chip = (a, cls) => removable ? `<span class="chip">${attributeHtml(a, art, cls)}<button class="mini" data-drop="attributes|${esc(a.key)}" aria-label="Remove ${esc(a.name)}">×</button></span>` : attributeHtml(a, art, cls);
  if (!o) return u.attributes.map(a => chip(a, "")).join("") || "<span>None</span>";
  const mine = new Set(u.attributes.map(a => a.key)), theirs = new Set(o.attributes.map(a => a.key));
  const list = u.attributes.map(a => chip(a, theirs.has(a.key) ? "" : "down")).concat(o.attributes.filter(a => !mine.has(a.key)).map(a => attributeHtml(a, art, "up")));
  return list.length ? list.join("") : "<span>None</span>";
}

export class StatsTab {
  constructor(studio) {
    this.studio = studio; this.flip = false; this.open = new Set();
    this.editor = new FormEditor(studio);
    // The "+ Ability" and "+ Attribute" picker.
    this.picker = document.createElement("div"); this.picker.className = "overlay"; this.picker.hidden = true;
    document.body.append(this.picker);
  }

  // What the open form can be compared with: {key, label, panel}. Its vanilla equivalent, and on a mount the same weapon's form on foot, with
  // that form's unsaved edits.
  targets(entry) {
    const panels = this.studio.manifest.panels, out = [];
    if (entry.versus && panels[entry.versus]) out.push({ key: "vanilla", label: panels[entry.versus].name, short: "vanilla", panel: panels[entry.versus] });
    const f = this.editor.form(entry.unit), forms = (this.studio.manifest.editor || {}).forms || {};
    const foot = f && f.mount !== "foot" && Object.keys(forms).find(k => forms[k].weapon === f.weapon && forms[k].mount === "foot");
    const footEntry = foot && this.studio.manifest.entries.find(e => e.unit === foot);
    if (footEntry && panels[foot]) out.push({ key: "foot", label: footEntry.name.split(" - ")[1] || footEntry.name, short: "on foot", panel: this.editor.preview(foot) });
    return out;
  }

  // Whether the open entry has a card to show.
  available(entry) { return !!(entry && entry.unit && this.studio.manifest.panels && this.studio.manifest.panels[entry.unit]); }
  // Edits were saved: they keep showing until a rebuild.
  saved() { this.editor.saved(); }

  render(container) {
    const entry = this.studio.stage.entry;
    if (!this.available(entry)) { container.innerHTML = '<div class="note">No unit card for this entry. Pick one of the project\'s forms.</div>'; return; }
    const { esc, cardHtml, hpHtml, statsHtml, abilitiesHtml } = window.UnitPanel;
    const panels = this.studio.manifest.panels, art = this.studio.panelArt, mine = this.editor.preview(entry.unit);
    const targets = this.targets(entry), target = targets.find(t => t.key === this.studio.compare), compare = !!target;
    const [u, o] = compare && this.flip ? [target.panel, mine] : [mine, compare ? target.panel : null];
    const f = !(compare && this.flip) && this.editor.enabled() && this.editor.form(entry.unit);
    const others = targets.filter(t => t !== target).map(t => `<button data-against="${t.key}">Compare with ${esc(t.label)}</button>`).join("");
    const vs = !targets.length ? "" : compare
      ? `<div class="vs">Compared with <b>${esc(target.label)}</b><button data-t="flip">${this.flip ? "Show this form" : `Show ${target.short}`}</button><button data-against="">Alone</button>${others}</div>`
      : `<div class="vs">${others}</div>`;
    const weaponName = entry.name.split(" - ")[0], formName = entry.name.split(" - ")[1] || "";
    const scope = f ? `<div class="vs scope">Changes apply to <button data-scope="form" class="${this.editor.scope(f) === "form" ? "on" : ""}">${esc(formName)} only</button>
      <button data-scope="weapon" class="${this.editor.scope(f) === "weapon" ? "on" : ""}">every ${esc(weaponName)} form${f.mount === "foot" ? "" : ", by the same amount"}</button></div>` : "";
    const health = f && this.open.has("hp") ? this.subRow("unit.bonus_hit_points", "Health bonus per model", this.editor.unitValue(f, "bonus_hit_points"), this.override(f, "bonus_hit_points")) : "";
    container.innerHTML = `<div class="panel"><div class="p-title">${esc(u.name)}</div>${vs}${scope}
      <div class="p-sub"><span>${esc(u.caste)} · ${esc(u.class)}${u.stats.tier ? ` · tier ${u.stats.tier}` : ""}</span></div>
      <div class="p-top">${cardHtml(u, art)}<div><div class="meta">${esc(u.key)}</div><div ${f ? 'data-open="hp" class="opener" title="Edit the health bonus"' : ""}>${hpHtml(u, o, art)}</div>${health}</div></div>
      <div class="p-head">Stats${f ? '<span class="note">tap a number to change it</span>' : ""}</div>${f ? this.statRows(f, u, o) : statsHtml(u.stats, o ? o.stats : {}, art)}
      <div class="p-head">Abilities</div><div class="abilities">${f ? u.abilities.map(a => `<span class="chip">${abilitiesHtml([a], art)}<button class="mini" data-drop="abilities|${esc(a.key)}" aria-label="Remove ${esc(a.name)}">×</button></span>`).join("")
        + this.adder("abilities") : abilitiesHtml(u.abilities, art)}</div>
      ${o ? `<div class="vs">${esc(o.name)}</div><div class="abilities">${abilitiesHtml(o.abilities, art)}</div>` : ""}
      <div class="p-head">Attributes</div><div class="chips">${attributeChips(u, o, art, !!f)}${f ? this.adder("attributes") : ""}</div>
      <div class="p-head">Game keys</div><div class="keys">${(entry.info || entry.sets || []).map(line => `<div>${esc(line)}</div>`).join("")}</div></div>`;
    this.wire(container, f);
  }

  // The "+ Ability" or "+ Attribute" button of a list.
  adder(kind) { return `<button class="mini add" data-adding="${kind}">${LISTS[kind][0]}</button>`; }

  // Adds an ability or attribute to the weapon, or takes it off. One the weapon added comes off its list, any other goes on its removed list.
  toggle(f, kind, key, on) {
    const { added, removed } = this.editor.lists(f, kind), path = `weapons.${f.weapon}.${kind}`;
    if (on) { if (removed.includes(key)) this.editor.set(path + "_removed", removed.filter(a => a !== key)); else this.editor.set(path, [...added, key]); }
    else if (added.includes(key)) this.editor.set(path, added.filter(a => a !== key)); else this.editor.set(path + "_removed", [...removed, key]);
  }

  // The picker: every ability or attribute the game has in one scrolling list, searched by name, key or text. Tapping one adds it, or takes it off
  // again when the form has it. It stays open so several can be picked in a row.
  openPicker(container, f, kind) {
    const { esc } = window.UnitPanel, art = this.studio.panelArt, box = this.picker, catalog = this.editor.editor[kind] || {};
    const rows = Object.entries(catalog).map(([key, a]) => {
      const body = pickBody(kind, a, art), icon = a.icon ? `<img loading="lazy" src="${art(a.icon)}" alt="">` : "<span></span>";
      const find = `${a.name} ${key} ${plain(body.replace(/<[^>]+>/g, " "))}`.toLowerCase();
      return `<button class="pick" title="${esc(key)}" data-key="${esc(key)}" data-find="${esc(find)}">${icon}<span class="fx-body">${body}</span><span class="state"></span></button>`;
    }).join("");
    box.innerHTML = `<div class="dialog pickbox"><div class="d-head"><b>${LISTS[kind][1]}</b><button class="mini" data-x="close">Done</button></div>
      <input data-f="find" placeholder="${LISTS[kind][2]}" autocomplete="off"><div class="note" data-count></div><div class="pick-list">${rows}</div></div>`;
    box.hidden = false;
    const list = box.querySelector(".pick-list"), find = box.querySelector('[data-f="find"]'), count = box.querySelector("[data-count]");
    const mark = () => {
      const has = new Set(this.editor.preview(this.studio.stage.entry.unit)[kind].map(a => a.key));
      for (const b of list.children) {
        const on = has.has(b.dataset.key);
        b.classList.toggle("added", on); b.querySelector(".state").textContent = on ? "On this form. Tap to remove." : "";
      }
    };
    const filter = () => {
      const words = find.value.toLowerCase().split(/\s+/).filter(Boolean);
      let shown = 0;
      for (const b of list.children) { b.hidden = !words.every(w => b.dataset.find.includes(w)); shown += !b.hidden; }
      count.textContent = `${shown} of ${list.children.length}`;
    };
    const close = () => { box.hidden = true; box.innerHTML = ""; document.removeEventListener("keydown", onKey); };
    const onKey = e => { if (e.key === "Escape") close(); };
    document.addEventListener("keydown", onKey);
    box.onclick = e => { if (e.target === box) close(); };
    box.querySelector('[data-x="close"]').onclick = close;
    list.onclick = e => {
      const b = e.target.closest("[data-key]");
      if (!b) return;
      this.toggle(f, kind, b.dataset.key, !b.classList.contains("added")); mark(); this.render(container);
    };
    find.oninput = filter; mark(); filter(); find.focus();
  }

  // Whether this form sets its own value for a unit stat.
  override(f, field) {
    const p = this.studio.pending(), path = `weapons.${f.weapon}.forms.${f.mount}.${field}`;
    return path in p ? p[path] !== null : f.overrides.includes(field);
  }

  // The card's stat rows, each number an input. Grouped rows open into their parts.
  statRows(f, u, o) {
    const { STATS, barHtml, cmpHtml, esc } = window.UnitPanel, art = this.studio.panelArt, s = u.stats, other = o ? o.stats : {};
    return STATS.filter(([k]) => s[k] !== undefined || other[k] !== undefined).map(([k, name, img, max]) => {
      const v = s[k] ?? 0, icon = `<img src="${art(`ui/skins/default/${img}.png`)}" alt="">`, tail = `${cmpHtml(v, other[k])}${barHtml(v, other[k], max)}`;
      if (UNIT_ROWS[k]) {
        const field = UNIT_ROWS[k], own = this.override(f, field);
        return `<div class="stat edit">${icon}<span>${name}${own ? ` <button class="mini" data-reset="${f.weapon}|${f.mount}|${field}" title="This form has its own value. Use the weapon's again.">form ×</button>` : ""}</span>
          <input class="v" type="number" step="any" data-path="unit.${field}" value="${v}">${tail}</div>`;
      }
      if (MISSILE_ROWS[k] && f.missile) return `<div class="stat edit">${icon}<span>${name}</span><input class="v" type="number" step="any" data-path="missile.${MISSILE_ROWS[k]}" value="${v}">${tail}</div>`;
      if (GROUPS[k] && (k !== "missile_strength" || f.missile)) {
        const [group, fields] = GROUPS[k], opened = this.open.has(k);
        const value = field => group === "melee" ? this.editor.meleeValue(f, field) : this.editor.missileValue(f, field);
        const parts = opened ? fields.map(([field, label]) => this.subRow(`${group}.${field}`, label, value(field), false)).join("")
          + (group === "melee" ? `<div class="note sub">${f.own_melee ? `Its own melee weapon, copied from ${esc(f.melee_template)}` : `Uses the game's ${esc(f.melee_template)}. A change gives it its own copy`}. Shared by every form of the weapon.</div>` : "") : "";
        return `<div class="stat edit opener" data-open="${k}">${icon}<span>${name} <span class="caret">${opened ? "▾" : "▸"}</span></span><span class="v">${v}</span>${tail}</div>${parts}`;
      }
      return `<div class="stat edit">${icon}<span>${name}</span><span class="v">${v}</span>${tail}</div>`;
    }).join("");
  }

  // One editable value under a grouped row (or under the health bar).
  subRow(path, label, value, own) {
    const { esc } = window.UnitPanel;
    return `<div class="stat sub"><span></span><span>${esc(label)}${own ? " <em>(this form)</em>" : ""}</span><input class="v" type="number" step="any" data-path="${path}" value="${Math.round(value * 100) / 100}"></div>`;
  }

  wire(container, f) {
    // Redraws wait a tick: redrawing inside a change event pulls the focused input out mid-blur.
    const q = t => container.querySelector(`[data-t="${t}"]`), redraw = () => setTimeout(() => this.render(container));
    const flip = q("flip");
    if (flip) flip.onclick = () => { this.flip = !this.flip; redraw(); };
    container.querySelectorAll("[data-against]").forEach(b => b.onclick = () => { this.studio.compare = b.dataset.against || null; this.flip = false; redraw(); });
    if (!f) return;
    container.querySelectorAll("[data-scope]").forEach(b => b.onclick = () => { this.editor.setScope(f, b.dataset.scope); redraw(); });
    container.querySelectorAll("[data-open]").forEach(el => el.onclick = e => {
      if (e.target.closest("input, button")) return;
      const key = el.dataset.open; this.open.has(key) ? this.open.delete(key) : this.open.add(key); redraw();
    });
    container.querySelectorAll("input[data-path]").forEach(input => input.onchange = () => {
      if (input.value === "" || !isFinite(+input.value)) return;
      this.editor.edit(f, input.dataset.path, +input.value); redraw();
    });
    container.querySelectorAll("[data-reset]").forEach(b => b.onclick = () => {
      const [weapon, mount, field] = b.dataset.reset.split("|"); this.editor.set(`weapons.${weapon}.forms.${mount}.${field}`, null); redraw();
    });
    for (const b of container.querySelectorAll("[data-drop]")) b.onclick = () => { const [kind, key] = b.dataset.drop.split("|"); this.toggle(f, kind, key, false); redraw(); };
    for (const b of container.querySelectorAll("[data-adding]")) b.onclick = () => this.openPicker(container, f, b.dataset.adding);
  }
}
