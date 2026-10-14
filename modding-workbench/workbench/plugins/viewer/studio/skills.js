// The Skills stage and inspector tab: the unit's skill tree laid out like the game's (rows of tiers, links between them), with the project's
// planned skills (registry `skills`, read through the API's `registry` values) next to the fixed ones the generator makes (`manifest.editor.skills`).
// A planned skill is a Draft (kept in the workbench only) or In game (`build`: the next Rebuild adds it to the mod). A skill can need all of
// some skills (a chain) or any N of them (`needs`), and can be exclusive with others: taking one locks the rest, both ways. Tapping an empty cell
// in a planning row adds a skill there, tapping a skill opens it in the inspector. Each change is a registry edit of the whole skill
// (`skills.<id>`), saved by the Jobs bar.

// Rows a tree has, and the first row planned skills may use (the rows above hold the fixed skills).
const ROWS = 6;
const FIRST_PLAN_ROW = 2;
// Levels a skill may have, and how many effects and icons a search lists.
const MAX_LEVELS = 3;
const SEARCH_HITS = 24;
// Scope given to a new effect: the character itself.
const DEFAULT_SCOPE = "character_to_character_own";

// An effect's in-game line with its value: `%+n` is the signed value, `%n` the value.
function effectLine(text, value) {
  const v = Number(value) || 0, signed = (v > 0 ? "+" : "") + v;
  return (text || "").replace(/%\+n/g, signed).replace(/%n/g, String(v));
}

export class SkillsTab {
  // `host` is the stage element the tree goes in.
  constructor(host, studio) {
    this.host = host; this.studio = studio; this.selected = null; this.level = 0; this.iconFilter = ""; this.effectFilter = "";
    this.data = (studio.manifest.editor && studio.manifest.editor.skills) || null;
    host.addEventListener("click", e => this.onStageClick(e));
  }

  enabled() { return !!this.data && !!this.studio.tuning; }
  // Saved skills with the pending edits laid over them (a null edit removes a skill).
  skills() {
    const saved = (this.studio.tuning && this.studio.tuning.registry && this.studio.tuning.registry.skills) || {}, all = { ...saved };
    for (const [path, value] of Object.entries({ ...this.studio.savedRegistry, ...this.studio.edits.registry })) {
      if (!path.startsWith("skills.")) continue;
      const id = path.slice("skills.".length);
      if (value === null) delete all[id]; else all[id] = value;
    }
    return all;
  }
  // Whether a skill needs only some of the skills it lists.
  anyOf(s) { return typeof s.needs === "number" && s.needs < (s.requires || []).length; }
  // Records a skill and redraws a tick later: redrawing inside a change event pulls the focused input out mid-blur.
  put(id, skill) { this.studio.edits.registry[`skills.${id}`] = skill; this.studio.changed(); setTimeout(() => this.refresh()); }
  refresh() { this.renderTree(); if (this.container) this.render(this.container); }
  art(path) { return this.studio.panelArt(path); }
  iconPath(name) { return name ? (name.includes("/") ? name : `ui/campaign ui/skills/${name}`).toLowerCase() : ""; }

  // //////////////////////////////////////////////////////////////////////////////////////////////////
  // Tree

  renderTree() {
    if (!this.enabled()) { this.host.innerHTML = '<div class="note pad">This project has no skill data. Rebuild its gallery.</div>'; return; }
    const { esc } = window.UnitPanel, skills = this.skills(), cells = new Map();
    for (const f of this.data.fixed) cells.set(`${f.row}:${f.tier}`, { fixed: true, name: f.name, icon: f.icon });
    for (const [id, s] of Object.entries(skills)) cells.set(`${s.row}:${s.tier}`, { id, ...s, icon: this.iconPath(s.icon) });
    const tiers = Math.max(4, ...[...cells.keys()].map(k => +k.split(":")[1] + 2));
    let html = `<div class="tree" style="grid-template-columns: 96px repeat(${tiers}, 92px)">`;
    for (let row = 0; row < ROWS; row++) {
      html += `<div class="tree-row">${esc(this.data.rows[row] || `Row ${row + 1}`)}</div>`;
      for (let tier = 0; tier < tiers; tier++) {
        const c = cells.get(`${row}:${tier}`);
        if (c) {
          const cls = c.fixed ? "fixed" : `${c.build ? "build" : "plan"}${c.id === this.selected ? " on" : ""}`;
          html += `<button class="node ${cls}" ${c.id ? `data-id="${esc(c.id)}"` : ""} data-cell="${row}:${tier}" title="${esc(c.name)}">
            <span class="ring">${c.icon ? `<img src="${this.art(c.icon)}" alt="" onerror="this.remove()">` : ""}</span><span class="nm">${esc(c.name)}</span>
            ${c.fixed ? "" : `<span class="rk">${c.rank || 1}</span>`}</button>`;
        } else {
          html += row >= FIRST_PLAN_ROW ? `<button class="node empty" data-cell="${row}:${tier}" title="Add a skill here">+</button>` : `<span></span>`;
        }
      }
    }
    html += "</div><svg class=\"links\"></svg>";
    this.host.innerHTML = html;
    this.drawLinks(skills);
  }

