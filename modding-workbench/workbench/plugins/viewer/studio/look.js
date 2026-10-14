// The Look inspector tab: his outfit, his hood and extra pieces such as a hat, set per weapon and shared by every mount of that weapon
// (`weapons.<weapon>.body`, `.hood` and `.pieces`). Outfits come from the registry's `model.bodies`, and any other humanoid model of the game can be
// added as an outfit or a piece. Every choice shows live on the stage through `studio.live`. The Jobs bar saves the edits.
import { stem } from "./live_models.js";

// Models a search lists at most.
const MODEL_HITS = 30;

// The metadata a new outfit's body slot carries, as on the vanilla outfits.
const BODY_META = ["audio_entity_type:wh_human_male_LH", "audio_armour_type:leather"];

// A key or file name in words: "grey_wizard" -> "Grey Wizard".
const words = key => key.replace(/_\d+$/, "").split("_").filter(Boolean).map(w => w[0].toUpperCase() + w.slice(1)).join(" ");

export class LookTab {
  constructor(studio) {
    // `adding` is "outfit" or "piece" while its model search is open, `filter` its search text.
    this.studio = studio; this.adding = null; this.filter = "";
    this.look = studio.manifest.editor && studio.manifest.editor.look;
    // The stage shows the chosen outfit, head and pieces.
    studio.live.sources.push(f => this.wanted(f));
    studio.live.listeners.push(() => this.refresh());
  }

  enabled() { return !!(this.look && this.studio.tuning); }
  pending() { return { ...this.studio.savedRegistry, ...this.studio.edits.registry }; }
  // A look field of the form's weapon with the pending edits.
  value(f, field) { const p = this.pending(), path = `weapons.${f.weapon}.${field}`; return path in p ? p[path] : f.look[field]; }
  // Every outfit: the gallery's, then any added since (slot -> model).
  bodies() {
    const all = { ...this.look.bodies };
    for (const [path, body] of Object.entries(this.pending())) {
      if (path.startsWith("model.bodies.") && body) all[path.slice("model.bodies.".length)] = Object.fromEntries(Object.entries(body).map(([slot, piece]) => [slot, piece[0]]));
    }
    return all;
  }
  hoodless() { return !!this.look.head.hoodless; }

  // The slots the stage should show for the form: its outfit's (every other outfit's slot empty), its head and its pieces (removed ones empty).
  // What has not changed since the gallery was built is marked built.
  wanted(f) {
    if (!this.enabled()) return {};
    const bodies = this.bodies(), key = this.value(f, "body"), body = bodies[key] || {}, out = {}, hood = this.value(f, "hood") !== false;
    for (const outfit of Object.values(bodies)) for (const slot of Object.keys(outfit)) out[slot] = null;
    for (const [slot, model] of Object.entries(body)) out[slot] = { model, attach: "", built: key === f.look.body };
    if (this.hoodless()) out.head = { model: hood ? this.look.head.hooded : this.look.head.hoodless, attach: "", built: hood === (f.look.hood !== false) };
    for (const slot of Object.keys(f.look.pieces)) out[slot] = null;
    for (const [slot, piece] of Object.entries(this.value(f, "pieces") || {})) {
      out[slot] = { model: piece[0], attach: "", built: !!f.look.pieces[slot] && f.look.pieces[slot][0] === piece[0] };
    }
    return out;
  }

  // Records registry edits and shows them.
  set(changes) { Object.assign(this.studio.edits.registry, changes); this.studio.changed(); this.studio.live.sync(); this.refresh(); }

  // Redraws the tab when it is open.
  refresh() { const body = document.getElementById("inspBody"); if (body && body.dataset.tab === "look") setTimeout(() => this.render(body)); }

  // A slot's loading or failed preview, in words.
  state(slots) {
    const { esc } = window.UnitPanel, live = this.studio.live;
    if (slots.some(s => live.loading.has(s))) return '<div class="note">Loading...</div>';
    const failed = slots.find(s => live.failed.has(s));
    return failed ? `<div class="note warn">No preview: ${esc(live.failed.get(failed))}. It still builds on Rebuild.</div>` : "";
  }

