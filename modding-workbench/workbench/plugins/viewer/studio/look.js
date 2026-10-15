// The Look inspector tab: the open form's weapons (`weapons.js`), then his outfit, his hood and extra pieces such as a hat, set per weapon and shared
// by every mount of that weapon (`weapons.<weapon>.body`, `.hood` and `.pieces`), then his hands. An outfit can be worn without the faction colours
// or heraldry the game paints on it (`model.unpainted.<outfit>`), on every form wearing it. Outfits come from the registry's `model.bodies`,
// and any full body of the game (`api/bodies`) can be added as an outfit, any humanoid model or prop as a piece. A prop piece is held on a bone
// ([bone, model]) and has its own position, turn and size (`weapons.<weapon>.piece_shapes.<slot>`), so two of the same model can point different
// ways. A piece that bends with the body is [model]. Every picker is a `ModelList` with thumbnails, and the model the
// pointer rests on is tried on. Every choice shows live on the stage through `studio.live`. The Jobs bar saves the edits.
import { stem } from "./live_models.js";
import { ModelList } from "./model_list.js";
import { Thumbnails } from "./thumbs.js";
import { NO_SHAPE, WeaponCards } from "./weapons.js";

// The slot a hovered piece is tried on in.
const HOVER_SLOT = "piece_hover";

// Bones a prop piece can be held on, with what the picker calls them. The first is where a new one goes.
const PIECE_BONES = [["spine_2", "Back"], ["spine_0", "Waist"], ["root", "Hips"], ["head", "Head"], ["clav_left", "Left shoulder"],
  ["clav_right", "Right shoulder"], ["upperleg_left", "Left thigh"], ["upperleg_right", "Right thigh"], ["hand_left", "Left hand"], ["hand_right", "Right hand"]];

// Whether a piece is a prop held on a bone ([bone, model, ...]) rather than one that bends with the body ([model, ...]), and its model.
const held = piece => !/\.(wsmodel|rigid_model_v2)$/i.test(piece[0]);
const pieceModel = piece => held(piece) ? piece[1] : piece[0];

// The metadata a new outfit's body slot carries, as on the vanilla outfits.
const BODY_META = ["audio_entity_type:wh_human_male_LH", "audio_armour_type:leather"];

// A key or file name in words: "grey_wizard" -> "Grey Wizard".
const words = key => key.replace(/_\d+$/, "").split("_").filter(Boolean).map(w => w[0].toUpperCase() + w.slice(1)).join(" ");

export class LookTab {
  constructor(studio) {
    // `adding` is the open picker ("outfit", "piece" or "weapon:<slot>"), `hovering` the model he is trying on from it.
    this.studio = studio; this.adding = null; this.hovering = null; this.queued = false;
    this.look = studio.manifest.editor && studio.manifest.editor.look;
    this.thumbs = new Thumbnails(studio);
    // The props a piece may be, besides the humanoid models.
    this.props = new Set((studio.manifest.editor && studio.manifest.editor.prop_models) || []);
    // The game's full bodies, the models "+ Another outfit" lists. Null until the server has answered.
    this.fullBodies = null;
    if (this.look) fetch(studio.api + "bodies").then(r => r.json()).then(list => { this.fullBodies = list; if (this.adding === "outfit") this.redraw(); })
      .catch(error => console.error("full bodies", error));
    this.weapons = new WeaponCards(studio, this);
    // The stage shows the chosen outfit, head and pieces.
    studio.live.sources.push(f => this.wanted(f));
    studio.live.listeners.push(() => this.refresh());
  }

