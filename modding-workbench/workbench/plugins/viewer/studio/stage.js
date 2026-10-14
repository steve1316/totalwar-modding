// The Battle stage: the 3D view of one gallery entry (a unit form, its vanilla equivalent beside it, or a retarget comparison), playing one slot.
// Each side of an entry (rider, mount, vanilla rider, vanilla mount, source, target) is a Rig: its model, bone lines and prop gizmos, posed from its
// animation. The stage owns its renderer, camera and orbit controls, and draws when `render` is called.
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { loadModel } from "../viewer_common.js";

// Shown when nothing has been measured yet.
const DEFAULT_BOX = { cx: 0, cy: 1, cz: 0, w: 1.4, h: 2, d: 1 };

// Bounding box of every bone in the first frame of the given animations. `bodyOnly` leaves out the root and prop bones (the close-up framing).
function measure(list, bodyOnly = false) {
  const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
  for (const a of list) {
    if (!a) continue;
    for (let i = 0; i < a.bones.length; i++) {
      if (bodyOnly && /^(animroot|be_prop_)/.test(a.bones[i][0])) continue;
      for (let k = 0; k < 3; k++) { const v = a.data[i * 7 + k]; min[k] = Math.min(min[k], v); max[k] = Math.max(max[k], v); }
    }
  }
  if (!isFinite(min[0])) return null;
  if (!bodyOnly) min[1] = Math.min(min[1], 0);
  return { cx: (min[0] + max[0]) / 2, cy: (min[1] + max[1]) / 2, cz: (min[2] + max[2]) / 2, w: max[0] - min[0], h: max[1] - min[1], d: max[2] - min[2] };
}

// One side: bone lines, joints, prop gizmos, disc ring and the optional model, all driven by the current animation.
class Rig {
  constructor(stage, side) {
    this.stage = stage; this.side = side; this.color = new THREE.Color(side.color);
    this.group = new THREE.Group(); this.lines = new THREE.Group();
    this.group.add(this.lines); stage.scene.add(this.group);
  }
  dispose() { if (this.model) this.group.remove(this.model.group); this.stage.scene.remove(this.group); }
  setModel(model) { this.model = model; if (model) this.group.add(model.group); this.bind(); }
  load(anim) {
    this.lines.clear(); this.anim = anim; this.segs = []; this.joints = []; this.props = [];
    if (!anim) { this.bind(); return; }
    const names = anim.bones.map(b => b[0]);
    const mat = new THREE.LineBasicMaterial({ color: this.color });
    const jointGeo = new THREE.SphereGeometry(0.012, 6, 4), jointMat = new THREE.MeshBasicMaterial({ color: this.color });
    anim.bones.forEach(([name, parent], i) => {
      if (name.startsWith("be_prop_")) {
        const g = new THREE.Group();
        g.add(new THREE.AxesHelper(name === "be_prop_4" ? 0.25 : 0.18));
        if (name === "be_prop_4") {
          g.add(new THREE.Mesh(new THREE.RingGeometry(0.55, 0.62, 40), new THREE.MeshBasicMaterial({ color: 0xc78bff, side: THREE.DoubleSide, transparent: true, opacity: 0.55 })));
        }
        this.lines.add(g); this.props.push([i, g]); return;
      }
      if (parent >= 0 && !names[parent].startsWith("animroot")) {
        const geo = new THREE.BufferGeometry().setAttribute("position", new THREE.Float32BufferAttribute(new Float32Array(6), 3));
        this.lines.add(new THREE.Line(geo, mat)); this.segs.push([i, parent, geo]);
      }
      const j = new THREE.Mesh(jointGeo, jointMat); this.lines.add(j); this.joints.push([i, j]);
    });
    this.bind();
  }
  // Map model bones to animation bones by name.
  bind() { this.map = this.model && this.anim ? this.model.bones.map(b => this.anim.index.get(b.name) ?? -1) : null; }
  // Poses the rig at a time in seconds. Each side loops on its own length, so a mount idle keeps going under a longer rider cast.
  pose(seconds, offsetX) {
    const a = this.anim, view = this.stage.view; if (!a) return;
    const f = Math.floor(seconds * a.fps) % a.frames, n = a.bones.length, d = a.data, at = (i, k) => d[(f * n + i) * 7 + k];
    this.group.position.x = offsetX;
    for (const [i, parent, geo] of this.segs) {
      const p = geo.attributes.position.array;
      for (let k = 0; k < 3; k++) { p[k] = at(parent, k); p[3 + k] = at(i, k); }
      geo.attributes.position.needsUpdate = true; geo.computeBoundingSphere();
    }
    for (const [i, j] of this.joints) { j.position.set(at(i, 0), at(i, 1), at(i, 2)); j.visible = view.bones; }
    for (const [i, g] of this.props) { g.visible = view.props; g.position.set(at(i, 0), at(i, 1), at(i, 2)); g.quaternion.set(at(i, 3), at(i, 4), at(i, 5), at(i, 6)); }
    this.lines.children.forEach(c => { if (c.isLine) c.visible = view.bones; });
    if (this.model) {
      this.model.group.visible = view.models;
      this.model.bones.forEach((b, k) => { const i = this.map[k]; if (i >= 0) { b.position.set(at(i, 0), at(i, 1), at(i, 2)); b.quaternion.set(at(i, 3), at(i, 4), at(i, 5), at(i, 6)); } });
    }
  }
}

