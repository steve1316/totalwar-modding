// The Look tab's weapon cards: one per weapon the open form holds (not what its mount adds, such as the disc), where the weapon's model can be
// swapped, moved, turned and sized, and the Hands card. A swap is for the open form only. A move, turn and size belong to the weapon model, on
// every form holding it. Everything shows live on the stage: a swapped or hovered model through `studio.live` until a rebuild bakes it in, and
// the position, turn, size and hand values by their difference from the ones the exported models already carry (`manifest.tuning`). The Jobs bar
// saves the edits.
import * as THREE from "three";
import { stem } from "./live_models.js";
import { ModelList } from "./model_list.js";

// Bones whose vertices the hand shift moves.
const HAND_BONES = /^(hand|finger_\w+|thumb)_(left|right)(_\d)?$/;

// Words in a model's file name -> what the card calls the weapon, first match wins.
const KINDS = [["shield", "Shield"], ["staff", "Staff"], ["disc", "Disc"], ["greatsword", "Greatsword"], ["sword_2h", "Greatsword"], ["2h", "Two-handed weapon"],
  ["sword", "Sword"], ["bow", "Bow"], ["arrow", "Arrows"], ["axe", "Axe"], ["hammer", "Hammer"], ["mace", "Mace"], ["spear", "Spear"], ["lance", "Lance"],
  ["halberd", "Halberd"], ["whip", "Whip"], ["dagger", "Dagger"], ["book", "Book"], ["banner", "Banner"], ["chalice", "Chalice"]];

// A weapon's change on its bone as a matrix: sized and turned around the bone, then moved, as the rebuild bakes it. `turn` is degrees around
// x, y and z, composed in XYZ order like the rebuild's `turn_matrix`.
const shapeMatrix = (offset, turn, size) => new THREE.Matrix4().compose(new THREE.Vector3(...offset),
  new THREE.Quaternion().setFromEuler(new THREE.Euler(...turn.map(THREE.MathUtils.degToRad), "XYZ")), new THREE.Vector3(size, size, size));

// What the card calls the weapon in a slot.
const kindOf = model => (KINDS.find(([word]) => stem(model).includes(word)) || [null, "Weapon"])[1];

export class WeaponCards {
  // `look` is the Look tab, which holds the open picker and the hovered model. `shaping` holds the slots showing the position, turn and size
  // sliders, `twin` the vanilla equivalent's models.
  constructor(studio, look) {
    this.studio = studio; this.look = look; this.shaping = new Set(); this.twin = new Map();
    // The stage shows each weapon slot's chosen model, or the one hovered in its picker.
    studio.live.sources.push(f => Object.fromEntries(Object.keys(f.props).map(slot => {
      const { prop: [attach, model], pending } = this.slotModel(f, slot), hovered = look.adding === `weapon:${slot}` && look.hovering;
      return [slot, hovered ? { model: hovered, attach } : { model, attach, built: !pending }];
    })));
  }

