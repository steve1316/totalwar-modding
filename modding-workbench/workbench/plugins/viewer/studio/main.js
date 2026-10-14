// The Workbench studio: forms and slots on the left, the stage in the middle (Battle or Portrait), the inspector tabs on the right (a bottom sheet
// on a phone), and the playback and job bar at the bottom. A new inspector tab is a module with `render(container)` added to `TABS`.
import { animLoader } from "../viewer_common.js";
import { AdjustTab } from "./adjust.js";
import { BattleStage } from "./stage.js";
import { Jobs } from "./jobs.js";
import { PortraitStage } from "./portrait.js";
import { SkillsTab } from "./skills.js";
import { StatsTab } from "./stats.js";

const $ = id => document.getElementById(id);
const { esc } = window.UnitPanel;
// Phones get the pickers and the bottom sheet.
const phone = window.matchMedia("(max-width: 899px)");

// //////////////////////////////////////////////////////////////////////////////////////////////////
// Project and studio state

const project = await window.workbenchProject;
const DATA = `p/${project}/data/`, API = `p/${project}/api/`;
const manifest = await (await fetch(DATA + "manifest.json")).json();
let tuning = null, jobs = null;
try { const r = await fetch(API + "tuning"); if (r.ok) tuning = await r.json(); } catch (e) { /* the server is down */ }

// Shared by every module: the gallery, the API, the saved values and the unsaved edits.
const studio = {
  manifest, data: DATA, api: API, tuning, getAnim: animLoader(manifest, DATA),
  panelArt: path => path ? DATA + "art/" + encodeURI(path) : "",
  edits: { props: {}, hand: null, camera: null, registry: {} },
  // Whether the panels compare the form with its vanilla equivalent. Off: each form is first seen on its own.
  compare: false,
  // Called after any edit.
  changed: () => jobs && jobs.refresh(),
  // Called with the API's answer after a save: those values are the new baseline.
  saved(answer) {
    studio.tuning = Object.assign(studio.tuning || {}, answer);
    tabs.stats.saved();
    studio.edits.props = {}; studio.edits.hand = null; studio.edits.registry = {};
    if (manifest.portrait) portrait.resetToSaved();
    tabs.adjust.applyLive(); renderTab(); tabs.skills.renderTree(); studio.changed();
  },
  // Opens the Skills tab (a skill was picked on the tree).
  openSkills() { if (tab !== "skills") selectTab("skills", true); else if (phone.matches && sheet === "peek") setSheet("half"); },
  // Drops every unsaved edit.
  undo() {
    studio.edits.props = {}; studio.edits.hand = null; studio.edits.registry = {};
    if (manifest.portrait) portrait.resetToSaved();
    tabs.adjust.applyLive(); renderTab(); tabs.skills.renderTree(); studio.changed();
  },
};
studio.stage = new BattleStage($("battle"), studio.getAnim, DATA);
const stage = studio.stage;
const portrait = manifest.portrait ? new PortraitStage($("portraitStage"), studio) : null;

// //////////////////////////////////////////////////////////////////////////////////////////////////
// Inspector tabs

const tabs = { stats: new StatsTab(studio), adjust: new AdjustTab(studio), portrait: portrait && { render: c => portrait.renderTab(c) },
               skills: new SkillsTab($("skillsStage"), studio) };
// Tab order and labels. Tabs without a module yet are shown greyed out.
const TABS = [["stats", "Stats"], ["adjust", "Adjust"], ["portrait", "Portrait"], ["skills", "Skills"]];
let tab = "stats";

