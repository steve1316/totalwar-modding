// The Portrait stage and its inspector tab: the unit's 3D portrait camera, drawn in the round in-game porthole frame, with the vanilla reference
// beside it. The gallery's `manifest.portrait` gives the looks (hooded, hoodless), the porthole idle animation, the registry's camera values, the
// vanilla reference and the rounds tried in game. The camera values are edits like any other: the Jobs bar saves them into the registry.
import * as THREE from "three";
import { loadModel } from "../viewer_common.js";

// Camera model, calibrated against in-game porthole screenshots of rounds 1, 2, 3 and 5 (see the Advisor Overhaul's RESEARCH_NOTES.md):
// - The camera looks at a target straight above the head bone of frame 0: `y` metres above it, plus `ANCHOR_DY`.
// - It sits `z` plus `DISTANCE_PAD` metres from that target, along its own view axis. `pitch` swings it up around the target (positive looks down on
//   him) and `yaw` swings it around him.
// - `fov` is the vertical field of view. The visible circle spans the full fov, so its diameter is the render's height.
const ANCHOR_DY = -0.037;
const DISTANCE_PAD = 0.10;
// Idle frame shown by default. The in-game shots show the head turned ~10 degrees, as in frames 75-93 of the idle.
const POSE_FRAME = 84;
// Slider ranges: [key, min, max, step].
const FIELDS = [["z", 0.3, 2.5, 0.01], ["y", -0.25, 0.35, 0.005], ["yaw", -60, 60, 0.5], ["pitch", -30, 40, 0.5], ["fov", 10, 60, 0.5]];

// A number in the registry's style: at least one decimal, at most three.
const fmt = v => { const r = Math.round(v * 1000) / 1000; return Number.isInteger(r) ? r.toFixed(1) : String(r); };

// A soft radial backdrop texture, a little lighter in the middle like the in-game glass.
function backdrop() {
  const c = document.createElement("canvas"); c.width = c.height = 256;
  const g = c.getContext("2d"), grad = g.createRadialGradient(128, 110, 10, 128, 128, 180);
  grad.addColorStop(0, "#4a525c"); grad.addColorStop(1, "#1c2127");
  g.fillStyle = grad; g.fillRect(0, 0, 256, 256);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}

// One round render: its own renderer, scene, camera and posed model.
class Porthole {
  constructor(host, owner) {
    this.host = host; this.owner = owner;
    this.renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 3));
    host.append(this.renderer.domElement);
    const mask = document.createElement("div"); mask.className = "mask"; host.append(mask);
    this.guides = document.createElement("div"); this.guides.className = "guides"; this.guides.hidden = true; host.append(this.guides);
    this.scene = new THREE.Scene();
    this.scene.background = backdrop();
    this.scene.add(new THREE.HemisphereLight(0xdfe6f0, 0x2a2622, 1.3));
    const key = new THREE.DirectionalLight(0xfff1dc, 1.9); key.position.set(-1.2, 2.2, 2.5); this.scene.add(key);
    const rim = new THREE.DirectionalLight(0x9fb8d8, 0.6); rim.position.set(1.5, 1.0, -1.0); this.scene.add(rim);
    this.camera = new THREE.PerspectiveCamera(30, 1, 0.01, 50);
    this.model = null;
  }
  setModel(model) {
    if (this.model) this.scene.remove(this.model.group);
    this.model = model; if (model) this.scene.add(model.group);
    this.map = model ? model.bones.map(b => this.owner.anim.index.get(b.name) ?? -1) : null;
  }
  // Places the camera from portrait settings values, around the head bone of frame 0.
  setCamera(v) {
    const head0 = this.owner.head0, pitch = THREE.MathUtils.degToRad(v.pitch), yaw = THREE.MathUtils.degToRad(v.yaw);
    const target = new THREE.Vector3(head0.x, head0.y + v.y + ANCHOR_DY, head0.z);
    const dir = new THREE.Vector3(Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), Math.cos(yaw) * Math.cos(pitch));
    this.camera.position.copy(target).addScaledVector(dir, v.z + DISTANCE_PAD);
    this.camera.fov = v.fov; this.camera.updateProjectionMatrix(); this.camera.lookAt(target); this.camera.updateMatrixWorld();
  }
  render(frame) {
    const size = Math.round(this.host.clientWidth);
    if (!size) return;
    if (size !== this.size) { this.size = size; this.renderer.setSize(size, size, false); }
    const anim = this.owner.anim;
    if (this.model) {
      const base = frame * anim.count * 7, d = anim.data;
      this.model.bones.forEach((b, k) => {
        const i = this.map[k]; if (i < 0) return;
        const o = base + i * 7; b.position.set(d[o], d[o + 1], d[o + 2]); b.quaternion.set(d[o + 3], d[o + 4], d[o + 5], d[o + 6]);
      });
    }
    this.renderer.render(this.scene, this.camera);
  }
}

