// Model thumbnails for the Look tab's lists. An `<img data-thumb="<model path>">` shows the project's cached picture at once (`api/thumbs`).
// Without one it is filled once it scrolls into view: the server exports the model (`api/props`, several at a time), it is drawn in its bind pose
// on a small off-screen stage lit like the Battle stage, and the picture is kept on the server (`api/thumb`) for next time. `warm` draws and keeps
// the pictures of a whole list in the background, after the ones on screen.
import * as THREE from "three";
import { loadModel } from "../viewer_common.js";

// Thumbnail size in pixels.
const SIZE = 160;

// Models one export request asks for.
const BATCH = 4;

// How many times longer than broad a weapon is when it is laid corner to corner (a sword), rather than stood upright (a kite shield).
const LONG = 3;

// The drawing style. Kept pictures of an older style (file names end "_<style>.png") are drawn again. 2: weapons seen across the blade.
// 3: a broad weapon stands on its narrower end. 4: a weapon tilted in its file is framed by its own directions.
const STYLE = 4;

export class Thumbnails {
  constructor(studio) {
    // `cached` is the promised index of kept pictures (model -> url), `images` each drawn model's promised picture (a url, or null when it
    // could not be drawn), `queue` the models waiting to be drawn with the images showing them (none for a background one).
    this.studio = studio; this.images = new Map(); this.queue = []; this.busy = false; this.stage = null;
    const folder = studio.api.replace(/api\/$/, "thumbs/");
    this.cached = fetch(studio.api + "thumbs").then(r => r.json()).catch(() => ({}))
      .then(index => new Map(Object.entries(index).filter(([, file]) => file.endsWith(`_${STYLE}.png`)).map(([model, file]) => [model, folder + file])));
    this.observer = new IntersectionObserver(seen => seen.forEach(e => { if (e.isIntersecting) { this.observer.unobserve(e.target); this.show(e.target); } }), { rootMargin: "200px" });
  }

  // Fills every thumbnail image under a container: a kept picture at once (the browser loads it when it scrolls near), the rest once they
  // scroll into view. The images are found straight away, so a container that is a fragment can be put on the page meanwhile.
  async fill(container) {
    const imgs = [...container.querySelectorAll("img[data-thumb]:not([src])")], kept = await this.cached;
    for (const img of imgs) {
      const url = kept.get(img.dataset.thumb);
      if (url) { img.loading = "lazy"; img.src = url; } else this.observer.observe(img);
    }
  }

  async show(img) {
    const model = img.dataset.thumb, kept = (await this.cached).get(model);
    if (kept) { img.src = kept; return; }
    this.request(model, img).then(image => { if (image) img.src = image; else img.classList.add("missing"); });
  }

  // The promised picture of a model, queued for drawing once. `img` is the image showing it, or none for a background one.
  request(model, img) {
    if (!this.images.has(model)) { this.images.set(model, new Promise(done => this.queue.push({ model, done, imgs: img ? [img] : [] }))); this.pump(); }
    else if (img) { const waiting = this.queue.find(q => q.model === model); if (waiting) waiting.imgs.push(img); }
    return this.images.get(model);
  }

  // Draws and keeps, in the background, the pictures of every model in a list that has none yet.
  async warm(models) {
    const kept = await this.cached;
    for (const model of models) if (!kept.has(model)) this.request(model, null);
  }