  get tuning() { return this.studio.tuning; }
  get baked() { return this.studio.manifest.tuning; }
  // Whether the project can tune models at all.
  enabled() { return !!(this.tuning && this.baked && this.tuning.props); }
  propKey(model) { return this.tuning.props.find(k => stem(k) === stem(model)); }
  propValue(key) { return this.studio.edits.props[key] || this.tuning.prop_offsets[key] || [0, 0, 0]; }
  turnValue(key) { return this.studio.edits.turns[key] || (this.tuning.prop_turns || {})[key] || [0, 0, 0]; }
  sizeValue(key) { return this.studio.edits.sizes[key] ?? (this.tuning.prop_sizes || {})[key] ?? 1; }
  // The change the gallery's model of a weapon already carries.
  bakedMatrix(key) { const b = this.baked; return shapeMatrix((b.prop_offsets || {})[key] || [0, 0, 0], (b.prop_turns || {})[key] || [0, 0, 0], (b.prop_sizes || {})[key] ?? 1); }
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
      // The wanted change, less the one the shown model already carries (none for a model exported on the spot).
      if (key) shapeMatrix(this.propValue(key), this.turnValue(key), this.sizeValue(key)).multiply(u.preview ? new THREE.Matrix4() : this.bakedMatrix(key).invert())
        .decompose(mesh.position, mesh.quaternion, mesh.scale);
    }
  }

  // The registry path of a slot's swap on the form.
  formPath(f, slot) { return `weapons.${f.weapon}.forms.${f.mount}.props.${slot}`; }

  // The model a form's slot will use: a swap made or saved on this visit, else one saved earlier and not rebuilt yet (the registry differs from
  // the gallery), else the one it was built with.
  slotModel(f, slot) {
    const p = this.look.pending();
    for (const path of [this.formPath(f, slot), `weapons.${f.weapon}.props.${slot}`]) if (path in p && p[path]) return { prop: p[path], pending: true };
    const weapon = ((this.tuning.registry || {}).weapons || {})[f.weapon] || {};
    const saved = (((weapon.forms || {})[f.mount] || {}).props || {})[slot] || (weapon.props || {})[slot];
    if (saved && saved[1].toLowerCase() !== f.props[slot][1].toLowerCase()) return { prop: saved, pending: true };
    return { prop: f.props[slot], pending: false };
  }

  // The model picker of one slot: the vanilla equivalent's models, then every vanilla weapon model. The pick is this form's own.
  picker(entry, f, slot, prop) {
    const featured = this.twinProps(entry).then(all => {
      const vanilla = entry.versus && this.studio.manifest.panels && this.studio.manifest.panels[entry.versus];
      // The vanilla unit's mount props (its disc) are not weapons either.
      return { title: `${vanilla ? vanilla.name : "The vanilla equivalent"} holds:`, models: all.filter(([twinSlot]) => !(f.mount_props || []).includes(twinSlot)).map(([, , model]) => model) };
    });
    return new ModelList(this.look.thumbs, {
      models: this.studio.manifest.editor.prop_models, placeholder: "Search weapon models (staff, tzeentch, whip...)", featured,
      onPick: model => { this.look.close(); this.look.set({ [this.formPath(f, slot)]: [prop[0], model, prop[2] || ""] }); this.applyLive(); },
      onHover: model => this.look.tryOn(model),
    }).element();
  }

  // One slider row with a number box, rounded to `step`.
  numberRow(host, label, value, min, max, step, onChange) {
    const row = document.createElement("div"), digits = step < 1 ? 1 : 0;
    row.className = "arow";
    row.innerHTML = `<label>${label}</label><input type="range" min="${min}" max="${max}" step="${step}"><input type="number" step="${step}" inputmode="decimal">`;
    const [slider, box] = row.querySelectorAll("input"), round = n => Math.round(n / step) * step;
    const show = n => { slider.value = n; if (document.activeElement !== box) box.value = round(n).toFixed(digits); };
    const set = n => { show(n); onChange(round(n)); };
    slider.oninput = () => set(+slider.value);
    box.onchange = () => { if (box.value !== "" && isFinite(+box.value)) set(Math.max(min, Math.min(max, +box.value))); };
    show(value);
    host.append(row);
  }
  // One slider row in centimetres for a value held in metres.
  sliderRow(host, label, metres, range, onChange) { this.numberRow(host, label, metres * 100, -range, range, 0.1, cm => onChange(Math.round(cm * 10) / 1000)); }

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
    return this.formPath(f, slot) in this.studio.edits.registry ? "Not saved yet." : "Saved: Rebuild to put it in the mod.";
  }

  // Adds a card per weapon slot of the form to the tab.
  render(container, entry, f) {
    const { esc } = window.UnitPanel;
    for (const slot of Object.keys(f.props).filter(s => !(f.mount_props || []).includes(s))) {
      const { prop, pending } = this.slotModel(f, slot), key = this.propKey(prop[1]), card = document.createElement("div"), open = this.look.adding === `weapon:${slot}`;
      card.className = "adj-card";
      card.innerHTML = `<div class="adj-head"><b>${esc(kindOf(prop[1]))}</b><button class="mini" data-add="weapon:${esc(slot)}">${open ? "Close" : "Change model"}</button></div>
        <div class="look-piece"><img class="thumb" data-thumb="${esc(prop[1])}" alt=""><span class="adj-model">${esc(stem(prop[1]))}</span></div>
        <div class="note">${esc(this.origin(f, slot, pending))}</div>${this.look.state([slot])}`;
      container.append(card);
      if (open) card.append(this.picker(entry, f, slot, prop));
      if (!key) { if (pending) card.insertAdjacentHTML("beforeend", '<div class="note">Save to move, turn or size it.</div>'); continue; }
      const shaping = this.shaping.has(slot), more = document.createElement("button");
      more.className = "mini adj-more"; more.textContent = shaping ? "Hide position, turn and size" : "Position, turn and size";
      more.onclick = () => { shaping ? this.shaping.delete(slot) : this.shaping.add(slot); this.look.redraw(); };
      if (!shaping) card.insertAdjacentHTML("beforeend", `<div class="note">${esc(this.shapeSummary(key))}</div>`);
      card.append(more);
      if (shaping) this.shapeRows(card, key);
    }
  }

  // A weapon model's position, turn and size in words, or that it is as the game has it.
  shapeSummary(key) {
    const [x, y, z] = this.propValue(key), turn = this.turnValue(key), size = this.sizeValue(key), cm = v => (Math.round(v * 1000) / 10).toFixed(1);
    const parts = [x || y || z ? `moved ${cm(x)}, ${cm(y)}, ${cm(z)} cm` : "", turn.some(Boolean) ? `turned ${turn.join(", ")} degrees` : "", size !== 1 ? `${Math.round(size * 100)}% size` : ""];
    const said = parts.filter(Boolean).join(", ");
    return said ? said[0].toUpperCase() + said.slice(1) + "." : "As the game holds it.";
  }

  // The position, size and turn sliders of a weapon model, and a reset. A turn of 180 flips it, for a weapon that comes upside down.
  shapeRows(card, key) {
    const edits = this.studio.edits, changed = () => { this.applyLive(); this.studio.changed(); };
    card.insertAdjacentHTML("beforeend", `<div class="note">In the weapon's own directions, around his hand, on every form holding this model. x runs along the grip.</div>`);
    [["Move along x (cm)", 0], ["Move along y (cm)", 1], ["Move along z (cm)", 2]].forEach(([label, axis]) => this.sliderRow(card, label, this.propValue(key)[axis], 30, m => {
      edits.props[key] = this.propValue(key).slice(); edits.props[key][axis] = m; changed();
    }));
    this.numberRow(card, "Size (%)", this.sizeValue(key) * 100, 25, 300, 1, percent => { edits.sizes[key] = percent / 100; changed(); });
    [["Turn around x (degrees)", 0], ["Turn around y (degrees)", 1], ["Turn around z (degrees)", 2]].forEach(([label, axis]) =>
      this.numberRow(card, label, this.turnValue(key)[axis], -180, 180, 1, degrees => { edits.turns[key] = this.turnValue(key).slice(); edits.turns[key][axis] = degrees; changed(); }));
    const reset = document.createElement("button"); reset.className = "mini adj-more"; reset.textContent = "Reset to the game's";
    reset.onclick = () => { edits.props[key] = [0, 0, 0]; edits.turns[key] = [0, 0, 0]; edits.sizes[key] = 1; changed(); this.look.redraw(); };
    card.append(reset);
  }

  // Adds the Hands card to the tab.
  renderHands(container) {
    const edits = this.studio.edits, hands = document.createElement("div"); hands.className = "adj-card";
    hands.innerHTML = `<div class="adj-head"><b>Hands</b></div><div class="note">Moves both hands on every form, in centimetres. The left hand mirrors the right.</div>`;
    container.append(hands);
    [["Toward the fingers", 0], ["Up and down", 1], ["In and out", 2]].forEach(([label, axis]) => this.sliderRow(hands, label, this.handValue()[axis], 5, m => {
      edits.hand = this.handValue().slice(); edits.hand[axis] = m; this.applyLive(); this.studio.changed();
    }));
  }
}
