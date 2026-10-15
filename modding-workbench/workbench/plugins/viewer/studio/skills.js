// The Skills stage and inspector tab: the unit's skill tree laid out like the game's (rows of tiers, links between them), with the project's
// planned skills (registry `skills`, read through the API's `registry` values) next to the fixed ones the generator makes (`manifest.editor.skills`).
// A planned skill is a Draft (kept in the workbench only) or In game (`build`: the next Rebuild adds it to the mod). A skill can need all of
// some skills (a chain) or any N of them (`needs`), can be exclusive with others (taking one locks the rest, both ways), and can be locked by
// others one way (`locked_by`, such as a pact choice). A hidden skill has no cell: a script gives it, or he is made with it (`learned`). An art
// slot skill (`slot`) does what the held weapon's art for that slot does, edited per weapon (`weapons.<w>.arts.<slot>`). Tapping an empty cell in
// a planning row adds a skill there, tapping a skill opens it in the inspector. Each change is a registry edit of the whole skill (`skills.<id>`)
// or art, saved by the Jobs bar. With nothing selected, the inspector shows the point budget.

// Rows a tree has (the 10-row skills panel), and the first row planned skills may use (the rows above hold the fixed skills).
const ROWS = 10;
const FIRST_PLAN_ROW = 2;
// Levels a skill may have (a dump node for raised level caps has many), and how many effects and icons a search lists.
const MAX_LEVELS = 60;
const SEARCH_HITS = 24;
// Highest rank a hero reaches without mods. Each rank after the first gives one skill point.
const MAX_RANK = 50;
// Scope given to a new effect: the character itself.
const DEFAULT_SCOPE = "character_to_character_own";
// What a skill is in the tree: an ordinary skill, the Apex that ends a discipline row, or the Polymath capstone.
const ROLES = [["", "Skill"], ["apex", "Apex"], ["polymath", "Polymath"]];

// An effect's in-game line with its value: `%+n` is the signed value, `%n` the value.
function effectLine(text, value) {
  const v = Number(value) || 0, signed = (v > 0 ? "+" : "") + v;
  return (text || "").replace(/%\+n/g, signed).replace(/%n/g, String(v));
}

// A deep copy of a skill or an art, to edit and record.
const clone = x => structuredClone(x);
// A new weapon art, with no effects yet.
const blankArt = name => ({ name, description: "", effects: [] });

// Skill points a skill costs: one per level, none for a hidden skill (a script gives it).
function cost(s) { return s.hidden ? 0 : (s.levels || [[]]).length; }

export class SkillsTab {
  // `host` is the stage element the tree goes in.
  constructor(host, studio) {
    this.host = host; this.studio = studio; this.selected = null; this.level = 0; this.iconFilter = ""; this.weapon = null;
    // Each effect search's text, by the list it adds to (`level` or `art`), kept across redraws.
    this.filters = { level: "", art: "" };
    this.data = (studio.manifest.editor && studio.manifest.editor.skills) || null;
    host.addEventListener("click", e => this.onStageClick(e));
  }

  enabled() { return !!this.data && !!this.studio.tuning; }
  registry() { return (this.studio.tuning && this.studio.tuning.registry) || {}; }
  // Saved skills with the pending edits laid over them (a null edit removes a skill).
  skills() {
    const all = { ...(this.registry().skills || {}) };
    for (const [path, value] of Object.entries(this.studio.pending())) {
      if (!path.startsWith("skills.")) continue;
      const id = path.slice("skills.".length);
      if (value === null) delete all[id]; else all[id] = value;
    }
    return all;
  }
  // Weapons that build (those with animation sets), with their pending edits, in registry order: [key, weapon].
  weapons() { return Object.entries(this.studio.weapons()).filter(([, w]) => w.sets && Object.keys(w.sets).length); }
  rowName(row) { return this.data.rows[row] || `Row ${row + 1}`; }
  // Whether a skill needs only some of the skills it lists.
  anyOf(s) { return typeof s.needs === "number" && s.needs < (s.requires || []).length; }
  // Records a skill or an art and redraws a tick later: redrawing inside a change event pulls the focused input out mid-blur.
  put(id, skill) { this.putPath(`skills.${id}`, skill); }
  putPath(path, value) { this.studio.edits.registry[path] = value; this.studio.changed(); setTimeout(() => this.refresh()); }
  refresh() { this.renderTree(); if (this.container) this.render(this.container); }
  art(path) { return this.studio.panelArt(path); }
  iconPath(name) { return name ? (name.includes("/") ? name : `ui/campaign ui/skills/${name}`).toLowerCase() : ""; }
  // A new skill id no skill uses yet.
  newId() { const skills = this.skills(); let n = Object.keys(skills).length + 1; while (skills[`skill_${n}`]) n++; return `skill_${n}`; }