  // Lines from each skill to the skills it needs (solid for all of them, dashed for any N of them), and dotted lines between exclusive skills.
  drawLinks(skills) {
    const svg = this.host.querySelector(".links"), box = this.host.getBoundingClientRect();
    svg.setAttribute("width", this.host.scrollWidth); svg.setAttribute("height", this.host.scrollHeight);
    const centre = id => { const el = this.host.querySelector(`[data-id="${CSS.escape(id)}"] .ring`); if (!el) return null;
      const r = el.getBoundingClientRect(); return [r.left - box.left + this.host.scrollLeft + r.width / 2, r.top - box.top + this.host.scrollTop + r.height / 2]; };
    const line = (from, to, cls) => { const a = centre(from), b = centre(to); return a && b ? `<line class="${cls}" x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}" />` : ""; };
    svg.innerHTML = Object.entries(skills).flatMap(([id, s]) => (s.requires || []).map(parent => line(parent, id, this.anyOf(s) ? "any" : "all"))
      .concat((s.exclusive || []).filter(other => other > id).map(other => line(id, other, "lock")))).join("");
  }

  onStageClick(e) {
    const node = e.target.closest(".node"); if (!node || node.classList.contains("fixed")) return;
    if (node.dataset.id) { this.selected = node.dataset.id; this.level = 0; }
    else {
      const [row, tier] = node.dataset.cell.split(":").map(Number), skills = this.skills();
      let n = Object.keys(skills).length + 1; while (skills[`skill_${n}`]) n++;
      this.selected = `skill_${n}`; this.level = 0;
      this.put(this.selected, { name: "New skill", description: "", icon: "", row, tier, rank: 1, levels: [[]], requires: [], build: false });
    }
    this.studio.openSkills();
    this.refresh();
  }

  // //////////////////////////////////////////////////////////////////////////////////////////////////
  // Inspector

