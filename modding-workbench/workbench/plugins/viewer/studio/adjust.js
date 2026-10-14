// The Adjust inspector tab: swaps the model in each weapon slot of the open form, slides each weapon along its grip and moves the hands, live on
// the stage. The exported models already carry the saved values (`manifest.tuning`), so the live view moves each part by the difference from them.
// A new model shows after a rebuild. The Jobs bar saves the edits.
import * as THREE from "three";

// Bones whose vertices the hand shift moves.
const HAND_BONES = /^(hand|finger_\w+|thumb)_(left|right)(_\d)?$/;

// A model path's file name without its extension, to match a mesh's model to a registry weapon.
const stem = p => p.toLowerCase().split("/").pop().replace(/\.(wsmodel|rigid_model_v2)$/, "");

// Weapon models a model search lists at most.
const MODEL_HITS = 20;

export class AdjustTab {
  constructor(studio) { this.studio = studio; this.picking = null; this.scope = "form"; this.filter = ""; this.twin = new Map(); }

  get tuning() { return this.studio.tuning; }
  get baked() { return this.studio.manifest.tuning; }
  // Whether the project can tune models at all.
  enabled() { return !!(this.tuning && this.baked && this.tuning.props); }
  propKey(model) { return this.tuning.props.find(k => stem(k) === stem(model)); }
  propValue(key) { return this.studio.edits.props[key] || this.tuning.prop_offsets[key] || [0, 0, 0]; }
  handValue() { return this.studio.edits.hand || this.tuning.hand_shift; }
  isAdvisor(model) { return !!model && model.meshes.some(m => /advisor_overhaul_body/.test(m.userData.model)); }

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

  // Shows the current values on every Advisor model of the open entry.
  applyLive() {
    if (!this.enabled()) return;
    for (const rig of this.studio.stage.rigs) {
      const model = rig.model; if (!this.isAdvisor(model)) continue;
      for (const mesh of model.meshes) {
        const u = mesh.userData;
        if (mesh.isSkinnedMesh && /advisor_overhaul_body/.test(u.model)) this.liveHands(model, mesh);
        const key = u.attach && this.propKey(u.model);
        if (key) { const v = this.propValue(key), b = this.baked.prop_offsets[key] || [0, 0, 0]; mesh.position.set(v[0] - b[0], v[1] - b[1], v[2] - b[2]); }
      }
    }
  }

  // The model picker of one slot: whether the swap is for this form or every form of the weapon, the vanilla equivalent's models, and a search
  // of every vanilla weapon model.
  picker(entry, f, slot, prop) {
    const { esc } = window.UnitPanel, box = document.createElement("div"), weaponName = entry.name.split(" - ")[0], formName = entry.name.split(" - ")[1] || "";
    box.className = "picker";
    box.innerHTML = `<div class="tools seg"><button data-scope="form" class="${this.scope === "form" ? "on" : ""}">${esc(formName)} only</button>
      <button data-scope="weapon" class="${this.scope === "weapon" ? "on" : ""}">Every ${esc(weaponName)} form</button></div>
      <div class="note twin">Loading the vanilla equivalent's models...</div>
      <input class="attrSearch" placeholder="Search the game's weapon models (staff, tzeentch, whip...)" value="${esc(this.filter)}"><div class="hits"></div>
      <div class="note">A new model shows after a rebuild.</div>`;
    const choose = model => {
      const path = this.scope === "form" ? `weapons.${f.weapon}.forms.${f.mount}.props.${slot}` : `weapons.${f.weapon}.props.${slot}`;
      this.studio.edits.registry[path] = [prop[0], model, prop[2] || ""]; this.picking = null; this.studio.changed();
      setTimeout(() => this.render(box.closest("#inspBody")));
    };
    box.querySelectorAll("[data-scope]").forEach(b => b.onclick = () => { this.scope = b.dataset.scope; box.querySelectorAll("[data-scope]").forEach(x => x.classList.toggle("on", x === b)); });
    this.twinProps(entry).then(list => {
      const vanilla = entry.versus && this.studio.manifest.panels && this.studio.manifest.panels[entry.versus];
      const twin = box.querySelector(".twin");
      twin.innerHTML = list.length ? `<div>From ${esc(vanilla ? vanilla.name : "the vanilla equivalent")}:</div>` + list.map(([s, bone, model]) =>
        `<button class="mini" data-model="${esc(model)}">${esc(s)} ${esc(stem(model))}</button>`).join(" ") : "";
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

  // The model a form's slot will use: a pending swap, else the one it has.
  slotModel(f, slot) {
    const p = { ...this.studio.savedRegistry, ...this.studio.edits.registry };
    for (const path of [`weapons.${f.weapon}.forms.${f.mount}.props.${slot}`, `weapons.${f.weapon}.props.${slot}`]) if (path in p && p[path]) return { prop: p[path], pending: true };
    return { prop: f.props[slot], pending: false };
  }

  // The vanilla equivalent's weapon models, read from its exported model once: [slot, attach bone, model path].
  async twinProps(entry) {
    const side = entry.sides.find(s => s.key === "v_rider");
    if (!side || !side.model) return [];
    if (!this.twin.has(side.model)) this.twin.set(side.model, fetch(this.studio.data + side.model).then(r => r.json())
      .then(doc => doc.meshes.filter(m => m.attach).map(m => [m.slot, m.attach, m.model])).catch(() => []));
    return this.twin.get(side.model);
  }

  // Builds the rows for the open entry: each weapon slot with its model (and a picker to swap it) and grip sliders, then his hands.
  render(container) {
    container.innerHTML = "";
    const entry = this.studio.stage.entry, model = this.enabled() && this.studio.stage.rigs.map(r => r.model).find(m => this.isAdvisor(m));
    const f = entry && this.studio.manifest.editor && this.studio.manifest.editor.forms[entry.unit];
    if (!model || !f) { container.innerHTML = '<div class="note">Nothing to adjust on this entry. Pick one of the project\'s forms.</div>'; return; }
    const { esc } = window.UnitPanel, edits = this.studio.edits;
    for (const slot of Object.keys(f.props)) {
      const { prop, pending } = this.slotModel(f, slot), key = this.propKey(prop[1]);
      const head = document.createElement("div"); head.className = "p-head slot-head";
      head.innerHTML = `<span>${esc(slot)}: ${esc(stem(prop[1]))}${pending ? ' <em class="note">(after a rebuild)</em>' : ""}</span><button class="mini" data-pick="${esc(slot)}">${this.picking === slot ? "Close" : "Change model"}</button>`;
      container.append(head);
      if (this.picking === slot) container.append(this.picker(entry, f, slot, prop));
      if (key && !pending) ["along blade (x)", "y", "z"].forEach((label, axis) => this.sliderRow(container, label, this.propValue(key)[axis], 15, m => {
        edits.props[key] = this.propValue(key).slice(); edits.props[key][axis] = m; this.applyLive(); this.studio.changed();
      }));
    }
    container.querySelectorAll("[data-pick]").forEach(b => b.onclick = () => { this.picking = this.picking === b.dataset.pick ? null : b.dataset.pick; this.filter = ""; this.render(container); });
    const head = document.createElement("div"); head.className = "p-head"; head.textContent = "Hands: right hand frame, left mirrored (cm)"; container.append(head);
    ["toward fingers (x)", "y", "z"].forEach((label, axis) => this.sliderRow(container, label, this.handValue()[axis], 5, m => {
      edits.hand = this.handValue().slice(); edits.hand[axis] = m; this.applyLive(); this.studio.changed();
    }));
  }
}