  // //////////////////////////////////////////////////////////////////////////////////////////////////
  // Tree

  renderTree() {
    if (!this.enabled()) { this.host.innerHTML = '<div class="note pad">This project has no skill data. Rebuild its gallery.</div>'; return; }
    const { esc } = window.UnitPanel, skills = this.skills(), cells = new Map();
    for (const f of this.data.fixed) cells.set(`${f.row}:${f.tier}`, { fixed: true, name: f.name, icon: f.icon });
    const cell = ([id, s]) => ({ id, ...s, icon: this.iconPath(s.icon) }), hidden = Object.entries(skills).filter(([, s]) => s.hidden);
    for (const entry of Object.entries(skills)) if (!entry[1].hidden) cells.set(`${entry[1].row}:${entry[1].tier}`, cell(entry));
    const tiers = Math.max(4, hidden.length + 1, ...[...cells.keys()].map(k => +k.split(":")[1] + 2));
    const node = (c, cell) => {
      const cls = c.fixed ? "fixed" : `${c.build ? "build" : "plan"}${c.role ? " " + c.role : ""}${c.id === this.selected ? " on" : ""}`;
      return `<button class="node ${cls}" ${c.id ? `data-id="${esc(c.id)}"` : ""} data-cell="${cell}" title="${esc(c.name)}">
        <span class="ring">${c.icon ? `<img src="${this.art(c.icon)}" alt="" onerror="this.remove()">` : ""}</span><span class="nm">${esc(c.name)}</span>
        ${c.fixed ? "" : `<span class="rk">${c.rank || 1}</span>`}${c.role ? `<span class="tag">${c.role}</span>` : c.slot ? '<span class="tag">art</span>' : ""}</button>`;
    };
    let html = `<div class="tree" style="grid-template-columns: 96px repeat(${tiers}, 92px)">`;
    for (let row = 0; row < ROWS; row++) {
      html += `<div class="tree-row">${esc(this.rowName(row))}</div>`;
      for (let tier = 0; tier < tiers; tier++) {
        const c = cells.get(`${row}:${tier}`);
        html += c ? node(c, `${row}:${tier}`)
          : row >= FIRST_PLAN_ROW ? `<button class="node empty" data-cell="${row}:${tier}" title="Add a skill here">+</button>` : "<span></span>";
      }
    }
    // Hidden skills sit in their own strip, in no particular order: the game never shows them.
    html += '<div class="tree-row">Hidden</div>';
    for (let i = 0; i < tiers; i++) {
      const h = hidden[i];
      html += h ? node(cell(h), "hidden")
        : i === hidden.length ? '<button class="node empty" data-cell="hidden" title="Add a hidden skill a script gives">+</button>' : "<span></span>";
    }
    html += "</div><svg class=\"links\"></svg>";
    this.host.innerHTML = html;
    this.drawLinks(skills);
  }

  // Lines from each skill to the skills it needs (solid for all of them, dashed for any N of them), and dotted lines between skills that lock
  // each other or one way.
  drawLinks(skills) {
    const svg = this.host.querySelector(".links"), box = this.host.getBoundingClientRect();
    svg.setAttribute("width", this.host.scrollWidth); svg.setAttribute("height", this.host.scrollHeight);
    const centre = id => { const el = this.host.querySelector(`[data-id="${CSS.escape(id)}"] .ring`); if (!el) return null;
      const r = el.getBoundingClientRect(); return [r.left - box.left + this.host.scrollLeft + r.width / 2, r.top - box.top + this.host.scrollTop + r.height / 2]; };
    const line = (from, to, cls) => { const a = centre(from), b = centre(to); return a && b ? `<line class="${cls}" x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}" />` : ""; };
    svg.innerHTML = Object.entries(skills).flatMap(([id, s]) => (s.requires || []).map(parent => line(parent, id, this.anyOf(s) ? "any" : "all"))
      .concat((s.exclusive || []).filter(other => other > id).map(other => line(id, other, "lock")))
      .concat((s.locked_by || []).map(other => line(other, id, "lock")))).join("");
  }