  render(container) {
    this.container = container;
    const { esc, markupHtml } = window.UnitPanel, skills = this.skills(), s = this.selected && skills[this.selected];
    if (!this.enabled()) { container.innerHTML = '<div class="note">This project has no skill data.</div>'; return; }
    if (!s) {
      const counts = Object.values(skills).reduce((c, x) => (c[x.build ? "build" : "plan"]++, c), { build: 0, plan: 0 });
      container.innerHTML = `<div class="note">Tap a + cell in rows ${FIRST_PLAN_ROW + 1} to ${ROWS} to plan a skill, or tap a skill to edit it.</div>
        <div class="note">Gold rings are <b>In game</b>: the next Rebuild adds them to the mod. Dashed rings are <b>Drafts</b>, kept here only.
        ${counts.build} in game, ${counts.plan} drafts.</div>
        <div class="note">Lines: solid needs every linked skill, dashed needs some of them, dotted marks skills that lock each other.</div>`;
      return;
    }
    const catalog = this.data.catalog, id = this.selected, level = Math.min(this.level, s.levels.length - 1), effects = s.levels[level] || [];
    const scopes = Object.entries(catalog.scopes).slice(0, 40);
    const scopeLabel = (key, text) => `${key.replace(/_/g, " ")}${text ? " " + text.replace(/\[\[[^\]]*\]\]|\\+n/g, " ").replace(/\s+/g, " ") : ""}`;
    const effectRows = effects.map((e, i) => {
      const c = catalog.effects[e.effect] || { text: e.effect, icon: "" };
      const options = (scopes.some(([k]) => k === e.scope) ? scopes : [[e.scope, catalog.scopes[e.scope] || { text: "" }], ...scopes])
        .map(([k, v]) => `<option value="${esc(k)}" ${k === e.scope ? "selected" : ""}>${esc(scopeLabel(k, v.text))}</option>`).join("");
      return `<div class="effect" data-i="${i}">${c.icon ? `<img src="${this.art(c.icon)}" alt="" onerror="this.remove()">` : "<span></span>"}
        <span class="txt">${markupHtml(effectLine(c.text, e.value), p => this.art(p))}</span>
        <input type="number" step="any" data-f="value" value="${e.value}"><button class="mini" data-f="remove" aria-label="Remove">×</button>
        <select data-f="scope">${options}</select></div>`;
    }).join("");
    const others = Object.entries(skills).filter(([k]) => k !== id);
    container.innerHTML = `<div class="skill-head"><span class="ring">${s.icon ? `<img src="${this.art(this.iconPath(s.icon))}" alt="" onerror="this.remove()">` : ""}</span>
        <div><b>${esc(s.name)}</b><div class="note">Rank ${s.rank} · ${s.levels.length} level${s.levels.length > 1 ? "s" : ""} · row ${s.row + 1}, tier ${s.tier + 1}</div></div></div>
      <div class="tools seg"><button data-f="plan" class="${s.build ? "" : "on"}">Draft</button><button data-f="build" class="${s.build ? "on" : ""}">In game</button></div>
      <div class="note">${s.build ? "The next Rebuild adds this skill to the mod." : "A draft stays in the workbench. Switch to In game to add it to the mod on the next Rebuild."}</div>
      <div class="p-head">Skill</div>
      <div class="erow wide"><label>Name</label><input data-f="name" value="${esc(s.name)}"></div>
      <div class="erow wide"><label>Description</label><textarea data-f="description" rows="3">${esc(s.description || "")}</textarea></div>
      <div class="erow"><label>Unlock rank</label><input type="number" min="1" max="60" data-f="rank" value="${s.rank}"><span></span><span></span></div>
      <div class="erow"><label>Row</label><input type="number" min="${FIRST_PLAN_ROW + 1}" max="${ROWS}" data-f="row" value="${s.row + 1}"><span class="hint">tier</span><input type="number" min="1" data-f="tier" value="${s.tier + 1}"></div>
      <div class="p-head">Icon</div>
      <input class="attrSearch" data-f="iconSearch" placeholder="Search skill icons (sword, mount, lore...)" value="${esc(this.iconFilter)}"><div class="icons"></div>
      <div class="p-head">Levels</div>
      <div class="tools">${s.levels.map((_, i) => `<button data-level="${i}" class="${i === level ? "on" : ""}">Level ${i + 1}</button>`).join("")}
        ${s.levels.length < MAX_LEVELS ? '<button data-f="addLevel">+ Level</button>' : ""}${s.levels.length > 1 ? '<button data-f="dropLevel">Remove this level</button>' : ""}</div>
      ${effectRows || '<div class="note">No effects at this level yet.</div>'}
      <input class="attrSearch" data-f="effectSearch" placeholder="Add an effect (melee attack, leadership, upkeep...)" value="${esc(this.effectFilter)}"><div class="hits"></div>
      <div class="p-head">Needs</div>
      <div class="chips">${others.length ? others.map(([k, o]) => `<label class="need"><input type="checkbox" data-need="${esc(k)}" ${(s.requires || []).includes(k) ? "checked" : ""}>${esc(o.name)}</label>`).join("") : "<span>No other planned skills.</span>"}</div>
      ${(s.requires || []).length > 1 ? `<div class="erow wide"><label>Unlocks after</label><select data-f="needs">
        <option value="all" ${this.anyOf(s) ? "" : "selected"}>all of them</option>
        ${s.requires.slice(0, -1).map((_, i) => `<option value="${i + 1}" ${s.needs === i + 1 ? "selected" : ""}>any ${i + 1} of them</option>`).join("")}</select></div>` : ""}
      <div class="p-head">Exclusive with</div>
      <div class="note">Taking either skill locks the other.</div>
      <div class="chips">${others.length ? others.map(([k, o]) => `<label class="need"><input type="checkbox" data-lock="${esc(k)}" ${(s.exclusive || []).includes(k) ? "checked" : ""}>${esc(o.name)}</label>`).join("") : "<span>No other planned skills.</span>"}</div>
      <div class="tools"><button data-f="delete">Delete this skill</button><button data-f="close">Done</button></div>`;
    this.wire(container, id, s, level);
  }