  // Exports, draws and keeps the waiting models, a batch at a time: the ones on screen first, then the background ones.
  async pump() {
    if (this.busy || !this.queue.length) return;
    // Models whose rows are gone (a new search) are dropped, and asked for again if they show up later.
    const gone = q => q.imgs.length && !q.imgs.some(img => img.isConnected);
    for (const q of this.queue.filter(gone)) this.images.delete(q.model);
    this.queue = this.queue.filter(q => !gone(q)).sort((a, b) => (b.imgs.length > 0) - (a.imgs.length > 0));
    if (!this.queue.length) return;
    this.busy = true;
    const batch = this.queue.splice(0, BATCH);
    let urls = [];
    try {
      const r = await fetch(this.studio.api + "props", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items: batch.map(b => ({ model: b.model, slot: "thumb", attach: "" })) }) });
      urls = (await r.json()).urls || [];
    } catch (error) { console.error("thumbnails", error); }
    const kept = await this.cached;
    for (const [i, b] of batch.entries()) {
      let image = null;
      try { if (urls[i]) image = await this.draw(this.studio.data + urls[i]); } catch (error) { console.error("thumbnail", b.model, error); }
      if (image) {
        kept.set(b.model, image);
        fetch(this.studio.api + "thumb", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ model: b.model, image, style: STYLE }) })
          .catch(error => console.error("keep thumbnail", error));
      }
      b.done(image);
    }
    this.busy = false;
    this.pump();
  }

  // A rigid model's own directions, from its vertices (principal axes), so a model tilted in its file is framed like a straight one. Each
  // direction points along the world axis it is closest to. Returns { centre, axes: [long, broad, thin], sizes, lean }, `lean` being 1 when
  // more of the model sits toward the end `long` points to, else -1.
  shape(meshes) {
    const points = [];
    for (const mesh of meshes) {
      const pos = mesh.geometry.attributes.position;
      for (let i = 0; i < pos.count; i++) points.push(new THREE.Vector3().fromBufferAttribute(pos, i).applyMatrix4(mesh.matrixWorld));
    }
    const mean = points.reduce((sum, p) => sum.add(p), new THREE.Vector3()).divideScalar(points.length || 1);
    const a = [0, 1, 2].map(i => [0, 1, 2].map(j => points.reduce((sum, p) => sum + (p.getComponent(i) - mean.getComponent(i)) * (p.getComponent(j) - mean.getComponent(j)), 0)));
    // Jacobi rotations: `a` turns diagonal and the columns of `v` become its eigenvectors.
    const v = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
    for (let sweep = 0; sweep < 50; sweep++) {
      let [p, q] = [0, 1];
      for (const [i, j] of [[0, 2], [1, 2]]) if (Math.abs(a[i][j]) > Math.abs(a[p][q])) [p, q] = [i, j];
      if (Math.abs(a[p][q]) < 1e-12) break;
      const theta = (a[q][q] - a[p][p]) / (2 * a[p][q]), t = Math.sign(theta || 1) / (Math.abs(theta) + Math.sqrt(theta * theta + 1));
      const c = 1 / Math.sqrt(t * t + 1), s = t * c, turn = (m, k, row) => {
        const [x, y] = row ? [m[p][k], m[q][k]] : [m[k][p], m[k][q]], [nx, ny] = [c * x - s * y, s * x + c * y];
        if (row) [m[p][k], m[q][k]] = [nx, ny]; else [m[k][p], m[k][q]] = [nx, ny];
      };
      for (let k = 0; k < 3; k++) turn(a, k, false);
      for (let k = 0; k < 3; k++) turn(a, k, true);
      for (let k = 0; k < 3; k++) turn(v, k, false);
    }
    const found = [0, 1, 2].map(k => {
      const axis = new THREE.Vector3(v[0][k], v[1][k], v[2][k]).normalize();
      const main = [0, 1, 2].reduce((best, i) => Math.abs(axis.getComponent(i)) > Math.abs(axis.getComponent(best)) ? i : best, 0);
      if (axis.getComponent(main) < 0) axis.negate();
      let min = Infinity, max = -Infinity;
      for (const p of points) { const d = p.clone().sub(mean).dot(axis); min = Math.min(min, d); max = Math.max(max, d); }
      return { axis, size: max - min, middle: (min + max) / 2 };
    }).sort((x, y) => y.size - x.size);
    const centre = found.reduce((sum, f) => sum.addScaledVector(f.axis, f.middle), mean.clone());
    return { centre, axes: found.map(f => f.axis), sizes: found.map(f => f.size), lean: found[0].middle > 0 ? -1 : 1 };
  }

  // Draws one exported model framed to fit, then frees it.
  async draw(url) {
    if (!this.stage) {
      const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
      renderer.setSize(SIZE, SIZE); renderer.outputColorSpace = THREE.SRGBColorSpace;
      const scene = new THREE.Scene();
      scene.add(new THREE.HemisphereLight(0xffffff, 0x404048, 1.6));
      const sun = new THREE.DirectionalLight(0xffffff, 1.6); sun.position.set(2, 4, 3); scene.add(sun);
      this.stage = { renderer, scene, camera: new THREE.PerspectiveCamera(30, 1, 0.01, 100) };
    }
    const { renderer, scene, camera } = this.stage, model = await loadModel(url, { shared: false, tint: false });
    await model.ready;
    scene.add(model.group); model.group.updateMatrixWorld(true);
    const box = new THREE.Box3();
    for (const mesh of model.meshes) { mesh.geometry.computeBoundingBox(); box.union(mesh.geometry.boundingBox.clone().applyMatrix4(mesh.matrixWorld)); }
    const centre = box.getCenter(new THREE.Vector3()), extent = box.getSize(new THREE.Vector3()), tan = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    if (model.meshes.some(m => m.isSkinnedMesh)) {
      // A model that bends with the body is seen from the front (models face +z), a little to the right and above.
      const distance = (extent.length() || 1) / (2 * tan);
      camera.up.set(0, 1, 0);
      camera.position.set(centre.x + distance * 0.35, centre.y + distance * 0.2, centre.z + distance * 0.92);
      camera.lookAt(centre);
    } else {
      // A weapon is seen across its thinnest side (the flat of a blade or a shield's face). A long one is laid corner to corner so it fills the
      // tile. A broad one (a shield) stands on its narrower end: the end of its length holding less of the model points down.
      const shape = this.shape(model.meshes), [long, broad, thin] = shape.sizes, diagonal = long > LONG * broad;
      const across = diagonal ? (long + broad) / Math.SQRT2 : long;
      camera.up.copy(diagonal ? shape.axes[0].clone().add(shape.axes[1]).normalize() : shape.axes[0].clone().multiplyScalar(shape.lean));
      const distance = (across || 1) / (2 * 0.9 * tan) + thin / 2;
      camera.position.copy(shape.centre).addScaledVector(shape.axes[2], distance);
      camera.lookAt(shape.centre);
    }
    renderer.render(scene, camera);
    const image = renderer.domElement.toDataURL("image/png");
    scene.remove(model.group);
    for (const mesh of model.meshes) {
      mesh.geometry.dispose();
      if (mesh.material.map) mesh.material.map.dispose();
      mesh.material.dispose();
    }
    return image;
  }
}
