// The in-game unit panel shared by the dashboard's tabs (see unit_panel.css). A panel's numbers come from `ttc.unit_panel` on the server: `stats`
// holds the panel rows by key, `hp_estimate` marks HP that adds a mount or engine, and `abilities` is a list of {key, name, icon}. Every builder
// takes an optional compared unit's stats, drawn into the bars and shown as a second number. `art` turns a pack-relative path into a URL.
// An ability with a `tip` (from `ttc.unit_panel.ability_tooltip`) and an attribute with a `text` get the game's tooltip, on hover or on tap.
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
  // Loc text as HTML: inline images (`[[img:...]]`, a bare name being a skin icon), colour tags dropped, line breaks kept.
  function markupHtml(text, art) {
    // An image tag may wrap the words it stands next to: [[img:icon]]Melee Attack[[/img]].
    return esc(text || "").replace(/\[\[img:([^\]]+)\]\]([^\[]*)\[\[\/img\]\]/g, (_, name, words) => {
      const path = name.includes("/") ? name.toLowerCase() : `ui/skins/default/${name.toLowerCase()}.png`;
      return `<img class="inl" src="${art(path)}" alt="" onerror="this.remove()">${words}`;
    }).replace(/\[\[(\/?)(b|i)\]\]/g, "<$1$2>").replace(/\[\[\/?col[^\]]*\]\]/g, "").replace(/\\+n/g, "<br>");
  }

  // Tooltip HTML by id, filled as panels are drawn. The same tooltip keeps its id (`tipIds`), so redrawing panels adds nothing.
  const tips = new Map(), tipIds = new Map();
  function tipAttr(html) {
    if (!tipIds.has(html)) { const id = `tip${tipIds.size}`; tipIds.set(html, id); tips.set(id, html); }
    return `data-tip="${tipIds.get(html)}" tabindex="0"`;
  }

  // An ability's tooltip, laid out like the game's: icon and name, type, passive, numbers, phases with their effects, description.
  function abilityTipHtml(a, art) {
    const t = a.tip;
    if (!t) return `<div class="tip-head"><b>${esc(a.name)}</b></div>`;
    const phases = t.phases.map(p => `<div class="tip-phase">${p.name || p.duration ? `<div class="tip-sub">${markupHtml(p.name, art)}${p.duration ? ` <span>${p.duration}</span>` : ""}</div>` : ""}
      ${p.effects.map(([label, value]) => `<div class="tip-row"><span>${markupHtml(label, art)}</span><b class="${value.startsWith("-") ? "down" : "up"}">${esc(value)}</b></div>`).join("")}
      ${p.attributes.map(([name, good]) => `<div class="tip-row"><span>${esc(name)}</span><b class="${good ? "up" : "down"}">${good ? "gained" : "lost"}</b></div>`).join("")}</div>`).join("");
    return `<div class="tip-head">${a.icon ? `<img src="${art(a.icon)}" alt="">` : ""}<div><b>${esc(t.name)}</b><div class="tip-type">${markupHtml(t.type, art)}${t.passive ? " · Passive" : ""}</div></div></div>
      ${t.numbers.length ? `<div class="tip-nums">${t.numbers.map(([label, value]) => `<span>${esc(label)} <b>${esc(value)}</b></span>`).join("")}</div>` : ""}
      ${phases}${t.text ? `<div class="tip-text">${markupHtml(t.text, art)}</div>` : ""}`;
  }
  function abilitiesHtml(list, art) {
    return list.length ? list.map(a => a.icon ? `<img loading="lazy" src="${art(a.icon)}" alt="${esc(a.name)}" ${tipAttr(abilityTipHtml(a, art))}>`
      : `<span class="noicon" ${tipAttr(abilityTipHtml(a, art))}>${esc(a.name)}</span>`).join("") : '<span class="none">No abilities</span>';
  }
  // An attribute chip with its icon and tooltip. `cls` marks it against a compared unit.
  function attributeHtml(a, art, cls = "") {
    const icon = a.icon ? `<img loading="lazy" src="${art(a.icon)}" alt="">` : "";
    return `<span class="${cls}" ${tipAttr(`<div class="tip-head">${icon}<div><b>${esc(a.name)}</b><div class="tip-type">Attribute</div></div></div>
      ${a.text ? `<div class="tip-text">${markupHtml(a.text, art)}</div>` : ""}`)}>${icon}${esc(a.name)}</span>`;
  }

  // One floating tooltip for the page: it follows the hovered or tapped element and stays inside the window.
  function installTips() {
    const box = document.createElement("div"); box.className = "up-tip"; box.hidden = true; document.body.append(box);
    let owner = null;
    const show = el => {
      const html = tips.get(el.dataset.tip); if (!html) return;
      owner = el; box.innerHTML = html; box.hidden = false;
      const r = el.getBoundingClientRect(), w = box.offsetWidth, h = box.offsetHeight;
      const left = Math.min(Math.max(8, r.left + r.width / 2 - w / 2), innerWidth - w - 8);
      const top = r.top - h - 8 > 8 ? r.top - h - 8 : Math.min(r.bottom + 8, innerHeight - h - 8);
      box.style.left = left + "px"; box.style.top = top + "px";
    };
    const hide = () => { owner = null; box.hidden = true; };
    document.addEventListener("mouseover", e => { const el = e.target.closest("[data-tip]"); if (el && el !== owner) show(el); else if (!el && owner) hide(); });
    document.addEventListener("click", e => { const el = e.target.closest("[data-tip]"); if (!el) { hide(); return; } owner === el ? hide() : show(el); });
    // A scroll moves the tooltip with its element, and closes it once the element leaves the window.
    document.addEventListener("scroll", () => {
      if (!owner) return;
      const r = owner.getBoundingClientRect();
      if (r.bottom < 0 || r.top > innerHeight) hide(); else show(owner);
    }, true);
  }
  if (document.body) installTips(); else document.addEventListener("DOMContentLoaded", installTips);
  // The card art, or an empty frame.
  function cardHtml(u, art) {
    return u.card ? `<img class="art" src="${art(u.card)}" alt="">` : '<div class="art"></div>';
  }

  window.UnitPanel = { STATS, SKIN_FILES, esc, markupHtml, barHtml, cmpHtml, statsHtml, hpHtml, abilitiesHtml, attributeHtml, cardHtml };
})();