function renderTabs() {
  $("tabs").innerHTML = TABS.map(([key, label]) => `<button data-tab="${key}" class="${key === tab ? "on" : ""}" ${tabs[key] ? "" : "disabled title=\"Coming next\""}>${label}</button>`).join("");
  $("tabs").querySelectorAll("button").forEach(b => b.onclick = () => selectTab(b.dataset.tab, true));
}
function renderTab() {
  if (tabs[tab]) tabs[tab].render($("inspBody"));
}
// Picks a tab. The Portrait and Skills tabs show their own stage, and the other tabs the Battle stage.
async function selectTab(key, fromUser = false) {
  tab = key; renderTabs();
  if (key === "portrait" || key === "skills") await setMode(key); else if (mode !== "battle") await setMode("battle");
  renderTab();
  if (fromUser && phone.matches && sheet === "peek") setSheet("half");
  writeHash();
}

// The phone's bottom sheet: only the tabs (peek), half the screen, or most of it.
let sheet = "peek";
function setSheet(state) { sheet = state; $("inspector").dataset.sheet = state; }
$("grab").onclick = () => setSheet({ peek: "half", half: "full", full: "peek" }[sheet]);

// //////////////////////////////////////////////////////////////////////////////////////////////////
// Stage mode and view toggles

let mode = "battle";
async function setMode(next) {
  if (next === "portrait" && !portrait) return;
  // The portrait loads first, so the playback loop never runs it half loaded.
  if (next === "portrait") await portrait.start();
  mode = next;
  $("battle").hidden = $("battleTools").hidden = $("info").hidden = mode !== "battle";
  $("portraitStage").hidden = mode !== "portrait"; $("skillsStage").hidden = mode !== "skills";
  $("bar").classList.toggle("noplay", mode === "skills");
  document.querySelectorAll("[data-mode]").forEach(b => b.classList.toggle("on", b.dataset.mode === mode));
  if (mode === "portrait") {
    if (times.portrait === null) times.portrait = portrait.startTime;
  } else if (mode === "skills") {
    tabs.skills.renderTree();
  } else {
    stage.resize(); stage.frameCamera();
  }
  // The stage and its tab go together.
  const wanted = mode === "battle" ? (tab === "portrait" || tab === "skills" ? "stats" : tab) : mode;
  if (tab !== wanted) { tab = wanted; renderTabs(); renderTab(); }
  playing = mode === "battle"; syncPlay(); writeHash();
}
document.querySelectorAll("[data-mode]").forEach(b => b.onclick = () => setMode(b.dataset.mode));
$("modePortrait").hidden = !portrait;

// The stage toolbar: the unit's own side toggles, Compare to Vanilla (a drop-down whose column holds the vanilla sides' toggles while it is on),
// then the view toggles.
function renderToggles() {
  const v = stage.view, entry = stage.entry, chip = s => `<button data-side="${s.key}" style="color:${s.color}" class="${v.hidden.has(s.key) ? "" : "on"}">${esc(s.label)}</button>`;
  const vanillaSides = stage.listedSides().filter(s => s.group === "vanilla");
  $("toggles").innerHTML = (entry && entry.versus ? `<span class="dropdown"><button data-v="versus" class="${v.versus ? "on" : ""}">Compare to Vanilla ${v.versus ? "▴" : "▾"}</button>
      ${v.versus && vanillaSides.length ? `<span class="menu">${vanillaSides.map(chip).join("")}</span>` : ""}</span>` : "")
    + `<button data-v="models" class="${v.models ? "on" : ""}">Models</button><button data-v="bones" class="${v.bones ? "on" : ""}">Bones</button>`
    + `<button data-v="props" class="${v.props ? "on" : ""}">Props</button><button data-v="closeUp" class="${v.closeUp ? "on" : ""}">Close-up</button>`
    + (stage.isCompare() ? `<select data-v="layout"><option value="side">Side by side</option><option value="overlay">Overlay</option></select>` : "");
  $("toggles").querySelectorAll("button[data-v]").forEach(b => b.onclick = () => {
    v[b.dataset.v] = !v[b.dataset.v];
    if (b.dataset.v === "versus" || b.dataset.v === "closeUp") stage.frameCamera();
    renderToggles(); writeHash();
  });
  const layout = $("toggles").querySelector("select");
  if (layout) { layout.value = v.layout; layout.onchange = () => { v.layout = layout.value; stage.resize(); stage.frameCamera(); }; }
  const own = stage.listedSides().filter(s => s.group !== "vanilla");
  $("sides").innerHTML = own.length > 1 ? own.map(chip).join("") : "";
  $("battleTools").querySelectorAll("button[data-side]").forEach(b => b.onclick = () => {
    v.hidden.has(b.dataset.side) ? v.hidden.delete(b.dataset.side) : v.hidden.add(b.dataset.side); renderToggles();
  });
}

