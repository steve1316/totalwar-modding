// The Look inspector tab: his outfit, his hood and extra pieces such as a hat, set per weapon and shared by every mount of that weapon
// (`weapons.<weapon>.body`, `.hood` and `.pieces`). Outfits come from the registry's `model.bodies`, and any other humanoid model of the game can be
// added as an outfit or a piece, each search hit and piece with a thumbnail (kept on the server once drawn), and a hovered search hit tried on. Every choice shows live on the
// stage through `studio.live`. The Jobs bar saves the edits.
import { stem } from "./live_models.js";
import { Thumbnails } from "./thumbs.js";

// Rows the model list adds at a time: the first ones when it opens, then more as it scrolls near its end.
const LIST_CHUNK = 60;

// Milliseconds a search waits for typing to pause, so thumbnails are only drawn for what is searched in the end.
const TYPING_PAUSE = 300;

// Milliseconds the pointer rests on a search hit before he tries it on, so passing over the list loads nothing.
const HOVER_PAUSE = 1000;

// The slot a hovered piece is tried on in.
const HOVER_SLOT = "piece_hover";

// The metadata a new outfit's body slot carries, as on the vanilla outfits.
const BODY_META = ["audio_entity_type:wh_human_male_LH", "audio_armour_type:leather"];

// A key or file name in words: "grey_wizard" -> "Grey Wizard".
const words = key => key.replace(/_\d+$/, "").split("_").filter(Boolean).map(w => w[0].toUpperCase() + w.slice(1)).join(" ");

export class LookTab {
  constructor(studio) {
    // `adding` is "outfit" or "piece" while its model search is open, `filter` its search text, `hovering` the search hit he is trying on.
    this.studio = studio; this.adding = null; this.filter = ""; this.hovering = null;
    this.look = studio.manifest.editor && studio.manifest.editor.look;
    // The models a search lists, by name.
    this.models = this.look ? [...this.look.models].sort((a, b) => stem(a).localeCompare(stem(b))) : [];
    this.thumbs = new Thumbnails(studio);
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
    // A hovered search hit is tried on: a piece next to the rest, an outfit in place of his.
    out[HOVER_SLOT] = this.hovering && this.adding === "piece" ? { model: this.hovering, attach: "" } : null;
    if (this.hovering && this.adding === "outfit") {
      for (const slot of Object.keys(body)) out[slot] = null;
      out.body = { model: this.hovering, attach: "" };
    }
    return out;
  }

  // Records registry edits and shows them.
  set(changes) { Object.assign(this.studio.edits.registry, changes); this.studio.changed(); this.studio.live.sync(); this.refresh(); }

  // Redraws the tab when it is open, unless a search is open: redrawing would rebuild its rows under the pointer and take the typing focus.
  refresh() { const body = document.getElementById("inspBody"); if (body && body.dataset.tab === "look" && !this.adding) setTimeout(() => this.render(body)); }

  // A slot's loading or failed preview, in words.
  state(slots) {
    const { esc } = window.UnitPanel, live = this.studio.live;
    if (slots.some(s => live.loading.has(s))) return '<div class="note">Loading...</div>';
    const failed = slots.find(s => live.failed.has(s));
    return failed ? `<div class="note warn">No preview: ${esc(live.failed.get(failed))}. It still builds on Rebuild.</div>` : "";
  }

  // The model list of "+ Another outfit" or "+ Add a piece": every humanoid model by name, narrowed by the search words.
  search(f) {
    const { esc } = window.UnitPanel, box = document.createElement("div");
    box.className = "picker";
    box.innerHTML = `<input class="attrSearch" placeholder="Search the game's humanoid models (hat, helmet, cape, wizard...)" value="${esc(this.filter)}">
      <div class="note look-count"></div><div class="hits look-hits"></div>`;
    const input = box.querySelector("input"), hits = box.querySelector(".hits"), count = box.querySelector(".look-count");
    let found = [], shown = 0;
    // Adds the next rows of the found models.
    const more = () => {
      const rows = found.slice(shown, shown + LIST_CHUNK);
      shown += rows.length;
      hits.insertAdjacentHTML("beforeend", rows.map(p => `<button class="look-hit" data-model="${esc(p)}"><img class="thumb" data-thumb="${esc(p)}" alt="">
        <span><span>${esc(stem(p))}</span><span class="note">${esc(p.split("/").slice(3, -1).join("/"))}</span></span></button>`).join(""));
      this.thumbs.fill(hits);
    };
    const list = () => {
      // New rows replace the hovered one without a mouseleave.
      this.hover(null);
      this.filter = input.value; const terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
      found = this.models.filter(p => terms.every(w => p.includes(w))); shown = 0;
      count.textContent = `${found.length} of ${this.models.length} models. Rest the pointer on one for a second to try it on.`;
      hits.innerHTML = found.length ? "" : '<div class="note">No model matches.</div>';
      hits.scrollTop = 0; more();
    };
    hits.onscroll = () => { if (shown < found.length && hits.scrollTop + hits.clientHeight > hits.scrollHeight - 400) more(); };
    // One listener for every row, the ones added later included.
    const row = e => e.target.closest && e.target.closest("[data-model]");
    hits.onclick = e => { const b = row(e); if (b) this.pick(f, b.dataset.model); };
    hits.onmouseover = e => { const b = row(e); if (b && !b.contains(e.relatedTarget)) this.hover(b.dataset.model); };
    hits.onmouseout = e => { const b = row(e); if (b && !b.contains(e.relatedTarget)) this.hover(null); };
    input.oninput = () => { clearTimeout(this.typing); this.typing = setTimeout(list, TYPING_PAUSE); };
    // Every model's picture is drawn and kept in the background, so the list shows them at once from then on.
    this.thumbs.warm(this.models);
    list(); setTimeout(() => input.focus());
    return box;
  }

  // Tries a search hit on, or takes it off again (null), once the pointer rests.
  hover(model) {
    clearTimeout(this.resting);
    this.resting = setTimeout(() => { if (this.hovering !== model) { this.hovering = model; this.studio.live.sync(); } }, model ? HOVER_PAUSE : 0);
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
    this.adding = null; this.filter = ""; this.hover(null);
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
      ${Object.entries(pieces).map(([slot, piece]) => `<div class="look-piece"><img class="thumb" data-thumb="${esc(piece[0])}" alt=""><span class="adj-model">${esc(stem(piece[0]))}</span>
        <button class="mini" data-drop="${esc(slot)}" aria-label="Remove">×</button></div>
        ${this.state([slot])}`).join("")}`;
    container.append(extra);
    if (this.adding === "piece") extra.append(this.search(f));
    extra.querySelectorAll("[data-drop]").forEach(b => b.onclick = () => {
      const rest = { ...pieces }; delete rest[b.dataset.drop];
      this.set({ [base + "pieces"]: Object.keys(rest).length ? rest : null });
    });
    container.querySelectorAll("[data-add]").forEach(b => b.onclick = () => {
      this.adding = this.adding === b.dataset.add ? null : b.dataset.add; this.filter = ""; this.hover(null); this.render(container);
    });
    this.thumbs.fill(extra);
  }
}
