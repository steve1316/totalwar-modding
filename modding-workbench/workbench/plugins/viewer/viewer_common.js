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

// Textures by URL, shared by every model loaded with `shared` on, so a texture several models use is fetched, decoded and uploaded once. Each is
// { texture, ready }.
const sharedTextures = new Map();

// The faction's three uniform colours, shared by every tinted material, so `setFactionColours` recolours every model at once. White leaves
// the base colour as it is.
const factionColours = [0, 1, 2].map(() => ({ value: new THREE.Color(1, 1, 1) }));

// The heraldry column a model with a heraldry palette (Bretonnian knights) wears, shared like the faction colours. In game each soldier gets one.
const heraldry = { value: 0 };

// Sets the faction colours models are tinted with, as three "RRGGBB" hex strings (sRGB, as the game's `factions_tables` holds them).
export function setFactionColours(hexes) { hexes.forEach((hex, i) => factionColours[i].value.set(`#${hex}`)); }

// Sets the heraldry column (from 0) of models with a heraldry palette.
export function setHeraldry(column) { heraldry.value = column; }

// Shows a mesh with or without the colours its mask paints (an outfit worn unpainted). A mesh with no mask is left alone.
export function setPainted(mesh, on) { const paint = mesh.material && mesh.material.userData.paint; if (paint) paint.value = on ? 1 : 0; }

// Tints a material's base colour where its mask marks it, as the game does: each of the mask's red, green and blue channels multiplies the
// base colour by a colour. Those are the faction's three uniform colours, or with a heraldry `palette` (`columns` wide) the top and bottom colours
// of the heraldry column, then the faction's third.
function tint(material, mask, palette, columns) {
  // 1 paints the colours, 0 leaves the base colour as it is (`setPainted`).
  material.userData.paint = { value: 1 };
  material.onBeforeCompile = shader => {
    Object.assign(shader.uniforms, { tintMask: { value: mask }, painted: material.userData.paint });
    factionColours.forEach((colour, i) => { shader.uniforms[`factionColour${i + 1}`] = colour; });
    let header = "uniform sampler2D tintMask;\nuniform float painted;\nuniform vec3 factionColour1, factionColour2, factionColour3;", colours = ["factionColour1", "factionColour2"];
    if (palette) {
      Object.assign(shader.uniforms, { tintPalette: { value: palette }, tintColumns: { value: columns }, heraldry });
      header += `\nuniform sampler2D tintPalette;\nuniform float tintColumns, heraldry;
        vec3 heraldryColour(float row) { return texture2D(tintPalette, vec2((mod(heraldry, tintColumns) + 0.5) / tintColumns, row)).rgb; }`;
      colours = ["heraldryColour(0.25)", "heraldryColour(0.75)"];
    }
    shader.fragmentShader = shader.fragmentShader
      .replace("#include <common>", `#include <common>\n${header}`)
      .replace("#include <map_fragment>", `#include <map_fragment>
        vec3 tintWeights = texture2D(tintMask, vMapUv).rgb * painted;
        diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * ${colours[0]}, tintWeights.r);
        diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * ${colours[1]}, tintWeights.g);
        diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * factionColour3, tintWeights.b);`);
  };
  material.customProgramCacheKey = () => palette ? "heraldry_tint" : "faction_tint";
}

// Loads an exported model: skinned meshes on flat bones that take world transforms straight from an animation. Rigid props sit in the local
// space of their attach bone, and are left out when `props` is false. Each mesh keeps its `slot`, `model` path and `attach` bone in `userData`.
// With `shared` off the model gets textures of its own, for a caller that frees them (the thumbnails). With `tint` on, meshes with a colour mask
// take the colours of `setFactionColours`, or of their heraldry palette's column (`setHeraldry`).
// Returns { group, bones, inverses, meshes, missing, ready }, `ready` settling once every texture has loaded or failed.
export async function loadModel(url, { props = true, shared = true, tint: tinted = true } = {}) {
  // The vertex data is named after the model's json, so both are fetched at once.
  const guess = url.replace(/\.json$/, ".bin"), binary = fetch(guess).then(r => r.ok ? r.arrayBuffer() : null);
  const doc = await (await fetch(url)).json(), binUrl = url.replace(/[^/]+$/, doc.bin);
  const buffer = (binUrl === guess && await binary) || await (await fetch(binUrl)).arrayBuffer();
  const bones = doc.bones.map(name => { const b = new THREE.Bone(); b.name = name; return b; });
  const inverses = doc.inverse_bind.map(m => new THREE.Matrix4().fromArray(m));
  // Start every bone at its bind pose.
  inverses.forEach((m, i) => new THREE.Matrix4().copy(m).invert().decompose(bones[i].position, bones[i].quaternion, bones[i].scale));
  const skeleton = new THREE.Skeleton(bones, inverses);
  const group = new THREE.Group();
  bones.forEach(b => group.add(b));
  const loader = new THREE.TextureLoader(), textures = shared ? sharedTextures : new Map(), meshes = [], loading = [];
  // An image of the model's folder, loaded once per URL. A mask holds weights, not colours.
  const image = (file, colorSpace) => {
    const textureUrl = url.replace(/[^/]+$/, file);
    if (!textures.has(textureUrl)) {
      let texture;
      const ready = new Promise(done => { texture = loader.load(textureUrl, done, undefined, done); });
      texture.flipY = false; texture.colorSpace = colorSpace; textures.set(textureUrl, { texture, ready });
    }
    loading.push(textures.get(textureUrl).ready);
    return textures.get(textureUrl).texture;
  };
  // A palette is read one column at a time, so its colours must not blur into each other.
  const palette = texture => { texture.magFilter = texture.minFilter = THREE.NearestFilter; texture.generateMipmaps = false; return texture; };
  for (const m of doc.meshes) {
    if (!m.skinned && !props) continue;
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.BufferAttribute(new Float32Array(buffer, m.position, m.count * 3), 3));
    g.setAttribute("normal", new THREE.BufferAttribute(new Float32Array(buffer, m.normal, m.count * 3), 3));
    g.setAttribute("uv", new THREE.BufferAttribute(new Float32Array(buffer, m.uv, m.count * 2), 2));
    g.setIndex(new THREE.BufferAttribute(new Uint16Array(buffer, m.index, m.index_count), 1));
    const mat = new THREE.MeshLambertMaterial({ color: m.texture ? 0xffffff : 0x9a9aa2, side: THREE.DoubleSide });
    if (m.texture) {
      mat.map = image(m.texture, THREE.SRGBColorSpace);
      if (m.alpha) mat.alphaTest = 0.5;
      if (m.mask && tinted) tint(mat, image(m.mask, THREE.NoColorSpace), m.palette && palette(image(m.palette, THREE.SRGBColorSpace)), m.columns);
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
