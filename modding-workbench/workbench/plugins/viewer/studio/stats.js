// The Stats inspector tab: the in-game unit panel of the open form (`manifest.panels`, built by the project's generator with `ttc.unit_panel`),
// with its vanilla equivalent drawn into the bars. "Show vanilla" swaps which unit the panel is about.

// Attribute chips: red for what only the panel's unit has, green for what only the compared unit has.
function attributeChips(u, o) {
  const { esc } = window.UnitPanel;
  const mine = new Set(u.attributes.map(a => a.key)), theirs = new Set(o.attributes.map(a => a.key));
  const chip = (a, cls) => `<span class="${cls}" title="${esc(a.text)}">${esc(a.name)}</span>`;
  const list = u.attributes.map(a => chip(a, theirs.has(a.key) ? "" : "down")).concat(o.attributes.filter(a => !mine.has(a.key)).map(a => chip(a, "up")));
  return list.length ? list.join("") : "<span>None</span>";
}

export class StatsTab {
  constructor(studio) { this.studio = studio; this.flip = false; }

  // Whether the open entry has panels to show.
  available(entry) { return !!(entry && entry.unit && entry.versus && this.studio.manifest.panels); }

  render(container) {
    const entry = this.studio.stage.entry;
    if (!this.available(entry)) { container.innerHTML = '<div class="note">No unit panel for this entry. Pick an Advisor form.</div>'; return; }
    const { esc, cardHtml, hpHtml, statsHtml, abilitiesHtml } = window.UnitPanel;
    const panels = this.studio.manifest.panels, art = this.studio.panelArt;
    const [u, o] = this.flip ? [panels[entry.versus], panels[entry.unit]] : [panels[entry.unit], panels[entry.versus]];
    container.innerHTML = `<div class="panel"><div class="p-title">${esc(u.name)}</div>
      <div class="vs">Compared with <b>${esc(o.name)}</b><button data-t="flip">${this.flip ? "Show the Advisor" : "Show vanilla"}</button></div>
      <div class="p-sub"><span>${esc(u.caste)} · ${esc(u.class)}${u.stats.tier ? ` · tier ${u.stats.tier}` : ""}</span></div>
      <div class="p-top">${cardHtml(u, art)}<div><div class="meta">${esc(u.key)}</div>${hpHtml(u, o, art)}</div></div>
      <div class="p-head">Stats</div>${statsHtml(u.stats, o.stats, art)}
      <div class="p-head">Abilities</div><div class="abilities">${abilitiesHtml(u.abilities, art)}</div>
      <div class="vs">${esc(o.name)}</div><div class="abilities">${abilitiesHtml(o.abilities, art)}</div>
      <div class="p-head">Attributes</div><div class="chips">${attributeChips(u, o)}</div></div>`;
    container.querySelector('[data-t="flip"]').onclick = () => { this.flip = !this.flip; this.render(container); };
  }
}