  enabled() { return !!(this.look && this.studio.tuning); }
  // Shows the chosen weapons and the grip and hand values on the stage.
  applyLive() { this.weapons.applyLive(); }
  pending() { return { ...this.studio.savedRegistry, ...this.studio.edits.registry }; }
  // A look field of the form's weapon: as edited or saved on this visit, else as saved earlier, else as the gallery built it.
  value(f, field) {
    const p = this.pending(), path = `weapons.${f.weapon}.${field}`, saved = ((this.studio.tuning.registry || {}).weapons || {})[f.weapon];
    return path in p ? p[path] : saved && field in saved ? saved[field] : f.look[field];
  }
  // A prop piece's wanted position, turn and size, and the ones the gallery's model of it carries. Null for a slot that is no prop piece.
  heldShape(f, slot) {
    const piece = (this.value(f, "pieces") || {})[slot];
    if (!piece || !held(piece)) return null;
    return { want: (this.value(f, "piece_shapes") || {})[slot] || NO_SHAPE, baked: (f.look.piece_shapes || {})[slot] || NO_SHAPE };
  }
  // Every outfit: the gallery's, then any added since (slot -> model).
  bodies() {
    const all = { ...this.look.bodies };
    for (const [path, body] of Object.entries(this.pending())) {
      if (path.startsWith("model.bodies.") && body) all[path.slice("model.bodies.".length)] = Object.fromEntries(Object.entries(body).map(([slot, piece]) => [slot, piece[0]]));
    }
    return all;
  }
  hoodless() { return !!this.look.head.hoodless; }
  // Whether an outfit is worn without its colours, with the pending edits.
  unpainted(key) {
    const p = this.pending(), path = `model.unpainted.${key}`;
    return !!(path in p ? p[path] : ((this.studio.tuning.registry || {})["model.unpainted"] || {})[key]);
  }

  // The slots the stage should show for the form: its outfit's (every other outfit's slot empty), its head and its pieces (removed ones empty).
  // What has not changed since the gallery was built is marked built.
  wanted(f) {
    if (!this.enabled()) return {};
    const bodies = this.bodies(), key = this.value(f, "body"), body = bodies[key] || {}, out = {}, hood = this.value(f, "hood") !== false;
    for (const outfit of Object.values(bodies)) for (const slot of Object.keys(outfit)) out[slot] = null;
    for (const [slot, model] of Object.entries(body)) out[slot] = { model, attach: "", built: key === f.look.body, plain: this.unpainted(key) };
    if (this.hoodless()) out.head = { model: hood ? this.look.head.hooded : this.look.head.hoodless, attach: "", built: hood === (f.look.hood !== false) };
    for (const slot of Object.keys(f.look.pieces)) out[slot] = null;
    for (const [slot, piece] of Object.entries(this.value(f, "pieces") || {})) {
      out[slot] = { model: pieceModel(piece), attach: held(piece) ? piece[0] : "", built: JSON.stringify(f.look.pieces[slot]) === JSON.stringify(piece) };
    }
    // A hovered model is tried on: a piece next to the rest (a prop on his back), an outfit in place of his. A weapon is tried on by `WeaponCards`.
    out[HOVER_SLOT] = this.hovering && this.adding === "piece" ? { model: this.hovering, attach: this.props.has(this.hovering) ? PIECE_BONES[0][0] : "" } : null;
    if (this.hovering && this.adding === "outfit") {
      for (const slot of Object.keys(body)) out[slot] = null;
      out.body = { model: this.hovering, attach: "" };
    }
    return out;
  }

  // Records registry edits and shows them.
  set(changes) { Object.assign(this.studio.edits.registry, changes); this.studio.changed(); this.studio.live.sync(); this.refresh(); }

  // Redraws the tab when it is open, unless a picker is open: redrawing would rebuild its rows under the pointer and take the typing focus.
  // Several changes in a row redraw it once.
  refresh() { if (!this.adding && !this.queued) { this.queued = true; setTimeout(() => { this.queued = false; this.redraw(); }); } }
  redraw() { const body = document.getElementById("inspBody"); if (body && body.dataset.tab === "look") this.render(body); }

  // Tries a model on from the open picker, or takes it off again (null).
  tryOn(model) { if (this.hovering !== model) { this.hovering = model; this.studio.live.sync(); } }
  // Opens a picker, or closes it when it is the open one.
  toggle(adding) { const next = this.adding === adding ? null : adding; this.close(); this.adding = next; this.redraw(); }
  close() { this.adding = null; this.tryOn(null); }

  // A slot's loading or failed preview, in words.
  state(slots) {
    const { esc } = window.UnitPanel, live = this.studio.live;
    if (slots.some(s => live.loading.has(s))) return '<div class="note">Loading...</div>';
    const failed = slots.find(s => live.failed.has(s));
    return failed ? `<div class="note warn">No preview: ${esc(live.failed.get(failed))}. It still builds on Rebuild.</div>` : "";
  }

