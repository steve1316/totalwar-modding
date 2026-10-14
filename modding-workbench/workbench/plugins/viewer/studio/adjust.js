// The Adjust inspector tab: slides each weapon of the open form along its grip and moves the hands, live on the stage. The exported models
// already carry the saved values (`manifest.tuning`), so the live view moves each part by the difference from them. The Jobs bar saves the edits.
import * as THREE from "three";

// Bones whose vertices the hand shift moves.
const HAND_BONES = /^(hand|finger_\w+|thumb)_(left|right)(_\d)?$/;

// A model path's file name without its extension, to match a mesh's model to a registry weapon.
const stem = p => p.toLowerCase().split("/").pop().replace(/\.(wsmodel|rigid_model_v2)$/, "");

export class AdjustTab {
  constructor(studio) { this.studio = studio; }

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

  // Builds the rows for the open entry: each weapon of the Advisor's model, then his hands.
  render(container) {
    container.innerHTML = "";
    const model = this.enabled() && this.studio.stage.rigs.map(r => r.model).find(m => this.isAdvisor(m));
    if (!model) { container.innerHTML = '<div class="note">Nothing to adjust on this entry. Pick an Advisor form.</div>'; return; }
    const edits = this.studio.edits, seen = new Set();
    for (const mesh of model.meshes) {
      const key = mesh.userData.attach && this.propKey(mesh.userData.model);
      if (!key || seen.has(key)) continue;
      seen.add(key);
      const head = document.createElement("div"); head.className = "p-head"; head.textContent = `${mesh.userData.slot}: ${stem(key)} (cm)`; container.append(head);
      ["along blade (x)", "y", "z"].forEach((label, axis) => this.sliderRow(container, label, this.propValue(key)[axis], 15, m => {
        edits.props[key] = this.propValue(key).slice(); edits.props[key][axis] = m; this.applyLive(); this.studio.changed();
      }));
    }
    const head = document.createElement("div"); head.className = "p-head"; head.textContent = "Hands: right hand frame, left mirrored (cm)"; container.append(head);
    ["toward fingers (x)", "y", "z"].forEach((label, axis) => this.sliderRow(container, label, this.handValue()[axis], 5, m => {
      edits.hand = this.handValue().slice(); edits.hand[axis] = m; this.applyLive(); this.studio.changed();
    }));
  }
}
