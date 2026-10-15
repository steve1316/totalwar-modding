// The workbench's tab strip and project picker, added to the top of every tab's page. A page loads it with
// <script src="/static/nav.js" defer></script>, keeps its own content below the strip's height (`--nav-h`), and reads the open project's key from
// `await window.workbenchProject`. The project comes from the page's `?p=` query, else the last one picked, else the first project.
(function () {
  const PROJECT_KEY = "workbench-project";
  const style = document.createElement("style");
  style.textContent = `:root { --nav-h: 38px; }
    .wb-nav { position: fixed; top: 0; left: 0; right: 0; height: calc(var(--nav-h) + env(safe-area-inset-top, 0px)); z-index: 50; display: flex; gap: 2px;
      align-items: flex-end; padding: env(safe-area-inset-top, 0px) 8px 0; background: linear-gradient(#2a1d17, #120c0b); border-bottom: 1px solid #6b5233;
      font: 15px "Libre Caslon Text", Georgia, serif; overflow-x: auto; }
    .wb-nav a { color: #a8998a; text-decoration: none; padding: 7px 14px; border: 1px solid transparent; border-bottom: 0; border-radius: 4px 4px 0 0;
      white-space: nowrap; }
    .wb-nav a.on { color: #e9dfcf; background: linear-gradient(#5f1210, #3c0909); border-color: #a8302a; }
    .wb-nav select { margin: 0 0 4px auto; min-height: 28px; font: inherit; font-size: 13px; color: #e9dfcf; background: linear-gradient(#5b1714, #360b0a);
      border: 1px solid #a8442f; border-radius: 3px; padding: 0 6px; }`;
  document.head.append(style);

  function read() { try { return localStorage.getItem(PROJECT_KEY); } catch (e) { return null; } }
  function write(key) { try { localStorage.setItem(PROJECT_KEY, key); } catch (e) { /* storage blocked */ } }

  window.workbenchProject = (async () => {
    const nav = await (await fetch("/api/nav")).json();
    const keys = nav.projects.map(p => p.key);
    let key = new URLSearchParams(location.search).get("p") || read();
    if (!keys.includes(key)) key = keys[0] || "";
    write(key);
    const bar = document.createElement("nav");
    bar.className = "wb-nav";
    const here = location.pathname.replace(/index\.html$/, "");
    bar.innerHTML = nav.tabs.map(t => `<a href="${t.href}" class="${here === t.href ? "on" : ""}">${t.label}</a>`).join("")
      + (keys.length ? `<select aria-label="Project">${nav.projects.map(p => `<option value="${p.key}"${p.key === key ? " selected" : ""}>${p.name}</option>`).join("")}</select>` : "");
    const picker = bar.querySelector("select");
    if (picker) picker.onchange = () => { write(picker.value); const url = new URL(location.href); url.searchParams.set("p", picker.value); location.href = url.toString(); };
    document.body.prepend(bar);
    return key;
  })();
})();
