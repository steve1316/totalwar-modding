// A searchable list of game models for the Look tab's pickers (a weapon, an outfit, a piece): every model by name with its thumbnail, narrowed by
// the search words. Rows are built a chunk at a time as the list scrolls, under a spacer that keeps the list its full height, and the row under
// the pointer is tried on through `onHover`.
import { stem } from "./live_models.js";

// Rows the list adds at a time: the first ones when it opens, then more as it scrolls near its end.
const LIST_CHUNK = 60;

// Milliseconds a search waits for typing to pause, so thumbnails are only drawn for what is searched in the end.
const TYPING_PAUSE = 300;

// Each model list sorted by name, sorted once. Lists whose thumbnails are being drawn in the background.
const sorted = new WeakMap(), warmed = new WeakSet();

// A model list sorted by name.
function byName(models) {
  if (!sorted.has(models)) sorted.set(models, models.map(p => [stem(p), p]).sort((a, b) => a[0].localeCompare(b[0])).map(([, p]) => p));
  return sorted.get(models);
}

export class ModelList {
  // `models` are the game paths to list, `placeholder` the search box's hint, `featured` an optional promise of {title, models} shown above the
  // search, `onPick(model)` a click and `onHover(model or null)` a resting pointer.
  constructor(thumbs, { models, placeholder, featured, onPick, onHover }) {
    // `searches` counts searches so an older one's first rows are dropped, `typing` is the search's timer.
    this.thumbs = thumbs; this.placeholder = placeholder; this.featured = featured; this.onPick = onPick; this.onHover = onHover;
    this.models = byName(models); this.searches = 0; this.typing = null;
  }

  // One model's row.
  row(p) {
    const { esc } = window.UnitPanel;
    return `<button class="look-hit" data-model="${esc(p)}"><img class="thumb" data-thumb="${esc(p)}" alt="">
      <span><span>${esc(stem(p))}</span><span class="note">${esc(p.split("/").slice(2, -1).join("/"))}</span></span></button>`;
  }

  // Builds the picker box.
  element() {
    const box = document.createElement("div");
    box.className = "picker";
    box.innerHTML = `<div class="look-featured"></div><input class="attrSearch" placeholder="${window.UnitPanel.esc(this.placeholder)}">
      <div class="note look-count"></div><div class="hits look-hits"></div>`;
    const input = box.querySelector("input"), hits = box.querySelector(".hits"), count = box.querySelector(".look-count");
    if (this.featured) this.featured.then(({ title, models }) => {
      const top = box.querySelector(".look-featured");
      if (!models.length) return;
      top.innerHTML = `<div class="note">${window.UnitPanel.esc(title)}</div>` + models.map(p => this.row(p)).join("");
      this.thumbs.fill(top);
    });
    // A spacer below the built rows stands in for the rest, so the list is its full height from the start and the scrollbar keeps still.
    let found = [], shown = 0, spacer = null;
    // Adds the next rows of the found models, then sizes the spacer by the rows' measured height.
    const more = () => {
      const rows = found.slice(shown, shown + LIST_CHUNK), chunk = document.createElement("template");
      shown += rows.length;
      chunk.innerHTML = rows.map(p => this.row(p)).join("");
      this.thumbs.fill(chunk.content);
      spacer.before(chunk.content);
      const step = (spacer.offsetTop - hits.firstElementChild.offsetTop) / shown;
      spacer.style.height = `${Math.max(0, (found.length - shown) * step)}px`;
    };
    // Builds rows until they reach past the bottom of the view, however far it was scrolled or dragged.
    const fillView = () => { while (shown < found.length && spacer.offsetTop - hits.scrollTop < hits.clientHeight + 400) more(); };
    const list = () => {
      // New rows replace the hovered one without a mouseleave.
      this.onHover(null);
      const terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
      found = this.models.filter(p => terms.every(w => p.includes(w))); shown = 0;
      count.textContent = `${found.length} of ${this.models.length} models. Point at one to try it on.`;
      hits.innerHTML = found.length ? '<div class="look-spacer"></div>' : '<div class="note">No model matches.</div>';
      spacer = hits.querySelector(".look-spacer");
      hits.scrollTop = 0;
      // The first rows wait until the list is on the page, where the rows can be measured. A newer search drops the wait.
      const search = ++this.searches;
      setTimeout(() => { if (search === this.searches && spacer) { more(); fillView(); } });
    };
    hits.onscroll = () => { if (spacer) fillView(); };
    // One listener for every row, the featured ones and the ones added later included.
    const row = e => e.target.closest && e.target.closest("[data-model]");
    box.onclick = e => { const b = row(e); if (b) { this.onHover(null); this.onPick(b.dataset.model); } };
    // The try-on stays while the pointer moves between rows, so the stage never flashes back to his own model, and goes when it leaves the picker.
    box.onmouseover = e => { const b = row(e); if (b && !b.contains(e.relatedTarget)) this.onHover(b.dataset.model); };
    box.onmouseleave = () => this.onHover(null);
    input.oninput = () => { clearTimeout(this.typing); this.typing = setTimeout(list, TYPING_PAUSE); };
    // Every model's picture is drawn and kept in the background, so the list shows them at once from then on.
    if (!warmed.has(this.models)) { warmed.add(this.models); this.thumbs.warm(this.models); }
    list(); setTimeout(() => input.focus());
    return box;
  }
}
