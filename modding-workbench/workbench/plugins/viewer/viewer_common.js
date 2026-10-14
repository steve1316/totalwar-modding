// Model and animation loading shared by index.html and portrait.html. The exporter copies this file next to them.
import * as THREE from "three";

// Returns a loader for the manifest's animations, whose bundle paths are relative to `base`. Each animation and each bundle file is fetched once.
// Each bone of each frame is 7 int16 values: world position * scale, then the world quaternion * 32767. The decoded animation keeps them as
// floats in `data`, with `bones` ([name, parent] pairs), `count` (bones per frame), `fps`, `frames` and `index` (bone name -> bone index).
export function animLoader(manifest, base = "") {
  const bundles = new Map(), anims = new Map();
  function getBundle(i) {
    if (!bundles.has(i)) bundles.set(i, fetch(base + manifest.bundles[i]).then(r => { if (!r.ok) throw new Error(r.status); return r.arrayBuffer(); }));
    return bundles.get(i);
  }
  return async function getAnim(id) {
    if (id === undefined || id === null) return null;
    if (!anims.has(id)) anims.set(id, (async () => {
      const a = manifest.anims[id], rig = manifest.rigs[a.rig], buffer = await getBundle(a.bundle);
      const raw = new Int16Array(buffer, a.offset, a.frames * rig.length * 7), data = new Float32Array(raw.length);
      for (let i = 0; i < raw.length; i += 7) {
        for (let k = 0; k < 3; k++) data[i + k] = raw[i + k] * a.scale;
        for (let k = 3; k < 7; k++) data[i + k] = raw[i + k] / 32767;
      }
      return { bones: rig, count: rig.length, fps: a.fps, frames: a.frames, data, index: new Map(rig.map((b, i) => [b[0], i])) };
    })());
    return anims.get(id);
  };
}

// Loads an exported model: skinned meshes on flat bones that take world transforms straight from an animation. Rigid props sit in the local
// space of their attach bone, and are left out when `props` is false. Each mesh keeps its `slot`, `model` path and `attach` bone in `userData`.
// Returns { group, bones, inverses, meshes, missing, ready }, `ready` settling once every texture has loaded or failed.
export async function loadModel(url, { props = true } = {}) {
  const doc = await (await fetch(url)).json();
  const buffer = await (await fetch(url.replace(/[^/]+$/, doc.bin))).arrayBuffer();
  const bones = doc.bones.map(name => { const b = new THREE.Bone(); b.name = name; return b; });
  const inverses = doc.inverse_bind.map(m => new THREE.Matrix4().fromArray(m));
  // Start every bone at its bind pose.
  inverses.forEach((m, i) => new THREE.Matrix4().copy(m).invert().decompose(bones[i].position, bones[i].quaternion, bones[i].scale));
  const skeleton = new THREE.Skeleton(bones, inverses);
  const group = new THREE.Group();
  bones.forEach(b => group.add(b));
  const loader = new THREE.TextureLoader(), textures = new Map(), meshes = [], loading = [];
  for (const m of doc.meshes) {
    if (!m.skinned && !props) continue;
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.BufferAttribute(new Float32Array(buffer, m.position, m.count * 3), 3));
    g.setAttribute("normal", new THREE.BufferAttribute(new Float32Array(buffer, m.normal, m.count * 3), 3));
    g.setAttribute("uv", new THREE.BufferAttribute(new Float32Array(buffer, m.uv, m.count * 2), 2));
    g.setIndex(new THREE.BufferAttribute(new Uint16Array(buffer, m.index, m.index_count), 1));
    const mat = new THREE.MeshLambertMaterial({ color: m.texture ? 0xffffff : 0x9a9aa2, side: THREE.DoubleSide });
    if (m.texture) {
      if (!textures.has(m.texture)) {
        let t;
        loading.push(new Promise(done => { t = loader.load(url.replace(/[^/]+$/, m.texture), done, undefined, done); }));
        t.flipY = false; t.colorSpace = THREE.SRGBColorSpace; textures.set(m.texture, t);
      }
      mat.map = textures.get(m.texture);
      if (m.alpha) mat.alphaTest = 0.5;
    }
    let mesh;
    if (m.skinned) {
      g.setAttribute("skinIndex", new THREE.BufferAttribute(new Uint16Array(buffer, m.skin_index, m.count * 4), 4));
      g.setAttribute("skinWeight", new THREE.BufferAttribute(new Float32Array(buffer, m.skin_weight, m.count * 4), 4));
      mesh = new THREE.SkinnedMesh(g, mat);
      mesh.bind(skeleton, new THREE.Matrix4());
      group.add(mesh);
    } else {
      mesh = new THREE.Mesh(g, mat);
      const bone = bones[doc.bones.indexOf(m.attach)];
      (bone || group).add(mesh);
    }
    mesh.name = m.slot;
    mesh.userData = { slot: m.slot, model: m.model || "", attach: m.attach };
    mesh.frustumCulled = false;
    meshes.push(mesh);
  }
  return { group, bones, inverses, meshes, missing: doc.missing, ready: Promise.all(loading) };
}
