// The Adjust inspector tab: one card per weapon the open form holds (not what its mount adds, such as the disc), where the weapon's model can be swapped and slid along its grip, then his
// hands. A swap is for the open form only. Everything shows live on the stage. The exported models already carry the saved grip and hand values (`manifest.tuning`), so the live
// view moves each part by the difference from them. A swapped model is exported on the spot (`api/prop`) and put on its bone until a rebuild
// bakes it in. The Jobs bar saves the edits.
import * as THREE from "three";
import { loadModel } from "../viewer_common.js";

// Bones whose vertices the hand shift moves.
const HAND_BONES = /^(hand|finger_\w+|thumb)_(left|right)(_\d)?$/;

// A model path's file name without its extension, to match a mesh's model to a registry weapon.
const stem = p => p.toLowerCase().split("/").pop().replace(/\.(wsmodel|rigid_model_v2)$/, "");

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
    // `picking` is the slot whose model picker is open, `fine` the slots showing the y and z
    // sliders. `twin` caches the vanilla equivalent's models, `previews` the exported preview models, `loading` and `failed` each slot's preview.
    this.studio = studio; this.picking = null; this.filter = ""; this.fine = new Set();
    this.twin = new Map(); this.previews = new Map(); this.loading = new Set(); this.failed = new Map();
  }

  get tuning() { return this.studio.tuning; }
  get baked() { return this.studio.manifest.tuning; }
  // Whether the project can tune models at all.
  enabled() { return !!(this.tuning && this.baked && this.tuning.props); }
  propKey(model) { return this.tuning.props.find(k => stem(k) === stem(model)); }
  propValue(key) { return this.studio.edits.props[key] || this.tuning.prop_offsets[key] || [0, 0, 0]; }
  handValue() { return this.studio.edits.hand || this.tuning.hand_shift; }
  isAdvisor(model) { return !!model && model.meshes.some(m => /advisor_overhaul_body/.test(m.userData.model)); }
  advisor() { return this.enabled() ? this.studio.stage.rigs.map(r => r.model).find(m => this.isAdvisor(m)) : null; }
  form() { const entry = this.studio.stage.entry; return entry && this.studio.manifest.editor && this.studio.manifest.editor.forms[entry.unit]; }

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

  // Shows the current values on every Advisor model of the open entry, and each slot's chosen model.
  applyLive() {
    if (!this.enabled()) return;
    this.syncModels();
    for (const rig of this.studio.stage.rigs) {
      const model = rig.model; if (!this.isAdvisor(model)) continue;
      for (const mesh of model.meshes) {
        const u = mesh.userData;
        if (mesh.isSkinnedMesh && /advisor_overhaul_body/.test(u.model)) this.liveHands(model, mesh);
        const key = u.attach && this.propKey(u.model);
        if (key) { const v = this.propValue(key), b = u.preview ? [0, 0, 0] : this.baked.prop_offsets[key] || [0, 0, 0]; mesh.position.set(v[0] - b[0], v[1] - b[1], v[2] - b[2]); }
      }
    }
  }

  // The model a form's slot will use: a saved or unsaved swap, else the one it was built with.
  slotModel(f, slot) {
    const p = { ...this.studio.savedRegistry, ...this.studio.edits.registry };
    for (const path of [`weapons.${f.weapon}.forms.${f.mount}.props.${slot}`, `weapons.${f.weapon}.props.${slot}`]) if (path in p && p[path]) return { prop: p[path], pending: true };
    return { prop: f.props[slot], pending: false };
  }

  // The preview meshes of a model on a slot, exported by the server once and loaded once.
  preview(model, slot, attach) {
    const key = `${stem(model)}|${slot}|${attach}`;
    if (!this.previews.has(key)) {
      this.previews.set(key, fetch(this.studio.api + "prop", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ model, slot, attach }) })
        .then(async r => { const answer = await r.json(); if (!r.ok) throw new Error(answer.error); return loadModel(this.studio.data + answer.url); })
        .then(loaded => loaded.meshes.filter(m => !m.isSkinnedMesh)));
      this.previews.get(key).catch(() => this.previews.delete(key));
    }
    return this.previews.get(key);
  }

  // Puts each slot's chosen model on the Advisor's stage model: a swap shows its preview, and undoing it brings the built model back.
  async syncModels() {
    const model = this.advisor(), f = this.form(), entry = this.studio.stage.entry;
    if (!model || !f) return;
    model.built = model.built || {};
    for (const slot of Object.keys(f.props)) {
      const shown = model.meshes.filter(m => m.userData.slot === slot);
      if (!shown.length) continue;
      if (!model.built[slot]) model.built[slot] = shown;
      const [attach, wanted] = this.slotModel(f, slot).prop;
      if (stem(shown[0].userData.model) === stem(wanted)) continue;
      let meshes = model.built[slot];
      if (stem(meshes[0].userData.model) !== stem(wanted)) {
        this.loading.add(slot); this.failed.delete(slot); this.refresh();
        try { meshes = (await this.preview(wanted, slot, attach)).map(m => { const c = m.clone(); c.userData = { ...m.userData, preview: true }; return c; }); }
        catch (error) { this.failed.set(slot, error.message); meshes = null; }
        this.loading.delete(slot);
        // The form or the choice changed while it loaded.
        if (this.studio.stage.entry !== entry || stem(this.slotModel(f, slot).prop[1]) !== stem(wanted)) { this.refresh(); continue; }
      }
      if (meshes) {
        const bone = model.bones.find(b => b.name === attach) || model.group;
        for (const m of model.meshes.filter(m => m.userData.slot === slot)) m.removeFromParent();
        model.meshes = model.meshes.filter(m => m.userData.slot !== slot).concat(meshes);
        meshes.forEach(m => bone.add(m));
      }
      this.refresh();
    }
  }

  // Redraws the tab when it is open.
  refresh() { const body = document.getElementById("inspBody"); if (body && body.dataset.tab === "adjust") setTimeout(() => this.render(body)); }

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
    const entry = this.studio.stage.entry, model = this.advisor(), f = this.form();
    if (!model || !f) { container.innerHTML = '<div class="note">Nothing to adjust on this entry. Pick one of the project\'s forms.</div>'; return; }
    const { esc } = window.UnitPanel, edits = this.studio.edits;
    const intro = document.createElement("div"); intro.className = "note adj-intro";
    intro.textContent = "Swap a weapon's model or slide it in his hand. Changes show on the stage straight away. Save keeps them, and Rebuild puts them in the mod.";
    container.append(intro);
    for (const slot of Object.keys(f.props).filter(s => !(f.mount_props || []).includes(s))) {
      const { prop, pending } = this.slotModel(f, slot), key = this.propKey(prop[1]), card = document.createElement("div");
      const state = this.loading.has(slot) ? '<div class="note">Loading the new model...</div>'
        : this.failed.has(slot) ? `<div class="note warn">No preview: ${esc(this.failed.get(slot))}. It still builds on Rebuild.</div>` : "";
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
