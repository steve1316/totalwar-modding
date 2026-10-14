// The Adjust inspector tab: one card per weapon the open form holds (not what its mount adds, such as the disc), where the weapon's model can be
// swapped and slid along its grip, then his hands. A swap is for the open form only. Everything shows live on the stage: a swapped model through
// `studio.live` until a rebuild bakes it in, and the grip and hand values by their difference from the ones the exported models already carry
// (`manifest.tuning`). The Jobs bar saves the edits.
import * as THREE from "three";
import { stem } from "./live_models.js";

// Bones whose vertices the hand shift moves.
const HAND_BONES = /^(hand|finger_\w+|thumb)_(left|right)(_\d)?$/;

// Weapon models a model search lists at most.
const MODEL_HITS = 20;

// Words in a model's file name -> what the card calls the weapon, first match wins.
const KINDS = [["shield", "Shield"], ["staff", "Staff"], ["disc", "Disc"], ["greatsword", "Greatsword"], ["sword_2h", "Greatsword"], ["2h", "Two-handed weapon"],
  ["sword", "Sword"], ["bow", "Bow"], ["arrow", "Arrows"], ["axe", "Axe"], ["hammer", "Hammer"], ["mace", "Mace"], ["spear", "Spear"], ["lance", "Lance"],
  ["halberd", "Halberd"], ["whip", "Whip"], ["dagger", "Dagger"], ["book", "Book"], ["banner", "Banner"], ["chalice", "Chalice"]];

// What the card calls the weapon in a slot.
const kindOf = model => (KINDS.find(([word]) => stem(model).includes(word)) || [null, "Weapon"])[1];

export class AdjustTab {
  constructor(studio) {
    // `picking` is the slot whose model picker is open, `fine` the slots showing the y and z sliders, `twin` the vanilla equivalent's models.
    this.studio = studio; this.picking = null; this.filter = ""; this.fine = new Set(); this.twin = new Map();
    // The stage shows each weapon slot's chosen model.
    studio.live.sources.push(f => Object.fromEntries(Object.keys(f.props).map(slot => {
      const { prop: [attach, model], pending } = this.slotModel(f, slot);
      return [slot, { model, attach, built: !pending }];
    })));
    studio.live.listeners.push(() => this.refresh());
  }

  get tuning() { return this.studio.tuning; }
  get baked() { return this.studio.manifest.tuning; }
  // Whether the project can tune models at all.
  enabled() { return !!(this.tuning && this.baked && this.tuning.props); }
  propKey(model) { return this.tuning.props.find(k => stem(k) === stem(model)); }
  propValue(key) { return this.studio.edits.props[key] || this.tuning.prop_offsets[key] || [0, 0, 0]; }
  handValue() { return this.studio.edits.hand || this.tuning.hand_shift; }

  // Moves his hand vertices by the hand shift's change, weighted by how much each vertex follows the hand and finger bones.
  liveHands(model, mesh) {
    const g = mesh.geometry, pos = g.attributes.position, names = model.bones.map(b => b.name);
    if (!mesh.userData.hands) {
      const index = g.attributes.skinIndex, weight = g.attributes.skinWeight;
      const right = new Float32Array(pos.count), left = new Float32Array(pos.count);
      for (let v = 0; v < pos.count; v++) for (let k = 0; k < 4; k++) {
        const hit = HAND_BONES.exec(names[index.getComponent(v, k)] || "");
        if (hit) (hit[2] === "right" ? right : left)[v] += weight.getComponent(v, k);
      }
      const turn = side => new THREE.Matrix4().extractRotation(new THREE.Matrix4().copy(model.inverses[names.indexOf(`hand_${side}`)]).invert());
      mesh.userData.hands = { right, left, original: Float32Array.from(pos.array), turnRight: turn("right"), turnLeft: turn("left") };
    }
    const h = mesh.userData.hands, v = this.handValue(), b = this.baked.hand_shift, d = [v[0] - b[0], v[1] - b[1], v[2] - b[2]];
    const r = new THREE.Vector3(d[0], d[1], d[2]).applyMatrix4(h.turnRight), l = new THREE.Vector3(d[0], d[1], -d[2]).applyMatrix4(h.turnLeft);
    for (let i = 0; i < pos.count; i++) {
      pos.array[i * 3] = h.original[i * 3] + h.right[i] * r.x + h.left[i] * l.x;
      pos.array[i * 3 + 1] = h.original[i * 3 + 1] + h.right[i] * r.y + h.left[i] * l.y;
      pos.array[i * 3 + 2] = h.original[i * 3 + 2] + h.right[i] * r.z + h.left[i] * l.z;
    }
    pos.needsUpdate = true;
  }