  wire(container, id, s, level) {
    const q = f => container.querySelector(`[data-f="${f}"]`), copy = () => JSON.parse(JSON.stringify(s));
    const update = fn => { const next = copy(); fn(next); this.put(id, next); };
    q("plan").onclick = () => update(n => n.build = false);
    q("build").onclick = () => update(n => n.build = true);
    q("name").onchange = e => update(n => n.name = e.target.value || "New skill");
    q("description").onchange = e => update(n => n.description = e.target.value);
    q("rank").onchange = e => update(n => n.rank = Math.max(1, +e.target.value || 1));
    // Moving onto a taken cell is refused.
    const move = (row, tier) => {
      const taken = this.data.fixed.some(f => f.row === row && f.tier === tier) || Object.entries(this.skills()).some(([k, o]) => k !== id && o.row === row && o.tier === tier);
      if (taken || row < FIRST_PLAN_ROW || row >= ROWS || tier < 0) { this.render(container); return; }
      update(n => { n.row = row; n.tier = tier; });
    };
    q("row").onchange = e => move(+e.target.value - 1, s.tier);
    q("tier").onchange = e => move(s.row, +e.target.value - 1);
    container.querySelectorAll("[data-level]").forEach(b => b.onclick = () => { this.level = +b.dataset.level; this.render(container); });
    if (q("addLevel")) q("addLevel").onclick = () => { this.level = s.levels.length; update(n => n.levels.push(JSON.parse(JSON.stringify(n.levels[n.levels.length - 1] || [])))); };
    if (q("dropLevel")) q("dropLevel").onclick = () => { this.level = Math.max(0, level - 1); update(n => n.levels.splice(level, 1)); };
    container.querySelectorAll(".effect").forEach(row => {
      const i = +row.dataset.i;
      row.querySelector('[data-f="value"]').onchange = e => update(n => n.levels[level][i].value = +e.target.value || 0);
      row.querySelector('[data-f="scope"]').onchange = e => update(n => n.levels[level][i].scope = e.target.value);
      row.querySelector('[data-f="remove"]').onclick = () => update(n => n.levels[level].splice(i, 1));
    });
    container.querySelectorAll("[data-need]").forEach(box => box.onchange = () => update(n => {
      const set = new Set(n.requires || []); box.checked ? set.add(box.dataset.need) : set.delete(box.dataset.need); n.requires = [...set];
      if (typeof n.needs === "number" && n.needs >= n.requires.length) delete n.needs;
    }));
    if (q("needs")) q("needs").onchange = e => update(n => { if (e.target.value === "all") delete n.needs; else n.needs = +e.target.value; });
    // Exclusive pairs are kept on both skills.
    container.querySelectorAll("[data-lock]").forEach(box => box.onchange = () => {
      const other = box.dataset.lock, all = this.skills(), pair = JSON.parse(JSON.stringify(all[other]));
      const set = (list, key, on) => { const x = new Set(list || []); on ? x.add(key) : x.delete(key); return [...x]; };
      pair.exclusive = set(pair.exclusive, id, box.checked);
      this.studio.edits.registry[`skills.${other}`] = pair;
      update(n => n.exclusive = set(n.exclusive, other, box.checked));
    });
    // Deleting a skill also takes it out of the other skills' needs and locks.
    q("delete").onclick = () => {
      for (const [other, o] of Object.entries(this.skills())) {
        if (other === id || !((o.requires || []).includes(id) || (o.exclusive || []).includes(id))) continue;
        const next = JSON.parse(JSON.stringify(o));
        next.requires = (next.requires || []).filter(k => k !== id); next.exclusive = (next.exclusive || []).filter(k => k !== id);
        if (typeof next.needs === "number" && next.needs >= next.requires.length) delete next.needs;
        this.studio.edits.registry[`skills.${other}`] = next;
      }
      this.selected = null; this.studio.edits.registry[`skills.${id}`] = null; this.studio.changed(); this.refresh();
    };
    q("close").onclick = () => { this.selected = null; this.refresh(); };

    // Icon and effect searches list their hits under the box.
    const { esc, markupHtml } = window.UnitPanel, catalog = this.data.catalog;
    const icons = () => {
      this.iconFilter = q("iconSearch").value; const f = this.iconFilter.toLowerCase();
      const hits = f ? catalog.icons.filter(n => n.includes(f)).slice(0, SEARCH_HITS) : [];
      container.querySelector(".icons").innerHTML = hits.map(n => `<button data-icon="${esc(n)}" title="${esc(n)}"><img src="${this.art(this.iconPath(n))}" alt="" onerror="this.parentNode.remove()"></button>`).join("");
      container.querySelectorAll("[data-icon]").forEach(b => b.onclick = () => { this.iconFilter = ""; update(n => n.icon = b.dataset.icon); });
    };
    const effects = () => {
      this.effectFilter = q("effectSearch").value; const f = this.effectFilter.toLowerCase();
      const hits = f ? Object.entries(catalog.effects).filter(([k, e]) => e.text.toLowerCase().includes(f) || k.includes(f)).slice(0, SEARCH_HITS) : [];
      container.querySelector(".hits").innerHTML = hits.map(([k, e]) => `<button data-effect="${esc(k)}" title="${esc(k)}">${e.icon ? `<img src="${this.art(e.icon)}" alt="" onerror="this.remove()">` : ""}<span>${markupHtml(effectLine(e.text, 1), p => this.art(p))}</span></button>`).join("");
      container.querySelectorAll("[data-effect]").forEach(b => b.onclick = () => { this.effectFilter = ""; update(n => n.levels[level].push({ effect: b.dataset.effect, scope: DEFAULT_SCOPE, value: 1 })); });
    };
    q("iconSearch").oninput = icons; q("effectSearch").oninput = effects;
    icons(); effects();
  }
}