  onStageClick(e) {
    const node = e.target.closest(".node"); if (!node || node.classList.contains("fixed")) return;
    if (node.dataset.id) { this.selected = node.dataset.id; this.level = 0; }
    else {
      const hidden = node.dataset.cell === "hidden", [row, tier] = hidden ? [0, 0] : node.dataset.cell.split(":").map(Number);
      this.selected = this.newId(); this.level = 0;
      this.put(this.selected, { name: hidden ? "New hidden skill" : "New skill", description: "", icon: "", row, tier, rank: 1, levels: [[]], requires: [],
                                build: false, ...(hidden ? { hidden: true } : {}) });
    }
    this.studio.openSkills();
    this.refresh();
  }

  // //////////////////////////////////////////////////////////////////////////////////////////////////
  // Inspector

  // Rows of effects with their value, scope and a remove button. `list` names which list they edit: `level` or `art`.
  effectRows(effects, list) {
    const { esc, markupHtml } = window.UnitPanel, catalog = this.data.catalog, scopes = Object.entries(catalog.scopes).slice(0, 40);
    const scopeLabel = (key, text) => `${key.replace(/_/g, " ")}${text ? " " + text.replace(/\[\[[^\]]*\]\]|\\+n/g, " ").replace(/\s+/g, " ") : ""}`;
    return effects.map((e, i) => {
      const c = catalog.effects[e.effect] || { text: e.effect, icon: "" };
      const options = (scopes.some(([k]) => k === e.scope) ? scopes : [[e.scope, catalog.scopes[e.scope] || { text: "" }], ...scopes])
        .map(([k, v]) => `<option value="${esc(k)}" ${k === e.scope ? "selected" : ""}>${esc(scopeLabel(k, v.text))}</option>`).join("");
      return `<div class="effect" data-list="${list}" data-i="${i}">${c.icon ? `<img src="${this.art(c.icon)}" alt="" onerror="this.remove()">` : "<span></span>"}
        <span class="txt">${markupHtml(effectLine(c.text, e.value), p => this.art(p))}</span>
        <input type="number" step="any" data-f="value" value="${e.value}"><button class="mini" data-f="remove" aria-label="Remove">×</button>
        <select data-f="scope">${options}</select></div>`;
    }).join("");
  }

  // Checkbox chips of the other skills, ticked where `list` holds them.
  chips(others, list, attr) {
    const { esc } = window.UnitPanel;
    return `<div class="chips">${others.length ? others.map(([k, o]) => `<label class="need"><input type="checkbox" ${attr}="${esc(k)}" ${(list || []).includes(k) ? "checked" : ""}>${esc(o.name)}</label>`).join("")
      : "<span>No other planned skills.</span>"}</div>`;
  }

