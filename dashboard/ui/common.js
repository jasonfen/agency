// Pieces every dashboard page uses: home (app.js), the app catalog
// (apps.js) and settings (settings.js). Loaded before each.

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

// ----------------------------------------------------------------- server

async function api(path, body) {
  const opts = body === undefined
    ? { cache: "no-store" }
    : { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) };
  const r = await fetch(path, opts);
  const data = await r.json().catch(() => ({}));
  if (!r.ok && !data.error) data.error = `The server said ${r.status}.`;
  return data;
}

// Start a job on the server, then redraw (each page has its own refresh).
async function startJob(path, body = {}) {
  showNotice("");
  const result = await api(path, body);
  if (!result.ok) showNotice(result.error || "That did not start.");
  await refresh();
  return result.ok;
}

// ---------------------------------------------------------------- shared

const NAMES = { github: "GitHub", claude: "Claude Code", codex: "Codex", opencode: "OpenCode", t3: "T3 Code" };

const gb = (bytes) => {
  const n = bytes / 1e9;
  return n >= 100 ? n.toFixed(0) : n.toFixed(1).replace(/\.0$/, "");
};

function day(stamp) {
  if (!stamp) return "";
  const then = new Date(stamp * 1000);
  const days = Math.round((new Date().setHours(0, 0, 0, 0) - new Date(then).setHours(0, 0, 0, 0)) / 864e5);
  if (days === 0) return "today";
  if (days === 1) return "yesterday";
  return "on " + then.toLocaleDateString(undefined, { day: "numeric", month: "short" });
}

