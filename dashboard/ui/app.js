// agency dashboard. Plain JavaScript; the server is dashboard/server.py.
//
// The page asks for /api/state every few seconds and draws each section
// from it: desktops, the terminal and the apps that are on. Accounts,
// secrets and the system are in Settings (settings.js). Changes start a job
// on the server; while one runs, the others wait and it shows in the bar at
// the bottom (common.js).

let state = null;
let appList = null;
let jobRunning = false;
let appsAfterJob = null;
const shots = {}; // desktop number -> object URL of its newest picture

// ----------------------------------------------------------------- pieces

const dis = () => (jobRunning ? "disabled" : "");

// --------------------------------------------------------------- sections

function drawDesktops(list) {
  const host = location.hostname;
  const last = list.length;
  const html = list.map((d) => {
    const detail = !d.running ? "Stopped"
      : d.windows === null ? "Running"
      : d.windows === 0 ? "No windows open"
      : `${d.windows} window${d.windows === 1 ? "" : "s"} open`;
    const remove = d.n === last && d.n > 1
      ? `<button type="button" class="button button--danger" data-action="desktop-remove" ${dis()}>Remove</button>` : "";
    return `<article class="card">
      <div class="shot" data-shot="${d.n}">${d.running ? `<img alt="What desktop :${d.n} shows" hidden>` : "Stopped"}</div>
      <div class="card-foot">
        <div><p class="card-name">Desktop :${d.n}</p><p class="card-detail">${detail}</p></div>
        <div class="buttons">${remove}
          <a class="button button--solid" href="${location.protocol}//${esc(host)}:${d.port}/" target="_blank" rel="noopener">Open</a>
        </div>
      </div>
    </article>`;
  }).join("");
  if (setHTML($("#desktop-list"), html)) {
    for (const img of document.querySelectorAll("[data-shot] img")) {
      const n = img.parentElement.dataset.shot;
      if (shots[n]) showShot(img, shots[n]);
    }
  }
}

// The home page lists the apps that are on; the catalog (/apps) has the rest.
function drawApps() {
  if (!appList) return;
  if (appList.error) {
    setHTML($("#app-list"), `<p class="row muted">The list did not load: ${esc(appList.error)}</p>`);
    return;
  }
  // A compact grid of names, so a long list stays short. Past a dozen,
  // the rest is a link to the catalog, which has them all.
  const on = appList.apps.filter((a) => a.on);
  if (!on.length) {
    setHTML($("#app-list"), `<p class="row muted">No apps yet.</p>`);
    return;
  }
  const max = on.length > 12 ? 11 : 12;
  const more = on.length - max;
  setHTML($("#app-list"), `<div class="app-grid">${on.slice(0, max).map((a) => `<div class="app-tile" title="${esc(a.label)}, ${esc(a.group)}">
      ${appLogo(a)}<span>${esc(a.label)}</span>
    </div>`).join("")}${more > 0 ? `<a class="app-tile app-more" href="/apps">${more} more</a>` : ""}</div>`);
}

function draw(s) {
  state = s;
  const wasRunning = jobRunning;
  jobRunning = !!(s.job && s.job.state === "running");
  drawHeader(s);
  drawDock(s.job);
  // Here only when there is something to do; Settings has the rest.
  drawUpdates(["behind", "unlinked"].includes(s.updates.status) ? s.updates : null, jobRunning);
  drawDesktops(s.desktops);
  drawApps();
  for (const b of document.querySelectorAll("[data-job]")) b.disabled = jobRunning;
  // A job ended: the app list may have changed.
  if (s.job && !jobRunning && s.job.id !== appsAfterJob) {
    appsAfterJob = s.job.id;
    if (wasRunning) loadApps();
  }
}

// ---------------------------------------------------------------- polling

let timer = null;