  render(container) {
    this.container = container;
    const { esc } = window.UnitPanel, skills = this.skills(), s = this.selected && skills[this.selected];
    if (!this.enabled()) { container.innerHTML = '<div class="note">This project has no skill data.</div>'; return; }
    if (!s) { container.innerHTML = this.overview(skills); return; }
    const id = this.selected, level = Math.min(this.level, s.levels.length - 1), effects = s.levels[level] || [];
    const others = Object.entries(skills).filter(([k]) => k !== id);
    const place = s.hidden ? "hidden" : `row ${s.row + 1}, tier ${s.tier + 1}`;
    container.innerHTML = `<div class="skill-head"><span class="ring">${s.icon ? `<img src="${this.art(this.iconPath(s.icon))}" alt="" onerror="this.remove()">` : ""}</span>
        <div><b>${esc(s.name)}</b><div class="note">Rank ${s.rank} · ${s.levels.length} level${s.levels.length > 1 ? "s" : ""} · ${place} · costs ${cost(s)}</div></div></div>
      <div class="tools seg"><button data-f="plan" class="${s.build ? "" : "on"}">Draft</button><button data-f="build" class="${s.build ? "on" : ""}">In game</button></div>
      <div class="note">${s.build ? "The next Rebuild adds this skill to the mod." : "A draft stays in the workbench. Switch to In game to add it to the mod on the next Rebuild."}</div>
      <div class="p-head">Skill</div>
      <div class="erow wide"><label>Name</label><input data-f="name" value="${esc(s.name)}"></div>
      <div class="erow wide"><label>Description</label><textarea data-f="description" rows="3">${esc(s.description || "")}</textarea></div>
      <div class="erow"><label>Unlock rank</label><input type="number" min="1" max="60" data-f="rank" value="${s.rank}"><span></span><span></span></div>
      ${s.hidden ? "" : `<div class="erow"><label>Row</label><input type="number" min="${FIRST_PLAN_ROW + 1}" max="${ROWS}" data-f="row" value="${s.row + 1}"><span class="hint">tier</span><input type="number" min="1" data-f="tier" value="${s.tier + 1}"></div>`}
      <div class="tools seg">${ROLES.map(([k, label]) => `<button data-role="${k}" class="${(s.role || "") === k ? "on" : ""}">${label}</button>`).join("")}</div>
      <label class="need"><input type="checkbox" data-f="hidden" ${s.hidden ? "checked" : ""}>Hidden: no cell in the tree, a script gives it</label>
      ${s.hidden ? `<label class="need"><input type="checkbox" data-f="learned" ${s.learned ? "checked" : ""}>He is made with it</label>` : ""}
      <div class="erow"><label>Art slot</label><input data-f="slot" placeholder="none (e.g. art_1)" value="${esc(s.slot || "")}"><span></span><span></span></div>
      <div class="p-head">Icon</div>
      <input class="attrSearch" data-f="iconSearch" placeholder="Search skill icons (sword, mount, lore...)" value="${esc(this.iconFilter)}"><div class="icons"></div>
      <div class="p-head">Levels</div>
      <div class="tools"><select data-f="level">${s.levels.map((_, i) => `<option value="${i}" ${i === level ? "selected" : ""}>Level ${i + 1}</option>`).join("")}</select>
        ${s.levels.length < MAX_LEVELS ? '<button data-f="addLevel">+ Level</button>' : ""}${s.levels.length > 1 ? '<button data-f="dropLevel">Remove this level</button>' : ""}</div>
      ${this.effectRows(effects, "level") || '<div class="note">No effects at this level yet.</div>'}
      <input class="attrSearch" data-list="level" placeholder="Add an effect (melee attack, leadership, upkeep...)" value="${esc(this.filters.level)}"><div class="hits" data-list="level"></div>
      ${s.slot ? this.artEditor(s.slot) : ""}
      <div class="p-head">Needs</div>
      ${this.chips(others, s.requires, "data-need")}
      ${(s.requires || []).length > 1 ? `<div class="erow wide"><label>Unlocks after</label><select data-f="needs">
        <option value="all" ${this.anyOf(s) ? "" : "selected"}>all of them</option>
        ${s.requires.slice(0, -1).map((_, i) => `<option value="${i + 1}" ${s.needs === i + 1 ? "selected" : ""}>any ${i + 1} of them</option>`).join("")}</select></div>` : ""}
      <div class="p-head">Exclusive with</div>
      <div class="note">Taking either skill locks the other.</div>
      ${this.chips(others, s.exclusive, "data-lock")}
      <div class="p-head">Locked by</div>
      <div class="note">Taking one of these locks this skill, but not the other way round (a pact choice locking the paths not taken).</div>
      ${this.chips(others, s.locked_by, "data-lockby")}
      <div class="tools"><button data-f="delete">Delete this skill</button><button data-f="close">Done</button></div>`;
    this.wire(container, id, s, level);
  }

