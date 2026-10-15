// The Jobs bar: one Save for every tab's edits (weapon offsets, hand shift, portrait camera, the Edit tab's registry values), Undo, Rebuild (saves
// first), Deploy (saves first, and the server rebuilds first when the registry changed since the last rebuild) and the job log.
// It talks to the project's API (`/viewer/p/<project>/api/`).

export class Jobs {
  // `host` gets the buttons and the note. `studio` holds the API prefix, the saved values and the edits.
  constructor(host, studio) {
    this.studio = studio; this.polling = null;
    host.innerHTML = `<button data-t="save">Save</button><button data-t="undo">Undo</button><button data-t="rebuild">Rebuild</button>
      <button data-t="deploy">Deploy</button><button data-t="log">Log</button><span class="note" data-t="note"></span>`;
    this.q = t => host.querySelector(`[data-t="${t}"]`);
    this.q("save").onclick = () => this.save();
    this.q("undo").onclick = () => studio.undo();
    this.q("rebuild").onclick = () => this.run("rebuild");
    this.q("deploy").onclick = () => this.run("deploy");
    this.q("log").onclick = () => { const log = document.getElementById("log"); log.hidden = !log.hidden; this.q("log").classList.toggle("on", !log.hidden); };
    this.refresh();
  }

  // Whether there is anything to save.
  dirty() { const e = this.studio.edits; return [e.props, e.turns, e.sizes, e.registry].some(map => Object.keys(map).length > 0) || !!e.hand || !!e.camera; }

  note(text) { this.q("note").textContent = text; }

  // Shows the unsaved state.
  refresh() {
    const dirty = this.dirty();
    this.q("save").disabled = this.q("undo").disabled = !dirty;
    this.q("save").classList.toggle("on", dirty);
    if (dirty) this.note("Unsaved edits.");
  }

  async save() {
    const e = this.studio.edits, body = {};
    for (const [edit, name] of [["props", "prop_offsets"], ["turns", "prop_turns"], ["sizes", "prop_sizes"]]) if (Object.keys(e[edit]).length) body[name] = e[edit];
    if (e.hand) body.hand_shift = e.hand;
    if (Object.keys(e.registry).length) body.registry = e.registry;
    if (e.camera) body.camera_head = Object.fromEntries(Object.entries(e.camera).map(([k, v]) => [k, Math.round(v * 1000) / 1000]));
    const r = await fetch(this.studio.api + "tuning", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const answer = await r.json();
    if (!r.ok) { this.note(`Not saved: ${answer.error}`); return false; }
    this.studio.saved(answer);
    this.note("Saved to the registry. Rebuild to bake it into the models.");
    return true;
  }

  // Starts a server job (saving first) and shows its log until it ends.
  async run(job) {
    if (this.dirty() && !(await this.save())) return;
    const r = await fetch(`${this.studio.api}run/${job}`, { method: "POST" });
    const state = await r.json();
    if (!r.ok) { this.note(`A ${state.name} job is still running.`); return; }
    this.note(job === "rebuild" ? "Rebuilding the mod and the gallery..." : "Deploying the test pack, rebuilding first if the registry changed...");
    clearInterval(this.polling);
    this.polling = setInterval(async () => {
      const s = await (await fetch(this.studio.api + "job")).json();
      document.getElementById("log").textContent = s.log.join("\n");
      if (s.running) return;
      clearInterval(this.polling);
      if (!s.ok) { this.note(`The ${s.name} failed. Open Log.`); return; }
      const rebuilt = s.name === "rebuild" || s.ran_first.includes("rebuild");
      if (rebuilt) this.addReload();
      this.note(s.name === "rebuild" ? "Rebuilt." : rebuilt ? "Rebuilt, then deployed. Test it in game." : "Deployed. Test it in game.");
    }, 1000);
  }

  addReload() {
    if (this.q("reload")) return;
    const b = document.createElement("button"); b.dataset.t = "reload"; b.textContent = "Reload"; b.className = "on"; b.onclick = () => location.reload();
    this.q("rebuild").after(b);
  }
}
