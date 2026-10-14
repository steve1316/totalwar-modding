// The dashboard's tab strip, added to the top of every tab's page. A page loads it with <script src="/shared/nav.js"></script> and keeps its own
// content below the strip's height (`--nav-h`).
(function () {
  const TABS = [["Workbench", "/workbench/"], ["Portrait", "/workbench/portrait.html"], ["Unit Browser", "/browser/"]];
  const style = document.createElement("style");
  style.textContent = `:root { --nav-h: 38px; }
    .dash-nav { position: fixed; top: 0; left: 0; right: 0; height: calc(var(--nav-h) + env(safe-area-inset-top, 0px)); z-index: 50; display: flex; gap: 2px;
      align-items: flex-end; padding: env(safe-area-inset-top, 0px) 8px 0; background: linear-gradient(#2a1d17, #120c0b); border-bottom: 1px solid #6b5233;
      font: 15px "Libre Caslon Text", Georgia, serif; overflow-x: auto; }
    .dash-nav a { color: #a8998a; text-decoration: none; padding: 7px 14px; border: 1px solid transparent; border-bottom: 0; border-radius: 4px 4px 0 0;
      white-space: nowrap; }
    .dash-nav a.on { color: #e9dfcf; background: linear-gradient(#5f1210, #3c0909); border-color: #a8302a; }`;
  document.head.append(style);
  const nav = document.createElement("nav");
  nav.className = "dash-nav";
  const here = location.pathname.replace(/index\.html$/, "");
  nav.innerHTML = TABS.map(([name, href]) => `<a href="${href}" class="${here === href ? "on" : ""}">${name}</a>`).join("");
  document.body.prepend(nav);
})();