  // The model search of "+ Another outfit" or "+ Add a piece".
  search(f) {
    const { esc } = window.UnitPanel, box = document.createElement("div");
    box.className = "picker";
    box.innerHTML = `<input class="attrSearch" placeholder="Search the game's humanoid models (hat, helmet, cape, wizard...)" value="${esc(this.filter)}"><div class="hits"></div>`;
    const input = box.querySelector("input"), hits = box.querySelector(".hits");
    const list = () => {
      this.filter = input.value; const terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
      const found = terms.length ? this.look.models.filter(p => terms.every(w => p.includes(w))).slice(0, MODEL_HITS) : [];
      hits.innerHTML = found.map(p => `<button data-model="${esc(p)}"><span>${esc(stem(p))}</span><span class="note">${esc(p.split("/").slice(3, -1).join("/"))}</span></button>`).join("")
        || (terms.length ? '<div class="note">No model matches.</div>' : "");
      hits.querySelectorAll("[data-model]").forEach(b => b.onclick = () => this.pick(f, b.dataset.model));
    };
    input.oninput = list; list(); setTimeout(() => input.focus());
    return box;
  }

  // Adds the picked model as an outfit (and wears it) or as a piece.
  pick(f, model) {
    const base = `weapons.${f.weapon}.`;
    if (this.adding === "outfit") {
      const key = stem(model).replace(/[^a-z0-9_]/g, "_");
      this.set({ [`model.bodies.${key}`]: { body: [model, ...BODY_META] }, [base + "body"]: key });
    } else {
      const pieces = { ...(this.value(f, "pieces") || {}) };
      let n = 1;
      while (`piece_${n}` in pieces) n++;
      pieces[`piece_${n}`] = [model];
      this.set({ [base + "pieces"]: pieces });
    }
    this.adding = null; this.filter = "";
  }

  render(container) {
    container.innerHTML = "";
    const live = this.studio.live, f = live.form(), entry = this.studio.stage.entry;
    if (!this.enabled() || !f || !live.model()) { container.innerHTML = '<div class="note">Nothing to dress on this entry. Pick one of the project\'s forms.</div>'; return; }
    const { esc } = window.UnitPanel, weaponName = entry.name.split(" - ")[0], base = `weapons.${f.weapon}.`;
    const bodies = this.bodies(), current = this.value(f, "body"), hood = this.value(f, "hood") !== false, pieces = this.value(f, "pieces") || {};
    container.insertAdjacentHTML("beforeend", `<div class="note adj-intro">His look for every ${esc(weaponName)} form, on foot and on each mount. Changes show on the stage
      straight away. Save keeps them, and Rebuild puts them in the mod.</div>`);

    const outfit = document.createElement("div"); outfit.className = "adj-card";
    outfit.innerHTML = `<div class="adj-head"><b>Outfit</b><button class="mini" data-add="outfit">${this.adding === "outfit" ? "Close" : "+ Another outfit"}</button></div>
      <div class="look-bodies">${Object.keys(bodies).map(k => `<button data-body="${esc(k)}" class="${k === current ? "on" : ""}">${esc(words(k))}</button>`).join("")}</div>
      ${this.state(Object.keys(bodies[current] || {}))}`;
    container.append(outfit);
    if (this.adding === "outfit") outfit.append(this.search(f));
    outfit.querySelectorAll("[data-body]").forEach(b => b.onclick = () => this.set({ [base + "body"]: b.dataset.body }));

    if (this.hoodless()) {
      const card = document.createElement("div"); card.className = "adj-card";
      card.innerHTML = `<div class="adj-head"><b>Hood</b><span class="tools seg"><button data-hood="on" class="${hood ? "on" : ""}">Up</button><button data-hood="off" class="${hood ? "" : "on"}">Down</button></span></div>
        ${this.state(["head"])}`;
      container.append(card);
      card.querySelectorAll("[data-hood]").forEach(b => b.onclick = () => this.set({ [base + "hood"]: b.dataset.hood === "on" }));
    }

    const extra = document.createElement("div"); extra.className = "adj-card";
    extra.innerHTML = `<div class="adj-head"><b>Extra pieces</b><button class="mini" data-add="piece">${this.adding === "piece" ? "Close" : "+ Add a piece"}</button></div>
      ${Object.keys(pieces).length ? "" : '<div class="note">None. Add a hat, a helmet, a cape and so on.</div>'}
      ${Object.entries(pieces).map(([slot, piece]) => `<div class="look-piece"><span class="adj-model">${esc(stem(piece[0]))}</span><button class="mini" data-drop="${esc(slot)}" aria-label="Remove">×</button></div>
        ${this.state([slot])}`).join("")}`;
    container.append(extra);
    if (this.adding === "piece") extra.append(this.search(f));
    extra.querySelectorAll("[data-drop]").forEach(b => b.onclick = () => {
      const rest = { ...pieces }; delete rest[b.dataset.drop];
      this.set({ [base + "pieces"]: Object.keys(rest).length ? rest : null });
    });
    container.querySelectorAll("[data-add]").forEach(b => b.onclick = () => { this.adding = this.adding === b.dataset.add ? null : b.dataset.add; this.filter = ""; this.render(container); });
  }
}
