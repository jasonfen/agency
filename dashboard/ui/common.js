// Pieces both dashboard pages use: the home page (app.js) and the app
// catalog (apps.js). Loaded before either.

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
  document.title = `${s.hostname} - agency`;
  const pill = $("#pill");
  const labels = { running: "Running", degraded: "Something failed", starting: "Starting", initializing: "Starting", stopping: "Stopping" };
  pill.className = "pill " + (s.state === "running" ? "is-good" : s.state === "degraded" ? "is-bad" : "");
  $("#pill-text").textContent = labels[s.state] || s.state;
  pill.title = s.state === "degraded" ? "A service failed. Over SSH: systemctl --failed" : "";
  setHTML($("#who"), `Signed in through Tailscale as <span class="mono">${esc(s.login)}</span>`);
}

function drawJob(job) {
  if (!job) return setHTML($("#job"), "");
  const results = {
    running: "Running. This page stays up to date.",
    done: "Done.",
    failed: job.code === null ? "It stopped before it finished." : "It failed. The log says why.",
  };
  const html = `<div class="job is-${job.state}">
    <div class="job-head">
      <p class="job-title"><span class="job-mark"></span>${esc(job.title)} <span class="job-result">${results[job.state]}</span></p>
      ${job.state === "running" ? "" : `<button type="button" class="button" data-action="job-dismiss">Close</button>`}
    </div>
    <pre class="log" id="log">${esc(job.log.join("\n")) || "Starting."}</pre>
  </div>`;
  const log = $("#log");
  const atEnd = !log || log.scrollHeight - log.scrollTop - log.clientHeight < 24;
  if (setHTML($("#job"), html) && atEnd) $("#log").scrollTop = $("#log").scrollHeight;
}

// An app's logo, or its initials when it has none.
function appLogo(a) {
  if (a.logo) return `<img class="logo" src="/logos/${esc(a.id)}.svg" alt="">`;
  const initials = a.label.split(/\s+/).map((w) => w[0]).join("").slice(0, 2);
  return `<span class="logo logo--initials" aria-hidden="true">${esc(initials)}</span>`;
}