function ago(stamp) {
  const s = Math.max(0, Date.now() / 1000 - stamp);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.round(s / 3600)} h ago`;
  return day(stamp);
}

// The updates banner. u is null to leave it empty.
function drawUpdates(u, busy) {
  if (!u) return setHTML($("#updates"), "");
  const dis = busy ? "disabled" : "";
  let text;
  let button = "";
  const repo = esc(u.repo || "the agency repo");
  // u.status is the server's: unlinked, behind, error, current or unchecked.
  if (u.status === "unlinked") {
    text = "This machine is not linked to the agency repo yet. Update links it and gets the newest version.";
    button = `<button type="button" class="button button--primary" data-action="update" ${dis}>Update</button>`;
  } else if (u.status === "behind") {
    const list = u.subjects.map((s) => `<li>${esc(s)}</li>`).join("");
    text = `<strong>${u.behind} update${u.behind === 1 ? "" : "s"}</strong> from ${repo}.<ul>${list}</ul>`;
    button = `<button type="button" class="button button--primary" data-action="update" ${dis}>Update</button>`;
  } else if (u.status === "error") {
    text = esc(u.error);
    button = `<button type="button" class="button" data-action="check">Check again</button>`;
  } else if (u.status === "current") {
    text = `Up to date with ${repo}. <span class="muted">Checked ${ago(u.checked)}.</span>`;
    button = `<button type="button" class="button" data-action="check">Check again</button>`;
  } else {
    text = "Not checked for updates yet.";
    button = `<button type="button" class="button" data-action="check">Check now</button>`;
  }
  setHTML($("#updates"), `<div>${text}</div>${button}`);
}

// ----------------------------------------------------------------- pieces

function setHTML(el, html) {
  if (el.dataset.html !== html) {
    el.innerHTML = html;
    el.dataset.html = html;
    return true;
  }
  return false;
}

function showNotice(text) {
  setHTML($("#notice"), text
    ? `<div class="notice"><span>${esc(text)}</span><button type="button" class="button" data-action="notice-close">Close</button></div>`
    : "");
}

// What the server said last, kept in the browser, so a page draws its
// sections at once instead of growing them when the answer comes.
// recall(key) gives it back, or null.
function remember(key, value) {
  try { localStorage.setItem(`agency-${key}`, JSON.stringify(value)); } catch {}
}
function recall(key) {
  try { return JSON.parse(localStorage.getItem(`agency-${key}`)); } catch { return null; }
}

// s.state is left out when drawing from memory: the pill says Loading.
function drawHeader(s) {
  $("#hostname").textContent = s.hostname;
  setHTML($("#who"), `Signed in through Tailscale as <span class="mono">${esc(s.login)}</span>`);
  if (!s.state) return;
  document.title = "agency";
  const pill = $("#pill");
  const labels = { running: "Running", degraded: "Something failed", starting: "Starting", initializing: "Starting", stopping: "Stopping" };
  pill.className = "pill " + (s.state === "running" ? "is-good" : s.state === "degraded" ? "is-bad" : "");
  $("#pill-text").textContent = labels[s.state] || s.state;
  pill.title = s.state === "degraded" ? "A service failed. Over SSH: systemctl --failed" : "";
}

// ----------------------------------------------------------------- the dock

// The bar at the bottom of every page: the running (or just finished) job
// and its log. A job runs on the server, so the bar follows you from page
// to page; the last job seen is kept for the next page to draw at once.
// more.next: what waits after it; more.keep: show the bar even with no job.

const DOCK_KEY = "agency-dock";
let dock = { job: null, logOpen: false, failedSeen: null };
let dockMore = {};
try { Object.assign(dock, JSON.parse(sessionStorage.getItem(DOCK_KEY)) || {}); } catch {}

function drawDock(job, more = {}) {
  const el = $("#dock");
  if (!el) return;
  dockMore = more;
  const running = job?.state === "running";
  if (job?.state === "failed" && job.id !== dock.failedSeen) { dock.failedSeen = job.id; dock.logOpen = true; }
  if (!job) dock.logOpen = false;
  dock.job = job ? { ...job, log: (job.log || []).slice(-300) } : null;
  try { sessionStorage.setItem(DOCK_KEY, JSON.stringify(dock)); } catch {}

  const show = !!(job || more.next || more.keep);
  el.hidden = !show;
  document.body.classList.toggle("has-dock", show);
  if (!show) return setHTML($("#dock-body"), "");

  const lower = (t) => esc(t.replace(/^./, (c) => c.toLowerCase()));
  const lastLine = job?.log?.filter((l) => l.trim()).at(-1) || "";
  let mark = "", title = "Starting the change.", detail = "";
  if (running) {
    mark = "is-running";
    title = esc(job.title);
    detail = lastLine ? `<span class="mono">${esc(lastLine)}</span>` : "Starting.";
  } else if (job?.state === "done") {
    mark = "is-done";
    title = `Done: ${lower(job.done || job.title)}`;
  } else if (job?.state === "failed") {
    mark = "is-failed";
    title = `It failed: ${lower(job.title)}`;
    detail = job.code === null ? "It stopped before it finished." : "The log says why.";
  }
  const then = more.next ? `<p class="dock-next">${running ? "Next" : "Waiting to"}: ${esc(more.next)}</p>` : "";
  const buttons = job ? `<button type="button" class="button" data-action="dock-log">${dock.logOpen ? "Hide the log" : "Show the log"}</button>
    ${running ? "" : `<button type="button" class="button" data-action="job-dismiss">Close</button>`}` : "";
  setHTML($("#dock-body"), `<div class="dock-row">
      <div class="dock-main">
        <span class="job-mark dock-mark ${mark}"></span>
        <div class="dock-text">
          <p class="dock-title">${title}</p>
          ${detail ? `<p class="dock-detail">${detail}</p>` : ""}
          ${then}
        </div>
      </div>
      <div class="buttons">${buttons}</div>
    </div>`);
  el.classList.toggle("is-running", running);
  // Tie the animations to the clock, so a new page picks them up mid-stride.
  const now = performance.timeOrigin + performance.now();
  for (const a of el.getAnimations({ subtree: true })) {
    const d = a.effect?.getTiming().duration;
    if (typeof d === "number" && d > 0) a.currentTime = now % d;
  }

  const log = $("#dock-log");
  log.hidden = !(dock.logOpen && job);
  if (!log.hidden) {
    const atEnd = log.scrollHeight - log.scrollTop - log.clientHeight < 24;
    if (setHTML(log, esc(job.log.join("\n")) || "Starting.") && atEnd) log.scrollTop = log.scrollHeight;
  }
}

document.addEventListener("click", (ev) => {
  if (!ev.target.closest('[data-action="dock-log"]')) return;
  dock.logOpen = !dock.logOpen;
  drawDock(dock.job, dockMore);
});

// Draw the job the last page saw, until the server says otherwise.
if (dock.job) drawDock(dock.job);

// ----------------------------------------------------------------- preload

// The browser renders the other pages ahead, so moving between them is
// instant. Nothing on a page should start for real until it is shown: wrap
// such work in whenShown.
function whenShown(fn) {
  if (document.prerendering) document.addEventListener("prerenderingchange", fn, { once: true });
  else fn();
}
if (HTMLScriptElement.supports?.("speculationrules")) {
  const rules = document.createElement("script");
  rules.type = "speculationrules";
  rules.textContent = JSON.stringify({
    prerender: [{ urls: ["/", "/apps", "/settings"].filter((u) => u !== location.pathname), eagerness: "eager" }],
  });
  document.head.append(rules);
}

// An app's logo, or its initials when it has none.
function appLogo(a) {
  if (a.logo) return `<img class="logo" src="/logos/${esc(a.id)}.svg" alt="">`;
  const initials = a.label.split(/\s+/).map((w) => w[0]).join("").slice(0, 2);
  return `<span class="logo logo--initials" aria-hidden="true">${esc(initials)}</span>`;
}

// ------------------------------------------------------------------- nav

// The nav marks the section in view: the last one whose top has passed a
// line near the top of the window. Sections side by side count as the first.
// Only links to sections of this page count (home and settings).
const links = [...document.querySelectorAll('.nav a[href^="#"]')];
let picked = null; // a section chosen in the nav wins while it is on screen
let pickedSeen = false;
function markNav() {
  let current = links[0];
  let lastTop = null;
  for (const a of links) {
    const top = Math.round(document.getElementById(a.getAttribute("href").slice(1)).getBoundingClientRect().top);
    if (top <= innerHeight * 0.3 && top !== lastTop) current = a;
    lastTop = top;
  }
  if (picked) {
    const r = document.getElementById(picked.getAttribute("href").slice(1)).getBoundingClientRect();
    // Smooth scrolling takes a moment to bring it on screen; it lets go
    // only once it has been seen and then scrolled away from.
    if (r.top < innerHeight && r.bottom > 0) { current = picked; pickedSeen = true; }
    else if (pickedSeen) picked = null;
    else current = picked;
  }
  for (const a of links) a.classList.toggle("is-current", a === current);
}
let navQueued = false;
addEventListener("scroll", () => {
  if (navQueued) return;
  navQueued = true;
  requestAnimationFrame(() => { navQueued = false; markNav(); });
}, { passive: true });
if (links.length) markNav();
for (const a of links) a.addEventListener("click", () => { picked = a; pickedSeen = false; markNav(); });
// Scrolling by hand lets go of the pick, even mid-flight.
for (const ev of ["wheel", "touchmove", "keydown"]) addEventListener(ev, () => { picked = null; }, { passive: true });
