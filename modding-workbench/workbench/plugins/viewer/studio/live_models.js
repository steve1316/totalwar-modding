// Live models: keeps the open form's stage model showing what its tabs chose (weapons from the Adjust tab, outfit, head and extra pieces from the
// Look tab) before a rebuild bakes them in. Each tab adds a source: a function giving, for the open form, slot -> {model, attach, built} (attach
// empty for a model that bends with the body, built when it is what the gallery built) or null for a slot that should be empty. A model the
// gallery does not have is exported on the spot (`api/props`) and loaded once. The pieces the gallery built are kept aside, and a slot changed
// here goes back to them once no source asks for anything else.
import * as THREE from "three";
import { loadModel } from "../viewer_common.js";

// A model path's file name without its extension.
export const stem = p => (p || "").toLowerCase().split("/").pop().replace(/\.(wsmodel|rigid_model_v2)$/, "");

export class LiveModels {
  constructor(studio) {
    // `sources` give the wanted slots, `listeners` redraw the tabs. `previews` caches exported models, `loading` and `failed` each slot's state.
    this.studio = studio; this.sources = []; this.listeners = []; this.previews = new Map(); this.loading = new Set(); this.failed = new Map();
    this.running = Promise.resolve();
  }

  // The open form's own stage model: the first side that is not the vanilla equivalent.
  model() { const rig = this.studio.stage.rigs.find(r => r.side.group !== "vanilla" && r.model); return rig ? rig.model : null; }
  form() { const entry = this.studio.stage.entry; return entry && this.studio.manifest.editor && this.studio.manifest.editor.forms[entry.unit]; }
  wanted(f) { return Object.assign({}, ...this.sources.map(source => source(f))); }
  changed() { this.listeners.forEach(listener => listener()); }

  // The meshes of a model on a slot, exported by the server once and loaded once.
  preview(model, slot, attach) {
    const key = `${stem(model)}|${slot}|${attach}`;
    if (!this.previews.has(key)) {
      this.previews.set(key, fetch(this.studio.api + "props", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ items: [{ model, slot, attach }] }) })
        .then(async r => {
          const answer = await r.json();
          if (!r.ok || !answer.urls[0]) throw new Error(answer.error || "not found in the game's packs");
          return loadModel(this.studio.data + answer.urls[0]);
        })
        .then(loaded => loaded.meshes));
      this.previews.get(key).catch(() => this.previews.delete(key));
    }
    return this.previews.get(key);
  }

  // Puts meshes on a slot in place of what it shows: rigid ones on their bone, bending ones on the model's skeleton.
  place(model, slot, meshes, attach) {
    for (const m of model.meshes.filter(m => m.userData.slot === slot)) m.removeFromParent();
    model.meshes = model.meshes.filter(m => m.userData.slot !== slot).concat(meshes);
    for (const m of meshes) {
      if (m.isSkinnedMesh) { model.group.add(m); m.bind(model.skeleton, new THREE.Matrix4()); }
      else (model.bones.find(b => b.name === attach) || model.group).add(m);
    }
  }

  // Brings the stage model in line with the sources. Runs one at a time.
  sync() { this.running = this.running.then(() => this.syncNow()).catch(error => console.error("live models", error)); return this.running; }

  async syncNow() {
    const model = this.model(), f = this.form(), entry = this.studio.stage.entry;
    if (!model || !f) return;
    if (!model.built) {
      model.built = {};
      for (const m of model.meshes) (model.built[m.userData.slot] = model.built[m.userData.slot] || []).push(m);
      model.skeleton = (model.meshes.find(m => m.isSkinnedMesh) || {}).skeleton;
    }
    const wanted = this.wanted(f);
    model.changedSlots = model.changedSlots || new Set();
    for (const slot of model.changedSlots) if (!(slot in wanted)) wanted[slot] = model.built[slot] ? { built: true } : null;
    for (const [slot, want] of Object.entries(wanted)) {
      const shown = model.meshes.filter(m => m.userData.slot === slot);
      if (!want) { if (shown.length) { this.place(model, slot, [], ""); model.changedSlots.add(slot); this.changed(); } continue; }
      if (want.built && model.built[slot]) {
        const built = model.built[slot];
        if (shown.length !== built.length || !shown.every(m => built.includes(m))) { this.place(model, slot, built, built[0].userData.attach); this.changed(); }
        continue;
      }
      if (shown.length && stem(shown[0].userData.model) === stem(want.model)) continue;
      let meshes = model.built[slot];
      if (!meshes || stem(meshes[0].userData.model) !== stem(want.model)) {
        this.loading.add(slot); this.failed.delete(slot); this.changed();
        try { meshes = (await this.preview(want.model, slot, want.attach)).map(m => { const c = m.clone(); c.userData = { ...m.userData, preview: true }; return c; }); }
        catch (error) { this.failed.set(slot, error.message); meshes = null; }
        this.loading.delete(slot);
        // Another form opened meanwhile, or the choice changed: the next sync takes over.
        if (this.studio.stage.entry !== entry) return;
        const now = this.wanted(f)[slot];
        if (!now || stem(now.model) !== stem(want.model)) { this.changed(); continue; }
      }
      if (meshes) { this.place(model, slot, meshes, want.attach); model.changedSlots.add(slot); }
      this.changed();
    }
  }
}
