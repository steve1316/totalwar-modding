// Model thumbnails for the Look tab's lists. An `<img data-thumb="<model path>">` shows the project's cached picture at once (`api/thumbs`).
// Without one it is filled once it scrolls into view: the server exports the model (`api/props`, several at a time), it is drawn in its bind pose
// on a small off-screen stage lit like the Battle stage, and the picture is kept on the server (`api/thumb`) for next time. `warm` draws and keeps
// the pictures of a whole list in the background, after the ones on screen.
import * as THREE from "three";
import { loadModel } from "../viewer_common.js";

// Thumbnail size in pixels.
const SIZE = 160;

// Models one export request asks for.
const BATCH = 8;

export class Thumbnails {
  constructor(studio) {
    // `cached` is the promised index of kept pictures (model -> url), `images` each drawn model's promised picture (a url, or null when it
    // could not be drawn), `queue` the models waiting to be drawn with the images showing them (none for a background one).
    this.studio = studio; this.images = new Map(); this.queue = []; this.busy = false; this.stage = null;
    const folder = studio.api.replace(/api\/$/, "thumbs/");
    this.cached = fetch(studio.api + "thumbs").then(r => r.json()).catch(() => ({}))
      .then(index => new Map(Object.entries(index).map(([model, file]) => [model, folder + file])));
    this.observer = new IntersectionObserver(seen => seen.forEach(e => { if (e.isIntersecting) { this.observer.unobserve(e.target); this.show(e.target); } }), { rootMargin: "200px" });
  }

  // Fills every thumbnail image under a container: a kept picture at once (the browser loads it when it scrolls near), the rest once they
  // scroll into view.
  async fill(container) {
    const kept = await this.cached;
    for (const img of container.querySelectorAll("img[data-thumb]:not([src])")) {
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
    const waiting = this.queue.find(q => q.model === model);
    if (waiting) { if (img) waiting.imgs.push(img); }
    else if (!this.images.has(model)) { this.images.set(model, new Promise(done => this.queue.push({ model, done, imgs: img ? [img] : [] }))); this.pump(); }
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
        fetch(this.studio.api + "thumb", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ model: b.model, image }) })
          .catch(error => console.error("keep thumbnail", error));
      }
      b.done(image);
    }
    this.busy = false;
    this.pump();
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
    const { renderer, scene, camera } = this.stage, model = await loadModel(url);
    await model.ready;
    scene.add(model.group); model.group.updateMatrixWorld(true);
    const box = new THREE.Box3();
    for (const mesh of model.meshes) { mesh.geometry.computeBoundingBox(); box.union(mesh.geometry.boundingBox.clone().applyMatrix4(mesh.matrixWorld)); }
    const centre = box.getCenter(new THREE.Vector3()), size = box.getSize(new THREE.Vector3()).length() || 1;
    const distance = size / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)));
    // Seen from the front (models face +z), a little to the right and above.
    camera.position.set(centre.x + distance * 0.35, centre.y + distance * 0.2, centre.z + distance * 0.92); camera.lookAt(centre);
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