// //////////////////////////////////////////////////////////////////////////////////////////////////
// Forms and slots

// Forms grouped by weapon ("Greatsword - On Foot" goes under Greatsword). Gallery entries that are not a form (looks, previews, vanilla
// references, retarget checks) are left out, unless the project has no forms at all.
const groups = new Map(), hasForms = manifest.entries.some(e => e.unit);
manifest.entries.forEach((e, i) => {
  if (hasForms && !e.unit) return;
  const [group, label] = e.unit ? e.name.split(" - ") : ["Gallery", e.name];
  if (!groups.has(group)) groups.set(group, []);
  groups.get(group).push({ index: i, label: label || e.name });
});
let entryIndex = 0, slotFilter = "";

function renderForms() {
  $("forms").innerHTML = [...groups].map(([group, items]) => `<div class="grp">${esc(group)}</div>`
    + items.map(it => `<button data-i="${it.index}" class="${it.index === entryIndex ? "on" : ""}">${esc(it.label)}</button>`).join("")).join("");
  $("forms").querySelectorAll("button").forEach(b => b.onclick = () => openEntry(+b.dataset.i));
  $("formSel").innerHTML = [...groups].map(([group, items]) => `<optgroup label="${esc(group)}">`
    + items.map(it => `<option value="${it.index}" ${it.index === entryIndex ? "selected" : ""}>${esc(group === "Gallery" ? it.label : `${group} · ${it.label}`)}</option>`).join("") + "</optgroup>").join("");
}
$("formSel").onchange = () => openEntry(+$("formSel").value);

function slotTag(s) {
  if (stage.isCompare()) return (s.anims.source !== undefined ? "S" : "-") + (s.anims.target !== undefined ? "R" : "-");
  return s.slots && s.slots.mount ? `mount ${s.slots.mount}` : "";
}
function renderSlots() {
  const entry = stage.entry; if (!entry) return;
  const shown = entry.slots.filter(s => !slotFilter || s.slot.toLowerCase().includes(slotFilter.toLowerCase()));
  $("slots").innerHTML = shown.map(s => `<button data-s="${s.slot}" class="${stage.slot === s ? "on" : ""}"><span>${s.slot}</span><span class="tag">${slotTag(s)}</span></button>`).join("");
  $("slots").querySelectorAll("button").forEach(b => b.onclick = () => selectSlot(entry.slots.find(s => s.slot === b.dataset.s)));
  $("slotSel").innerHTML = entry.slots.map(s => `<option ${stage.slot === s ? "selected" : ""}>${s.slot}</option>`).join("");
}
$("slotSel").onchange = () => selectSlot(stage.entry.slots.find(s => s.slot === $("slotSel").value));
$("search").oninput = e => { slotFilter = e.target.value; renderSlots(); };

function renderInfo() {
  const entry = stage.entry, s = stage.slot; if (!entry || !s) return;
  $("info").innerHTML = `<span><b>${esc(entry.name)}</b> · ${s.slot}</span>` + entry.sides.filter(side => s.paths[side.key] && (side.group !== "vanilla" || stage.versusOn()))
    .map(side => `<span style="color:${side.color}">${s.slots ? s.slots[side.key] + ": " : ""}${esc(s.paths[side.key].split("/").pop())}</span>`).join("");
}