  // The model list of "+ Another outfit" (the game's full bodies) or "+ Add a piece" (every humanoid model, then every prop).
  search(f) {
    const outfit = this.adding === "outfit";
    if (outfit && !this.fullBodies) return Object.assign(document.createElement("div"), { className: "note", textContent: "Finding the game's full bodies..." });
    return new ModelList(this.thumbs, { models: outfit ? this.fullBodies : this.look.models.concat([...this.props]),
      placeholder: outfit ? "Search full bodies (wizard, knight, priest...)" : "Search models and props (hat, cape, book, sword...)",
      onPick: model => this.pick(f, model), onHover: model => this.tryOn(model) }).element();
  }

  // Adds the picked model as an outfit (and wears it) or as a piece, a prop held on his back.
  pick(f, model) {
    const base = `weapons.${f.weapon}.`, adding = this.adding;
    this.close();
    if (adding === "outfit") {
      const key = stem(model).replace(/[^a-z0-9_]/g, "_");
      this.set({ [`model.bodies.${key}`]: { body: [model, ...BODY_META] }, [base + "body"]: key });
    } else {
      const pieces = { ...(this.value(f, "pieces") || {}) };
      let n = 1;
      while (`piece_${n}` in pieces) n++;
      pieces[`piece_${n}`] = this.props.has(model) ? [PIECE_BONES[0][0], model] : [model];
      this.set({ [base + "pieces"]: pieces });
    }
  }

  // Builds the tab: the form's weapons, his outfit, hood and pieces, then his hands. Each section says which forms it changes.
  render(container) {
    container.innerHTML = "";
    const live = this.studio.live, f = live.form(), entry = this.studio.stage.entry;
    if (!this.weapons.enabled() || !f || !live.model()) { container.innerHTML = '<div class="note">Nothing to change on this entry. Pick one of the project\'s forms.</div>'; return; }
    const { esc } = window.UnitPanel, weaponName = entry.name.split(" - ")[0];
    container.insertAdjacentHTML("beforeend", `<div class="note adj-intro">Changes show on the stage straight away. Save keeps them, and Rebuild puts them in the mod.</div>
      <div class="look-section"><b>Weapons</b><span class="note">Every ${esc(weaponName)} form, on foot and on each mount.</span></div>`);
    this.weapons.render(container, entry, f);
    if (this.enabled()) this.renderDress(container, f, weaponName);
    container.insertAdjacentHTML("beforeend", '<div class="look-section"><b>Hands</b><span class="note">Every form.</span></div>');
    this.weapons.renderHands(container);
    container.querySelectorAll("[data-add]").forEach(b => b.onclick = () => this.toggle(b.dataset.add));
    this.thumbs.fill(container);
  }

