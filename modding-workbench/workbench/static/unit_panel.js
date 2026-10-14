// The in-game unit panel shared by the dashboard's tabs (see unit_panel.css). A panel's numbers come from `ttc.unit_panel` on the server: `stats`
// holds the panel rows by key, `hp_estimate` marks HP that adds a mount or engine, and `abilities` is a list of {key, name, icon}. Every builder
// takes an optional compared unit's stats, drawn into the bars and shown as a second number. `art` turns a pack-relative path into a URL.
(function () {
  // Unit panel rows in the in-game order, with each stat's icon and the value a full bar stands for. The missile rows only show for units that shoot.
  const STATS = [["armour", "Armour", "icon_stat_armour", 200], ["leadership", "Leadership", "icon_stat_morale", 100], ["speed", "Speed", "icon_stat_speed", 120],
    ["melee_attack", "Melee Attack", "icon_stat_attack", 120], ["melee_defence", "Melee Defence", "icon_stat_defence", 120],
    ["weapon_strength", "Weapon Strength", "icon_stat_damage", 800], ["charge_bonus", "Charge Bonus", "icon_stat_charge_bonus", 150],
    ["ammunition", "Ammunition", "icon_stat_ammo", 50], ["range", "Range", "icon_stat_range", 200], ["missile_strength", "Missile Strength", "icon_stat_ranged_damage", 150]];
  // The game skin files the panel draws, for servers that extract them.
  const SKIN_FILES = ["icon_stat_health_noframe", "icon_entity_small", ...STATS.map(s => s[2])];

  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}[c]));
  const skin = (art, name) => art(`ui/skins/default/${name}.png`);

  // The bar keeps the panel's value in gold up to the smaller of the two. When the compared unit is lower, the part it lacks turns red. When it is
  // higher, the bar runs on past in green.
  function barHtml(value, other, max, cls = "bar") {
    const pct = v => Math.min(100, Math.max(0, v / max * 100));
    if (other === undefined || other === value) return `<span class="${cls}"><span class="fill" style="width:${pct(value)}%"></span></span>`;
    const low = pct(Math.min(value, other)), high = pct(Math.max(value, other));
    return `<span class="${cls}"><span class="fill" style="width:${low}%"></span><span class="${other < value ? "loss" : "gain"}" style="left:${low}%;width:${high - low}%"></span></span>`;
  }
  function cmpHtml(value, other) {
    if (other === undefined) return '<span class="cmp"></span>';
    return `<span class="cmp ${other > value ? "up" : other < value ? "down" : ""}">${other}</span>`;
  }
  // The stat rows. `o` is the compared unit's stats, or an empty object.
  function statsHtml(s, o, art) {
    return STATS.filter(([k]) => s[k] !== undefined || o[k] !== undefined).map(([k, name, img, max]) => {
      const v = s[k] ?? 0;
      return `<div class="stat"><img src="${skin(art, img)}" alt=""><span>${name}</span><span class="v">${v}</span>${cmpHtml(v, o[k])}${barHtml(v, o[k], max)}</div>`;
    }).join("");
  }
  // The health bar and the men count. HP has no fixed maximum, so its bar is scaled to the larger of the two units.
  function hpHtml(u, other, art) {
    const s = u.stats, o = other ? other.stats : {}, max = Math.max(s.hp, o.hp || 0, 1);
    return `<div class="hp"><div class="hp-bar">${barHtml(s.hp, o.hp, max, "hp-fill")}<b><img src="${skin(art, "icon_stat_health_noframe")}" alt="">${u.hp_estimate ? "~" : ""}${s.hp}${other ? cmpHtml(s.hp, o.hp) : ""}</b></div></div>
      <div class="men"><img src="${skin(art, "icon_entity_small")}" alt="">${s.men}${other ? cmpHtml(s.men, o.men) : ""}</div>`;
  }
  function abilitiesHtml(list, art) {
    return list.length ? list.map(a => a.icon ? `<img loading="lazy" src="${art(a.icon)}" title="${esc(a.name)}" alt="${esc(a.name)}">`
      : `<span class="noicon" title="${esc(a.key)}">${esc(a.name)}</span>`).join("") : '<span class="none">No abilities</span>';
  }
  // The card art, or an empty frame.
  function cardHtml(u, art) {
    return u.card ? `<img class="art" src="${art(u.card)}" alt="">` : '<div class="art"></div>';
  }

  window.UnitPanel = { STATS, SKIN_FILES, esc, barHtml, cmpHtml, statsHtml, hpHtml, abilitiesHtml, cardHtml };
})();