async function openEntry(index, slotName) {
  entryIndex = index; renderForms();
  const entry = manifest.entries[index];
  const first = entry.slots.find(s => s.slot === slotName) || entry.slots.find(s => s.slot === "STAND") || entry.slots[0];
  $("status").hidden = false;
  if (!(await stage.open(entry, first))) return;
  $("status").hidden = true;
  times.battle = 0;
  tabs.adjust.applyLive();
  renderToggles(); renderSlots(); renderInfo();
  if (tab !== "portrait") renderTab();
  writeHash();
}
async function selectSlot(slot) {
  if (!(await stage.select(slot))) return;
  times.battle = 0;
  renderSlots(); renderInfo(); writeHash();
}

// //////////////////////////////////////////////////////////////////////////////////////////////////
// Playback

// Time in seconds on each stage. The portrait starts paused on its calibration frame.
const times = { battle: 0, portrait: null };
let playing = true;
const active = () => mode === "portrait" ? portrait : mode === "skills" ? null : stage;
function syncPlay() { $("play").textContent = playing ? "Pause" : "Play"; }
$("play").onclick = () => { playing = !playing; syncPlay(); };
$("frame").oninput = e => { times[mode] = (+e.target.value + 0.5) / active().fps; playing = false; syncPlay(); };
window.addEventListener("keydown", e => {
  if (e.target.closest("input, select, textarea")) return;
  if (e.code === "Space") { e.preventDefault(); $("play").click(); }
  const step = d => { const a = active(); times[mode] = (Math.min(a.frames - 1, Math.max(0, Math.floor(times[mode] * a.fps) + d)) + 0.5) / a.fps; playing = false; syncPlay(); };
  if (e.code === "ArrowRight") step(1);
  if (e.code === "ArrowLeft") step(-1);
});

let last = performance.now();
function tick(now) {
  const dt = (now - last) / 1000; last = now;
  const a = active();
  if (a && a.frames) {
    if (playing) times[mode] = ((times[mode] || 0) + dt * +$("speed").value) % (a.frames / a.fps);
    const frame = Math.min(a.frames - 1, Math.floor((times[mode] || 0) * a.fps));
    $("frame").max = a.frames - 1; $("frame").value = frame; $("fnum").textContent = `${frame}/${a.frames - 1}`;
    if (mode === "battle") stage.render(times.battle); else portrait.render(frame);
  }
  requestAnimationFrame(tick);
}

// //////////////////////////////////////////////////////////////////////////////////////////////////
// Layout, hash and start

// The job buttons sit in the bottom bar on a desktop and inside the sheet on a phone.
function placeJobs() { (phone.matches ? $("sheetJobs") : $("barJobs")).append($("jobs")); }
phone.addEventListener("change", placeJobs);

function writeHash() {
  if (!stage.slot) return;
  const parts = [`u=${entryIndex}`, `s=${stage.slot.slot}`, stage.view.versus ? "vs=1" : "", `tab=${tab}`].filter(Boolean);
  history.replaceState(null, "", "#" + parts.join("&"));
}

jobs = tuning ? new Jobs($("jobs"), studio) : null;
if (!jobs) $("jobs").hidden = true;
placeJobs();
const params = new URLSearchParams(location.hash.slice(1));
stage.view.versus = params.get("vs") === "1";
renderTabs();
// Without a link, the first form opens.
const firstForm = Math.max(0, manifest.entries.findIndex(e => e.unit));
const linked = params.has("u") ? Math.min(manifest.entries.length - 1, Math.max(0, +params.get("u"))) : firstForm;
await openEntry(hasForms && !manifest.entries[linked].unit ? firstForm : linked, params.get("s"));
const startTab = params.get("tab");
if (startTab && tabs[startTab]) await selectTab(startTab);
requestAnimationFrame(tick);

// Hooks for scripted checks (Playwright).
window.studio = Object.assign(studio, { openEntry, selectSlot, selectTab, setMode, portrait, setFrame: f => { times[mode] = (f + 0.5) / active().fps; playing = false; syncPlay(); } });