  // Shows the chosen models and the current grip and hand values on the open form's stage model.
  applyLive() {
    if (!this.enabled()) return;
    this.studio.live.sync().then(() => this.placeLive());
    this.placeLive();
  }
  placeLive() {
    const model = this.studio.live.model();
    if (!model) return;
    for (const mesh of model.meshes) {
      const u = mesh.userData;
      if (mesh.isSkinnedMesh && /advisor_overhaul_body/.test(u.model)) this.liveHands(model, mesh);
      const key = u.attach && this.propKey(u.model);
      if (key) { const v = this.propValue(key), b = u.preview ? [0, 0, 0] : this.baked.prop_offsets[key] || [0, 0, 0]; mesh.position.set(v[0] - b[0], v[1] - b[1], v[2] - b[2]); }
    }
  }

  // The model a form's slot will use: a saved or unsaved swap, else the one it was built with.
  slotModel(f, slot) {
    const p = { ...this.studio.savedRegistry, ...this.studio.edits.registry };
    for (const path of [`weapons.${f.weapon}.forms.${f.mount}.props.${slot}`, `weapons.${f.weapon}.props.${slot}`]) if (path in p && p[path]) return { prop: p[path], pending: true };
    return { prop: f.props[slot], pending: false };
  }

  // Redraws the tab when it is open, unless a search is open: redrawing would rebuild its rows under the pointer and take the typing focus.
  refresh() { const body = document.getElementById("inspBody"); if (body && body.dataset.tab === "adjust" && !this.picking) setTimeout(() => this.render(body)); }

  // The model picker of one slot: the vanilla equivalent's models, and a search of every vanilla weapon model. The pick is this form's own.
  picker(entry, f, slot, prop) {
    const { esc } = window.UnitPanel, box = document.createElement("div");
    box.className = "picker";
    box.innerHTML = `<div class="twin note">Loading the vanilla equivalent's models...</div>
      <input class="attrSearch" placeholder="Search the game's weapon models (staff, tzeentch, whip...)" value="${esc(this.filter)}"><div class="hits"></div>`;
    const choose = model => {
      this.studio.edits.registry[`weapons.${f.weapon}.forms.${f.mount}.props.${slot}`] = [prop[0], model, prop[2] || ""]; this.picking = null; this.studio.changed(); this.applyLive(); this.refresh();
    };
    this.twinProps(entry).then(all => {
      // The vanilla unit's mount props (its disc) are not weapons either.
      const list = all.filter(([twinSlot]) => !(f.mount_props || []).includes(twinSlot));
      const vanilla = entry.versus && this.studio.manifest.panels && this.studio.manifest.panels[entry.versus], twin = box.querySelector(".twin");
      twin.innerHTML = list.length ? `<div>${esc(vanilla ? vanilla.name : "The vanilla equivalent")} holds:</div>` + list.map(([, , model]) =>
        `<button class="mini" data-model="${esc(model)}">${esc(kindOf(model))}: ${esc(stem(model))}</button>`).join(" ") : "";
      twin.querySelectorAll("[data-model]").forEach(b => b.onclick = () => choose(b.dataset.model));
    });
    const search = box.querySelector("input"), hits = box.querySelector(".hits");
    const list = () => {
      this.filter = search.value; const words = search.value.toLowerCase().split(/\s+/).filter(Boolean);
      const found = words.length ? this.studio.manifest.editor.prop_models.filter(p => words.every(w => p.includes(w))).slice(0, MODEL_HITS) : [];
      hits.innerHTML = found.map(p => `<button data-model="${esc(p)}"><span>${esc(stem(p))}</span><span class="note">${esc(p.split("/").slice(2, 4).join("/"))}</span></button>`).join("");
      hits.querySelectorAll("[data-model]").forEach(b => b.onclick = () => choose(b.dataset.model));
    };
    search.oninput = list; list();
    return box;
  }

  // One slider row in centimetres for a value held in metres.
  sliderRow(host, label, metres, range, onChange) {
    const row = document.createElement("div"); row.className = "arow";
    row.innerHTML = `<label>${label}</label><input type="range" min="${-range}" max="${range}" step="0.1"><input type="number" step="0.1" inputmode="decimal">`;
    const [slider, box] = row.querySelectorAll("input");
    const show = cm => { slider.value = cm; if (document.activeElement !== box) box.value = (Math.round(cm * 10) / 10).toFixed(1); };
    const set = cm => { show(cm); onChange(Math.round(cm * 10) / 1000); };
    slider.oninput = () => set(+slider.value);
    box.onchange = () => { if (box.value !== "" && isFinite(+box.value)) set(Math.max(-range, Math.min(range, +box.value))); };
    show(metres * 100);
    host.append(row);
  }