export class PortraitStage {
  // `host` is the stage element the portholes go in. `studio` holds the manifest, the data prefix, the saved tuning values and the edits.
  constructor(host, studio) {
    this.host = host; this.studio = studio; this.data = studio.manifest.portrait;
    this.look = 0; this.models = new Map(); this.ready = null;
    host.innerHTML = `<figure><div class="porthole" data-p="mine"></div><figcaption data-c="mine"></figcaption></figure>
      <figure data-f="ref" hidden><div class="porthole" data-p="ref"></div><figcaption data-c="ref"></figcaption></figure>`;
    this.values = { ...this.saved() };
  }

  // The camera values saved in the registry (or exported with the gallery when the server has none).
  saved() { return (this.studio.tuning && this.studio.tuning.camera_head) || this.data.camera; }

  // Loads the idle animation and the first look, once.
  start() {
    if (!this.ready) this.ready = (async () => {
      this.anim = await this.studio.getAnim(this.data.anim);
      const head = this.anim.index.get("head");
      this.head0 = new THREE.Vector3(this.anim.data[head * 7], this.anim.data[head * 7 + 1], this.anim.data[head * 7 + 2]);
      this.mine = new Porthole(this.host.querySelector('[data-p="mine"]'), this);
      this.ref = new Porthole(this.host.querySelector('[data-p="ref"]'), this);
      this.frames = this.anim.frames; this.fps = this.anim.fps; this.startTime = (POSE_FRAME + 0.5) / this.fps;
      await this.setLook(this.look);
    })();
    return this.ready;
  }

  getModel(url) {
    if (!this.models.has(url)) this.models.set(url, loadModel(this.studio.data + url, { props: false }));
    return this.models.get(url);
  }

  async setLook(i) {
    this.look = i;
    this.mine.setModel(await this.getModel(this.data.looks[i].model));
    this.setValues({});
  }

  // Applies camera changes, marks them as an edit when they differ from the saved values, and refreshes the captions and sliders.
  setValues(changes, note) {
    Object.assign(this.values, changes);
    const saved = this.saved();
    this.studio.edits.camera = Object.keys(saved).some(k => fmt(saved[k]) !== fmt(this.values[k])) ? { ...this.values } : null;
    if (this.mine) this.mine.setCamera(this.values);
    const cap = this.host.querySelector('[data-c="mine"]');
    cap.textContent = `z ${fmt(this.values.z)}  y ${fmt(this.values.y)}  pitch ${fmt(this.values.pitch)}  yaw ${fmt(this.values.yaw)}  fov ${fmt(this.values.fov)}`;
    if (this.tab) this.syncTab(note);
    this.studio.changed();
  }

  // The values were saved: they are the new baseline.
  resetToSaved() { this.values = { ...this.saved() }; this.setValues({}); }

  render(frame) {
    if (!this.mine) return;
    this.mine.render(frame);
    if (!this.host.querySelector('[data-f="ref"]').hidden) this.ref.render(frame);
  }

