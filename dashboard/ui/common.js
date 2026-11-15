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

function drawHeader(s) {
  $("#hostname").textContent = s.hostname;
  document.title = "agency";
  const pill = $("#pill");
  const labels = { running: "Running", degraded: "Something failed", starting: "Starting", initializing: "Starting", stopping: "Stopping" };
  pill.className = "pill " + (s.state === "running" ? "is-good" : s.state === "degraded" ? "is-bad" : "");
  $("#pill-text").textContent = labels[s.state] || s.state;
  pill.title = s.state === "degraded" ? "A service failed. Over SSH: systemctl --failed" : "";
  setHTML($("#who"), `Signed in through Tailscale as <span class="mono">${esc(s.login)}</span>`);
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
    title = `Done: ${lower(job.title)}`;
  } else if (job?.state === "failed") {
    mark = "is-failed";
    title = `It failed: ${lower(job.title)}`;
    detail = job.code === null ? "It stopped before it finished." : "The log says why.";
  }
  const then = more.next ? `<p class="dock-next">${running ? "Next" : "Waiting to"}: ${esc(more.next)}</p>` : "";
  const buttons = job ? `<button type="button" class="button" data-action="dock-log">${dock.logOpen ? "Hide the log" : "Show the log"}</button>
    ${running ? "" : `<button type="button" class="button" data-action="job-dismiss">Close</button>`}` : "";
  setHTML($("#dock-body"), `<div class="dock-row">
      <span class="job-mark dock-mark ${mark}"></span>
      <div class="dock-text">
        <p class="dock-title">${title}</p>
        ${detail ? `<p class="dock-detail">${detail}</p>` : ""}
        ${then}
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