  // The vanilla equivalent's weapon models, read from its exported model once: [slot, attach bone, model path].
  async twinProps(entry) {
    const side = entry.sides.find(s => s.key === "v_rider");
    if (!side || !side.model) return [];
    if (!this.twin.has(side.model)) this.twin.set(side.model, fetch(this.studio.data + side.model).then(r => r.json())
      .then(doc => doc.meshes.filter(m => m.attach).map(m => [m.slot, m.attach, m.model])).catch(() => []));
    return this.twin.get(side.model);
  }

  // Whether a slot's swap is saved yet, in words.
  origin(f, slot, pending) {
    if (!pending) return "";
    return `weapons.${f.weapon}.forms.${f.mount}.props.${slot}` in this.studio.edits.registry ? "Not saved yet." : "Saved: Rebuild to put it in the mod.";
  }

  // Builds the tab: a card per weapon slot, then his hands.
  render(container) {
    container.innerHTML = "";
    const entry = this.studio.stage.entry, live = this.studio.live, model = this.enabled() && live.model(), f = live.form();
    if (!model || !f) { container.innerHTML = '<div class="note">Nothing to adjust on this entry. Pick one of the project\'s forms.</div>'; return; }
    const { esc } = window.UnitPanel, edits = this.studio.edits;
    const intro = document.createElement("div"); intro.className = "note adj-intro";
    intro.textContent = "Swap a weapon's model or slide it in his hand. Changes show on the stage straight away. Save keeps them, and Rebuild puts them in the mod.";
    container.append(intro);
    for (const slot of Object.keys(f.props).filter(s => !(f.mount_props || []).includes(s))) {
      const { prop, pending } = this.slotModel(f, slot), key = this.propKey(prop[1]), card = document.createElement("div");
      const state = live.loading.has(slot) ? '<div class="note">Loading the new model...</div>'
        : live.failed.has(slot) ? `<div class="note warn">No preview: ${esc(live.failed.get(slot))}. It still builds on Rebuild.</div>` : "";
      card.className = "adj-card";
      card.innerHTML = `<div class="adj-head"><b>${esc(kindOf(prop[1]))}</b><button class="mini" data-pick>${this.picking === slot ? "Close" : "Change model"}</button></div>
        <div class="adj-model">${esc(stem(prop[1]))}</div><div class="note">${esc(this.origin(f, slot, pending))}</div>${state}`;
      container.append(card);
      card.querySelector("[data-pick]").onclick = () => { this.picking = this.picking === slot ? null : slot; this.filter = ""; this.render(container); };
      if (this.picking === slot) card.append(this.picker(entry, f, slot, prop));
      if (!key) { if (pending) card.insertAdjacentHTML("beforeend", '<div class="note">Save to slide it along the grip.</div>'); continue; }
      const move = axis => m => { edits.props[key] = this.propValue(key).slice(); edits.props[key][axis] = m; this.applyLive(); this.studio.changed(); };
      this.sliderRow(card, "Slide along the grip", this.propValue(key)[0], 15, move(0));
      const more = document.createElement("button"); more.className = "mini adj-more"; more.textContent = this.fine.has(slot) ? "Hide fine position" : "Fine position";
      more.onclick = () => { this.fine.has(slot) ? this.fine.delete(slot) : this.fine.add(slot); this.render(container); };
      card.append(more);
      if (this.fine.has(slot)) [["Up and down (y)", 1], ["Sideways (z)", 2]].forEach(([label, axis]) => this.sliderRow(card, label, this.propValue(key)[axis], 15, move(axis)));
    }
    const hands = document.createElement("div"); hands.className = "adj-card";
    hands.innerHTML = `<div class="adj-head"><b>Hands</b></div><div class="note">Moves both hands on every form, in centimetres. The left hand mirrors the right.</div>`;
    container.append(hands);
    [["Toward the fingers", 0], ["Up and down", 1], ["In and out", 2]].forEach(([label, axis]) => this.sliderRow(hands, label, this.handValue()[axis], 5, m => {
      edits.hand = this.handValue().slice(); edits.hand[axis] = m; this.applyLive(); this.studio.changed();
    }));
  }
}