  // The inspector tab: looks, guides, the vanilla reference, the camera sliders, the presets and a copyable registry line.
  renderTab(container) {
    const data = this.data;
    container.innerHTML = `<div class="p-head">Look</div><div class="tools" data-t="looks"></div>
      <div class="tools"><button data-t="guides">Guides</button><button data-t="ref">Vanilla ref</button></div>
      <div class="p-head">Camera</div><div data-t="sliders"></div>
      <div class="p-head">Presets</div><div class="tools" data-t="presets"></div>
      <div class="copyline"><code data-t="json"></code><button data-t="copy">Copy</button></div><div class="note" data-t="note"></div>`;
    const q = t => container.querySelector(`[data-t="${t}"]`);
    data.looks.forEach((l, i) => {
      const b = document.createElement("button"); b.textContent = l.name; b.classList.toggle("on", i === this.look);
      b.onclick = async () => { await this.setLook(i); [...q("looks").children].forEach((x, k) => x.classList.toggle("on", k === i)); };
      q("looks").append(b);
    });
    q("guides").onclick = () => { const on = this.mine.guides.hidden; this.mine.guides.hidden = this.ref.guides.hidden = !on; q("guides").classList.toggle("on", on); };
    if (data.reference) {
      const c = data.reference.camera;
      q("ref").onclick = async () => {
        const fig = this.host.querySelector('[data-f="ref"]'), show = fig.hidden;
        fig.hidden = !show; q("ref").classList.toggle("on", show);
        if (show && !this.ref.model) { this.ref.setModel(await this.getModel(data.reference.model)); this.ref.setCamera(c); }
        this.host.querySelector('[data-c="ref"]').textContent = `${data.reference.name}: z ${fmt(c.z)}  y ${fmt(c.y)}  pitch ${fmt(c.pitch)}`;
      };
    } else q("ref").hidden = true;
    this.inputs = {};
    for (const [key, min, max, step] of FIELDS) {
      const row = document.createElement("div"); row.className = "arow";
      row.innerHTML = `<label>${key}</label><input type="range" min="${min}" max="${max}" step="${step}"><input type="number" step="${step}" inputmode="decimal">`;
      const [range, number] = row.querySelectorAll("input");
      range.oninput = () => this.setValues({ [key]: +range.value });
      number.onchange = () => { if (number.value !== "" && isFinite(+number.value)) this.setValues({ [key]: +number.value }); };
      this.inputs[key] = { range, number };
      q("sliders").append(row);
    }
    const presets = [{ label: "Saved", camera: this.saved(), note: "The values saved in the registry." }]
      .concat(data.rounds.map((r, i) => ({ label: `R${i + 1}`, camera: r.camera, note: `Round ${i + 1} in game: ${r.note}.` })));
    for (const p of presets) {
      const b = document.createElement("button"); b.textContent = p.label; b.onclick = () => this.setValues({ ...p.camera }, p.note); q("presets").append(b);
    }
    // The clipboard API needs https, so over the LAN fall back to a selection copy.
    q("copy").onclick = async () => {
      try { await navigator.clipboard.writeText(q("json").textContent); }
      catch (e) { const range = document.createRange(); range.selectNodeContents(q("json")); const s = getSelection(); s.removeAllRanges(); s.addRange(range); document.execCommand("copy"); }
      q("copy").textContent = "Copied"; setTimeout(() => q("copy").textContent = "Copy", 1200);
    };
    this.tab = q;
    this.syncTab();
  }

  syncTab(note) {
    if (!this.tab || !this.tab("json")) return;
    for (const [key] of FIELDS) {
      const input = this.inputs[key];
      if (document.activeElement !== input.number) input.number.value = fmt(this.values[key]);
      input.range.value = this.values[key];
    }
    const v = this.values;
    this.tab("json").textContent = `"camera_head": {"z": ${fmt(v.z)}, "y": ${fmt(v.y)}, "yaw": ${fmt(v.yaw)}, "pitch": ${fmt(v.pitch)}, "fov": ${fmt(v.fov)}}`;
    if (note !== undefined) this.tab("note").textContent = note;
  }
}