async function refresh() {
  clearTimeout(timer);
  try {
    const s = await api("/api/state");
    if (s.error) showNotice(s.error);
    else draw(s);
  } catch {
    // The dashboard restarts during some rebuilds. Try again shortly.
  }
  timer = setTimeout(refresh, jobRunning ? 1500 : 6000);
}

async function loadApps() {
  try {
    appList = await api("/api/apps");
  } catch {
    appList = { apps: [], error: "the server did not answer" };
  }
  drawApps();
}

// Desktop pictures: a new one every few seconds while the section is on screen.
let desktopsVisible = false;
new IntersectionObserver((entries) => {
  desktopsVisible = entries.some((e) => e.isIntersecting);
}).observe($("#desktops"));

function showShot(img, url) {
  img.onload = () => { img.hidden = false; };
  img.onerror = () => { img.hidden = true; };
  img.src = url;
}

async function refreshShots() {
  if (desktopsVisible && !document.hidden && state) {
    for (const d of state.desktops.filter((x) => x.running)) {
      try {
        const r = await fetch(`/api/desktops/${d.n}/shot`, { cache: "no-store" });
        if (!r.ok) continue;
        const url = URL.createObjectURL(await r.blob());
        if (shots[d.n]) URL.revokeObjectURL(shots[d.n]);
        shots[d.n] = url;
        const img = document.querySelector(`[data-shot="${d.n}"] img`);
        if (img) showShot(img, url);
      } catch {
        // Skip this round.
      }
    }
  }
  setTimeout(refreshShots, 4000);
}

// The terminal starts a shell, so load it only once it is near the screen.
function openTerminal(src) {
  const frame = $("#term");
  if (frame.getAttribute("src") !== src) frame.src = src;
}
// In tmux, xterm.js turns the wheel into arrow keys, which walk the shell's
// history. Keep the wheel from xterm.js; with nothing to scroll in the
// frame, the browser scrolls this page, at its usual speed. The frame is
// same-origin.
$("#term").addEventListener("load", (ev) => {
  let win;
  try { win = ev.target.contentWindow; win.document; } catch { return; }
  win.addEventListener("wheel", (e) => e.stopImmediatePropagation(), { capture: true, passive: true });
});
whenShown(() => new IntersectionObserver((entries, obs) => {
  if (entries.some((e) => e.isIntersecting)) {
    if (!$("#term").getAttribute("src")) openTerminal("/terminal/");
    obs.disconnect();
  }
}, { rootMargin: "200px" }).observe($("#terminal")));

// ---------------------------------------------------------------- actions

// Sign-ins that run in the terminal come here from Settings: /?signin=<tool>.
function signInHere(tool) {
  openTerminal(`/terminal/?arg=${encodeURIComponent(tool)}`);
  $("#term-note").innerHTML = `Signing in to ${esc(NAMES[tool] || tool)}. Follow the steps in the terminal. <button type="button" class="button" data-action="term-shell">Back to the shell</button>`;
  $("#terminal").scrollIntoView();
}

document.addEventListener("click", async (ev) => {
  const t = ev.target.closest("button");
  if (!t) return;
  const action = t.dataset.action;

  switch (action) {
    case "update":
      return startJob("/api/update");
    case "desktop-add":
      return startJob("/api/desktops/add");
    case "desktop-remove":
      if (!confirm(`Remove desktop :${state.desktops.length}? Apps open on it close.`)) return;
      return startJob("/api/desktops/remove");
    case "job-dismiss":
      await api("/api/job/dismiss", {});
      return refresh();
    case "notice-close":
      return showNotice("");
    case "term-shell":
      openTerminal("/terminal/");
      $("#term-note").textContent = "A shell on the machine, in your browser. Start an agent here, or attach to your tmux sessions.";
      return;
  }
});

refresh();
loadApps();
whenShown(refreshShots);
const signin = new URLSearchParams(location.search).get("signin");
if (signin) {
  history.replaceState(null, "", "/#terminal");
  whenShown(() => signInHere(signin));
}