  // Adds the outfit, hood and extra pieces cards, shared by every form of the weapon.
  renderDress(container, f, weaponName) {
    const { esc } = window.UnitPanel, base = `weapons.${f.weapon}.`;
    const bodies = this.bodies(), current = this.value(f, "body"), hood = this.value(f, "hood") !== false, pieces = this.value(f, "pieces") || {};
    container.insertAdjacentHTML("beforeend", `<div class="look-section"><b>Outfit</b><span class="note">Every ${esc(weaponName)} form, on foot and on each mount.</span></div>`);

    const outfit = document.createElement("div"); outfit.className = "adj-card";
    outfit.innerHTML = `<div class="adj-head"><b>Body</b><button class="mini" data-add="outfit">${this.adding === "outfit" ? "Close" : "+ Another outfit"}</button></div>
      <div class="look-bodies">${Object.keys(bodies).map(k => `<button data-body="${esc(k)}" class="${k === current ? "on" : ""}">${esc(words(k))}</button>`).join("")}</div>
      ${this.state(Object.keys(bodies[current] || {}))}`;
    container.append(outfit);
    if (this.adding === "outfit") outfit.append(this.search(f));
    outfit.querySelectorAll("[data-body]").forEach(b => b.onclick = () => this.set({ [base + "body"]: b.dataset.body }));

    const plain = this.unpainted(current), colours = document.createElement("div"); colours.className = "adj-card";
    colours.innerHTML = `<div class="adj-head"><b>Colours</b><span class="tools seg"><button data-paint="on" class="${plain ? "" : "on"}">Painted</button><button data-paint="off" class="${plain ? "on" : ""}">Unpainted</button></span></div>
      <div class="note">${plain ? `${esc(words(current))} is worn without the faction colours or heraldry the game paints on it, on every form wearing it.`
        : "The game paints the faction's colours (or a Bretonnian knight's heraldry) on it, as the stage's colour pickers show."}</div>`;
    container.append(colours);
    colours.querySelectorAll("[data-paint]").forEach(b => b.onclick = () => this.set({ [`model.unpainted.${current}`]: b.dataset.paint === "off" ? true : null }));

    if (this.hoodless()) {
      const card = document.createElement("div"); card.className = "adj-card";
      card.innerHTML = `<div class="adj-head"><b>Hood</b><span class="tools seg"><button data-hood="on" class="${hood ? "on" : ""}">Up</button><button data-hood="off" class="${hood ? "" : "on"}">Down</button></span></div>
        ${this.state(["head"])}`;
      container.append(card);
      card.querySelectorAll("[data-hood]").forEach(b => b.onclick = () => this.set({ [base + "hood"]: b.dataset.hood === "on" }));
    }

    const extra = document.createElement("div"); extra.className = "adj-card";
    extra.innerHTML = `<div class="adj-head"><b>Extra pieces</b><button class="mini" data-add="piece">${this.adding === "piece" ? "Close" : "+ Add a piece"}</button></div>
      ${Object.keys(pieces).length ? "" : '<div class="note">None. Add a hat, a helmet, a cape, a book and so on.</div>'}`;
    container.append(extra);
    for (const [slot, piece] of Object.entries(pieces)) {
      extra.insertAdjacentHTML("beforeend", `<div class="look-piece"><img class="thumb" data-thumb="${esc(pieceModel(piece))}" alt=""><span class="adj-model">${esc(stem(pieceModel(piece)))}</span>
        <button class="mini" data-drop="${esc(slot)}" aria-label="Remove">×</button></div>${this.state([slot])}`);
      if (held(piece)) this.renderHeld(extra, f, pieces, slot, piece);
    }
    if (this.adding === "piece") extra.append(this.search(f));
    extra.querySelectorAll("[data-drop]").forEach(b => b.onclick = () => {
      const rest = { ...pieces }, shapes = { ...(this.value(f, "piece_shapes") || {}) };
      delete rest[b.dataset.drop]; delete shapes[b.dataset.drop];
      this.set({ [base + "pieces"]: Object.keys(rest).length ? rest : null, [base + "piece_shapes"]: Object.keys(shapes).length ? shapes : null });
    });
  }

  // A prop piece's bone, then its own position, turn and size.
  renderHeld(card, f, pieces, slot, piece) {
    const { esc } = window.UnitPanel, weapons = this.weapons, base = `weapons.${f.weapon}.`, row = document.createElement("div");
    row.className = "piece-bone";
    row.innerHTML = `<span>Held on</span><select>${PIECE_BONES.map(([bone, name]) => `<option value="${bone}">${esc(name)}</option>`).join("")}</select>`;
    const select = row.querySelector("select");
    if (!PIECE_BONES.some(([bone]) => bone === piece[0])) select.add(new Option(piece[0], piece[0]));
    select.value = piece[0];
    select.onchange = () => this.set({ [base + "pieces"]: { ...pieces, [slot]: [select.value, ...piece.slice(1)] } });
    card.append(row);
    const shaping = weapons.shaping.has(slot), more = document.createElement("button"), shape = this.heldShape(f, slot).want;
    more.className = "mini adj-more"; more.textContent = shaping ? "Hide position, turn and size" : "Position, turn and size";
    more.onclick = () => { shaping ? weapons.shaping.delete(slot) : weapons.shaping.add(slot); this.redraw(); };
    if (!shaping) card.insertAdjacentHTML("beforeend", `<div class="note">${esc(weapons.shapeSummary(shape))}</div>`);
    card.append(more);
    // Edits go straight into the pending registry, without a redraw that would drop the slider being dragged.
    if (shaping) weapons.shapeRows(card, "In the model's own directions, around the bone holding it. This piece only.", shape, next => {
      const shapes = { ...(this.value(f, "piece_shapes") || {}) }, plain = JSON.stringify(next) === JSON.stringify(NO_SHAPE);
      if (plain) delete shapes[slot]; else shapes[slot] = next;
      this.studio.edits.registry[base + "piece_shapes"] = Object.keys(shapes).length ? shapes : null;
    });
  }
}