export class BattleStage {
  // `host` is the element the canvas fills. `getAnim` decodes a manifest animation by id. `data` is the gallery's URL prefix.
  constructor(host, getAnim, data) {
    this.host = host; this.getAnim = getAnim; this.data = data;
    this.renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    host.append(this.renderer.domElement);
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x14161a);
    this.camera = new THREE.PerspectiveCamera(40, 1, 0.01, 200);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.scene.add(new THREE.GridHelper(10, 20, 0x3a3f48, 0x262a31));
    this.scene.add(new THREE.HemisphereLight(0xffffff, 0x404048, 1.6));
    const sun = new THREE.DirectionalLight(0xffffff, 1.6); sun.position.set(2, 4, 3); this.scene.add(sun);
    // What is drawn: models, bones, prop gizmos, the vanilla equivalent, the close-up, the comparison layout and the sides switched off.
    this.view = { models: true, bones: false, props: false, versus: false, closeUp: false, layout: "side", hidden: new Set() };
    // The open entry, its rigs (one per side), the current slot, its length, and the framing boxes.
    this.entry = null; this.rigs = []; this.slot = null; this.frames = 1; this.fps = 20; this.box = null; this.closeBox = null;
    // Models with their props, loaded once per side, so two sides wearing the same model (an Advisor and his vanilla equivalent on the same horse)
    // each get their own copy.
    this.models = new Map();
    // Close-up camera tracking: the point followed last frame and this frame. `split` is a comparison drawn as two halves on a tall screen.
    this.followed = new THREE.Vector3(); this.seen = new THREE.Vector3(); this.split = false;
    new ResizeObserver(() => { this.resize(); this.frameCamera(); }).observe(host);
  }

  isCompare() { return !!this.entry && this.entry.kind === "compare"; }
  // An Advisor form's entry carries its vanilla equivalent (`entry.versus`) as more sides in the "vanilla" group.
  versusOn() { return this.view.versus && !!this.entry && !!this.entry.versus; }
  // How far each side stands from the middle: wider for riders, and for units standing on a prop such as a disc (`be_prop_4`).
  versusOffset() {
    const wide = this.entry.sides.some(side => side.key === "mount") || this.rigs.some(r => r.model && r.model.meshes.some(m => m.userData.attach === "be_prop_4"));
    return wide ? 1.5 : 0.8;
  }
  // The sides listed as toggles: the vanilla ones only while they show.
  listedSides() { return this.entry ? this.entry.sides.filter(side => side.group !== "vanilla" || this.versusOn()) : []; }

  getModel(url, side) {
    const key = `${url}#${side}`;
    if (!this.models.has(key)) this.models.set(key, loadModel(url).catch(e => { console.error("model", url, e); return null; }));
    return this.models.get(key);
  }

  resize() {
    const w = this.host.clientWidth, h = this.host.clientHeight;
    if (!w || !h) return;
    this.split = this.isCompare() && this.view.layout === "side" && w < h;
    this.renderer.setSize(w, h, false); this.camera.aspect = w / (this.split ? h / 2 : h); this.camera.updateProjectionMatrix();
  }

  // Pull the camera back until the entry (both sides when they stand apart) fits the view width as well as its height.
  frameCamera() {
    const { camera, controls, view } = this;
    this.followed.set(0, 0, 0);
    const tanY = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    const b = (view.closeUp && this.closeBox) || this.box || DEFAULT_BOX;
    const apart = (this.isCompare() && view.layout === "side" && !this.split || this.versusOn()) && !view.closeUp;
    const halfW = this.versusOn() && !view.closeUp ? this.versusOffset() + Math.max(b.w, b.d) / 2 + 0.3 : apart ? 2.6 : Math.max(b.w, b.d) / 2 + 0.3;
    const halfH = b.h / 2 + 0.3;
    const distance = Math.max(halfH / tanY, halfW / (tanY * camera.aspect)) + Math.max(b.w, b.d) / 4;
    // The close-up looks from the rider's left and a little above, where the shield and the staff hand are.
    if (view.closeUp && this.closeBox) camera.position.set(b.cx + distance * 0.9, b.cy + halfH * 0.5, b.cz + distance * 0.45);
    else camera.position.set(b.cx + distance * 0.5, b.cy + halfH * 0.4, b.cz + distance * 0.87);
    controls.target.set(apart ? 0 : b.cx, b.cy, b.cz); controls.update();
  }

  // Opens an entry: builds its rigs, loads its models and the slot's animations. Returns once it is drawn.
  async open(entry, slot) {
    this.entry = entry;
    const mine = entry;
    this.rigs.forEach(r => r.dispose());
    this.rigs = entry.sides.map(side => new Rig(this, side));
    this.view.hidden.clear(); this.slot = null;
    const loaded = await Promise.all(entry.sides.map(side => side.model ? this.getModel(this.data + side.model, side.key) : null));
    if (this.entry !== mine) return false;
    this.rigs.forEach((r, i) => r.setModel(loaded[i]));
    const firstAnims = await Promise.all(entry.sides.map(side => this.getAnim(slot.anims[side.key])));
    this.box = measure(firstAnims); this.closeBox = measure(firstAnims.slice(0, 1), true);
    this.resize(); this.frameCamera();
    return this.select(slot);
  }

  // Plays a slot. Returns false when another slot was picked meanwhile.
  async select(slot) {
    this.slot = slot;
    const list = await Promise.all(this.entry.sides.map(side => this.getAnim(slot.anims[side.key])));
    if (this.slot !== slot) return false;
    this.rigs.forEach((r, i) => r.load(list[i]));
    const main = list.find(a => a);
    this.frames = main ? main.frames : 1; this.fps = main ? main.fps : 20;
    this.lengths = list.map(a => a ? a.frames : 0);
    return true;
  }

  // In close-up the camera follows the first side's root bone, so a rider lunging or a disc drifting stays in view.
  follow(time) {
    const r = this.rigs[0], a = r && r.anim; if (!a || !a.index.has("root")) return;
    const i = a.index.get("root"), n = a.bones.length, rootAt = (f, k) => a.data[(f * n + i) * 7 + k];
    if (this.followed.lengthSq() === 0) this.followed.set(rootAt(0, 0) + r.group.position.x, rootAt(0, 1) + 0.25, rootAt(0, 2));
    const f = Math.floor(time * a.fps) % a.frames;
    this.seen.set(rootAt(f, 0) + r.group.position.x, rootAt(f, 1) + 0.25, rootAt(f, 2));
    const delta = this.seen.clone().sub(this.followed); this.camera.position.add(delta); this.controls.target.add(delta);
    this.followed.copy(this.seen);
  }

  // Poses every side at `time` seconds and draws.
  render(time) {
    if (!this.entry) return;
    const view = this.view, compare = this.isCompare();
    const offset = compare && view.layout === "side" && !this.split ? 1.3 : 0, apart = this.versusOn() ? this.versusOffset() : 0;
    this.rigs.forEach((r, i) => r.pose(time, compare ? (i ? offset : -offset) : r.side.group === "vanilla" ? apart : -apart));
    if (view.closeUp) this.follow(time);
    this.controls.update();
    const w = this.host.clientWidth, h = this.host.clientHeight, renderer = this.renderer;
    const shown = r => !view.hidden.has(r.side.key) && !!r.anim && (r.side.group !== "vanilla" || this.versusOn());
    if (this.split) {
      renderer.setScissorTest(true);
      this.rigs.forEach((rig, k) => {
        this.rigs.forEach(other => other.group.visible = other === rig && shown(rig));
        const y = k === 0 ? h / 2 : 0;
        renderer.setViewport(0, y, w, h / 2); renderer.setScissor(0, y, w, h / 2); renderer.render(this.scene, this.camera);
      });
      renderer.setScissorTest(false);
    } else {
      this.rigs.forEach(r => r.group.visible = shown(r));
      renderer.setViewport(0, 0, w, h); renderer.render(this.scene, this.camera);
    }
  }
}