  // The per-weapon art editor of an art slot skill: a tab per weapon, then the chosen weapon's art.
  artEditor(slot) {
    const { esc } = window.UnitPanel, weapons = this.weapons(), artOf = w => (w.arts || {})[slot];
    if (!weapons.some(([k]) => k === this.weapon)) this.weapon = weapons.length ? weapons[0][0] : null;
    const art = this.weapon && artOf(Object.fromEntries(weapons)[this.weapon]);
    const tabs = weapons.map(([k, w]) => `<button data-weapon="${esc(k)}" class="${k === this.weapon ? "on" : ""}">${artOf(w) ? "" : "! "}${esc(w.name || k)}</button>`).join("");
    return `<div class="p-head">Weapon arts</div>
      <div class="note">This skill does what the held weapon's art for slot <b>${esc(slot)}</b> does. Every weapon needs one, or the Rebuild stops. ! marks a weapon without.</div>
      <div class="tools">${tabs}</div>
      ${!art ? `<div class="tools"><button data-f="makeArt">Add an art for this weapon</button></div>` : `
        <div class="erow wide"><label>Art name</label><input data-f="artName" value="${esc(art.name || "")}"></div>
        <div class="erow wide"><label>Art text</label><textarea data-f="artDescription" rows="2">${esc(art.description || "")}</textarea></div>
        ${this.effectRows(art.effects || [], "art") || '<div class="note">No effects in this art yet.</div>'}
        <input class="attrSearch" data-list="art" placeholder="Add an effect to this art" value="${esc(this.filters.art)}"><div class="hits" data-list="art"></div>
        <div class="tools"><button data-f="dropArt">Remove this weapon's art</button></div>`}`;
  }

  // The point budget: points by rank against what the In game skills cost, per row, on the way to each Apex, and the art slots each weapon lacks.
  overview(skills) {
    const { esc } = window.UnitPanel, all = Object.entries(skills), built = all.filter(([, s]) => s.build);
    const counts = { build: built.length, plan: all.length - built.length };
    const sum = list => list.reduce((n, [, s]) => n + cost(s), 0);
    // The fixed skills (weapons, mounts and lores the generator makes) are always in game.
    const fixedCost = list => list.reduce((n, f) => n + (f.cost || 0), 0);
    const rows = [...Array(ROWS).keys()].map(r => {
      const here = all.filter(([, s]) => !s.hidden && s.row === r), fixed = fixedCost(this.data.fixed.filter(f => f.row === r));
      return here.length || fixed ? `<tr><td>${esc(this.rowName(r))}</td><td>${fixed + sum(here.filter(([, s]) => s.build))}</td><td>${fixed + sum(here)}</td></tr>` : "";
    }).join("");
    // A capstone's path is it plus every skill it needs, all the way down.
    const path = id => { const seen = new Set(), walk = k => { if (seen.has(k) || !skills[k]) return; seen.add(k); (skills[k].requires || []).forEach(walk); }; walk(id); return [...seen]; };
    const capstones = all.filter(([, s]) => s.role).map(([id, s]) => {
      const points = path(id).reduce((n, k) => n + cost(skills[k]), 0), rank = Math.max(points + 1, s.rank || 1);
      return `<tr><td>${esc(s.name)} <span class="hint">${s.role}</span></td><td>${points}</td><td>${rank > MAX_RANK ? `<b>${rank}</b>` : rank}</td></tr>`;
    }).join("");
    const slots = [...new Set(all.map(([, s]) => s.slot).filter(Boolean))].sort();
    const weapons = this.weapons(), missing = slots.map(slot => [slot, weapons.filter(([, w]) => !(w.arts || {})[slot]).map(([k, w]) => w.name || k)]).filter(([, m]) => m.length);
    const total = fixedCost(this.data.fixed) + sum(built), points = MAX_RANK - 1;
    return `<div class="note">Tap a + cell in rows ${FIRST_PLAN_ROW + 1} to ${ROWS} to plan a skill, + in Hidden for one a script gives, or tap a skill to edit it.</div>
      <div class="note">Gold rings are <b>In game</b>: the next Rebuild adds them to the mod. Dashed rings are <b>Drafts</b>, kept here only.
        ${counts.build} in game, ${counts.plan} drafts.</div>
      <div class="note">Lines: solid needs every linked skill, dashed needs some of them, dotted marks skills that lock each other or one way.</div>
      <div class="p-head">Point budget</div>
      <div class="note">Rank ${MAX_RANK} gives ${points} points. The In game skills cost ${total}${total > points ? `, <b>${total - points} more than he can take</b>` : `, ${points - total} to spare`}.
        Hidden skills are free. Art slots cost the same whatever the weapon, so one budget covers every weapon.</div>
      ${rows ? `<table class="budget"><tr><th>Row</th><th>In game</th><th>With drafts</th></tr>${rows}</table>` : ""}
      ${capstones ? `<div class="p-head">Capstones</div><div class="note">Points to take each one with every skill it needs, and the rank that takes.</div>
        <table class="budget"><tr><th>Skill</th><th>Points</th><th>Rank</th></tr>${capstones}</table>` : ""}
      ${slots.length ? `<div class="p-head">Weapon arts</div>${missing.length ? missing.map(([slot, names]) => `<div class="note">Slot <b>${esc(slot)}</b> has no art for ${names.map(esc).join(", ")}.</div>`).join("")
        : `<div class="note">Every weapon has an art for each of the ${slots.length} slots.</div>`}` : ""}`;
  }

  wire(container, id, s, level) {
    const q = f => container.querySelector(`[data-f="${f}"]`), copy = () => clone(s);
    const update = fn => { const next = copy(); fn(next); this.put(id, next); };
    const artPath = () => `weapons.${this.weapon}.arts.${s.slot}`;
    const updateArt = fn => {
      const next = { ...blankArt(s.name), ...clone((this.studio.weapons()[this.weapon].arts || {})[s.slot] || {}) }; fn(next); this.putPath(artPath(), next);
    };
    // An effect list edit, on this level's effects or the open art's.
    const editList = (list, fn) => list === "art" ? updateArt(a => fn(a.effects)) : update(n => fn(n.levels[level]));
    q("plan").onclick = () => update(n => n.build = false);
    q("build").onclick = () => update(n => n.build = true);
    q("name").onchange = e => update(n => n.name = e.target.value || "New skill");
    q("description").onchange = e => update(n => n.description = e.target.value);
    q("rank").onchange = e => update(n => n.rank = Math.max(1, +e.target.value || 1));
    container.querySelectorAll("[data-role]").forEach(b => b.onclick = () => update(n => { if (b.dataset.role) n.role = b.dataset.role; else delete n.role; }));
    q("hidden").onchange = e => update(n => { if (e.target.checked) n.hidden = true; else { delete n.hidden; delete n.learned; } });
    if (q("learned")) q("learned").onchange = e => update(n => { if (e.target.checked) n.learned = true; else delete n.learned; });
    q("slot").onchange = e => update(n => { const v = e.target.value.trim().replace(/[^a-z0-9_]/gi, "_").toLowerCase(); if (v) n.slot = v; else delete n.slot; });
    // Moving onto a taken cell is refused.
    const move = (row, tier) => {
      const taken = this.data.fixed.some(f => f.row === row && f.tier === tier) || Object.entries(this.skills()).some(([k, o]) => k !== id && !o.hidden && o.row === row && o.tier === tier);
      if (taken || row < FIRST_PLAN_ROW || row >= ROWS || tier < 0) { this.render(container); return; }
      update(n => { n.row = row; n.tier = tier; });
    };
    if (q("row")) { q("row").onchange = e => move(+e.target.value - 1, s.tier); q("tier").onchange = e => move(s.row, +e.target.value - 1); }
    q("level").onchange = e => { this.level = +e.target.value; this.render(container); };
    if (q("addLevel")) q("addLevel").onclick = () => { this.level = s.levels.length; update(n => n.levels.push(clone(n.levels[n.levels.length - 1] || []))); };
    if (q("dropLevel")) q("dropLevel").onclick = () => { this.level = Math.max(0, level - 1); update(n => n.levels.splice(level, 1)); };
    container.querySelectorAll(".effect").forEach(row => {
      const i = +row.dataset.i, list = row.dataset.list;
      row.querySelector('[data-f="value"]').onchange = e => editList(list, l => l[i].value = +e.target.value || 0);
      row.querySelector('[data-f="scope"]').onchange = e => editList(list, l => l[i].scope = e.target.value);
      row.querySelector('[data-f="remove"]').onclick = () => editList(list, l => l.splice(i, 1));
    });
    const toggle = (list, key, on) => { const x = new Set(list || []); on ? x.add(key) : x.delete(key); return [...x]; };
    container.querySelectorAll("[data-need]").forEach(box => box.onchange = () => update(n => {
      n.requires = toggle(n.requires, box.dataset.need, box.checked);
      if (typeof n.needs === "number" && n.needs >= n.requires.length) delete n.needs;
    }));
    if (q("needs")) q("needs").onchange = e => update(n => { if (e.target.value === "all") delete n.needs; else n.needs = +e.target.value; });
    // Exclusive pairs are kept on both skills. A one-way lock lives on the locked skill only.
    container.querySelectorAll("[data-lock]").forEach(box => box.onchange = () => {
      const other = box.dataset.lock, pair = clone(this.skills()[other]);
      pair.exclusive = toggle(pair.exclusive, id, box.checked);
      this.studio.edits.registry[`skills.${other}`] = pair;
      update(n => n.exclusive = toggle(n.exclusive, other, box.checked));
    });
    container.querySelectorAll("[data-lockby]").forEach(box => box.onchange = () => update(n => n.locked_by = toggle(n.locked_by, box.dataset.lockby, box.checked)));
    // Deleting a skill also takes it out of the other skills' needs and locks.
    q("delete").onclick = () => {
      for (const [other, o] of Object.entries(this.skills())) {
        if (other === id || ![o.requires, o.exclusive, o.locked_by].some(l => (l || []).includes(id))) continue;
        const next = clone(o);
        for (const key of ["requires", "exclusive", "locked_by"]) if (next[key]) next[key] = next[key].filter(k => k !== id);
        if (typeof next.needs === "number" && next.needs >= next.requires.length) delete next.needs;
        this.studio.edits.registry[`skills.${other}`] = next;
      }
      this.selected = null; this.studio.edits.registry[`skills.${id}`] = null; this.studio.changed(); this.refresh();
    };
    q("close").onclick = () => { this.selected = null; this.refresh(); };

    // The art editor: weapon tabs, adding and removing the open weapon's art, and its name and text.
    container.querySelectorAll("[data-weapon]").forEach(b => b.onclick = () => { this.weapon = b.dataset.weapon; this.render(container); });
    if (q("makeArt")) q("makeArt").onclick = () => this.putPath(artPath(), blankArt(s.name));
    if (q("dropArt")) q("dropArt").onclick = () => this.putPath(artPath(), null);
    if (q("artName")) q("artName").onchange = e => updateArt(a => a.name = e.target.value);
    if (q("artDescription")) q("artDescription").onchange = e => updateArt(a => a.description = e.target.value);

    // Icon and effect searches list their hits under the box.
    const { esc, markupHtml } = window.UnitPanel, catalog = this.data.catalog;
    const icons = () => {
      this.iconFilter = q("iconSearch").value; const f = this.iconFilter.toLowerCase();
      const hits = f ? catalog.icons.filter(n => n.includes(f)).slice(0, SEARCH_HITS) : [];
      container.querySelector(".icons").innerHTML = hits.map(n => `<button data-icon="${esc(n)}" title="${esc(n)}"><img src="${this.art(this.iconPath(n))}" alt="" onerror="this.parentNode.remove()"></button>`).join("");
      container.querySelectorAll("[data-icon]").forEach(b => b.onclick = () => { this.iconFilter = ""; update(n => n.icon = b.dataset.icon); });
    };
    const effects = input => {
      const list = input.dataset.list, f = input.value.toLowerCase(), box = container.querySelector(`.hits[data-list="${list}"]`);
      this.filters[list] = input.value;
      const hits = f ? Object.entries(catalog.effects).filter(([k, e]) => e.text.toLowerCase().includes(f) || k.includes(f)).slice(0, SEARCH_HITS) : [];
      box.innerHTML = hits.map(([k, e]) => `<button data-effect="${esc(k)}" title="${esc(k)}">${e.icon ? `<img src="${this.art(e.icon)}" alt="" onerror="this.remove()">` : ""}<span>${markupHtml(effectLine(e.text, 1), p => this.art(p))}</span></button>`).join("");
      box.querySelectorAll("[data-effect]").forEach(b => b.onclick = () => { this.filters[list] = ""; editList(list, l => l.push({ effect: b.dataset.effect, scope: DEFAULT_SCOPE, value: 1 })); });
    };
    q("iconSearch").oninput = icons;
    container.querySelectorAll("input[data-list]").forEach(input => { input.oninput = () => effects(input); effects(input); });
    icons();
  }
}
