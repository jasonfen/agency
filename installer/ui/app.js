// agency setup: the screens.
//
// One page, no framework. `state` holds every answer, each screen is a
// function that returns { html, actions, enter }, and show() draws it.
// All real work happens in installer/server.py, reached through api().

const STEPS = [
  ["network", "Network"],
  ["access", "Who can log in"],
  ["disk", "Disk"],
  ["tailscale", "Tailscale"],
  ["apps", "Apps"],
  ["review", "Review"],
];

const state = {
  info: null,
  screen: "welcome",
  online: null,
  wifi: null,
  wifiError: "",
  user: "",
  keyCount: 0,
  accessError: "",
  disks: [],
  earlier: "",
  disk: "",
  tailscale: { state: "idle" },
  apps: new Set(),
  install: null,
  busy: false,
};

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const icon = (id, cls = "") => `<svg class="${cls}" aria-hidden="true"><use href="#${id}"/></svg>`;

async function api(path, body) {
  const res = await fetch("/api/" + path, body === undefined ? {} : {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return res.json();
}

let timer = null;
function every(ms, fn) {
  clearInterval(timer);
  timer = setInterval(fn, ms);
}

// ------------------------------------------------------------- screens ---

const screens = {
  welcome() {
    const { uefi, tpm } = state.info;
    if (!uefi || !tpm) {
      const what = !uefi
        ? "This computer started in legacy mode. In the BIOS, turn off legacy or CSM boot so it starts in UEFI mode."
        : "No TPM 2.0 chip was found. In the BIOS, turn it on. It is often called Security Device Support, Intel PTT or AMD fTPM.";
      return {
        html: `<h1>One setting to change first</h1>
          <p class="lede">${what}</p>
          <p>Then start from the USB stick again. Nothing on this computer has been changed.</p>`,
        actions: [{ label: "Power off", primary: true, run: () => api("poweroff", {}) }],
      };
    }
    return {
      html: `<h1>A computer for your agents</h1>
        <p class="lede">agency turns this computer into one that AI agents run. They get full control of it and a desktop of their own, and you check in from your laptop or phone.</p>
        <p>Setup takes about ten minutes. Installing erases one disk. You choose which, and nothing is changed until you confirm on the last screen.</p>
        ${icon("pointer", "hero")}`,
      actions: [{ label: "Begin", primary: true, run: () => show("network") }],
    };
  },

  network() {
    let body;
    if (state.online === null) {
      body = `<p class="muted">Checking the connection.</p>`;
    } else if (state.online) {
      body = `<div class="notice notice--good"><strong>Connected to the internet.</strong></div>`;
    } else {
      const list = state.wifi === null
        ? `<p class="muted">Looking for Wi-Fi networks.</p>`
        : state.wifi.length === 0
          ? `<p class="muted">No Wi-Fi networks found. Plug in a network cable.</p>`
          : `<div class="choices" role="radiogroup" aria-label="Wi-Fi networks">${state.wifi.map((n, i) => `
              <label class="choice">
                <input type="radio" name="ssid" value="${esc(n.ssid)}" ${i === 0 ? "checked" : ""}>
                ${icon("pointer", "mark")}
                <span class="name">${esc(n.ssid)}</span>
                <span class="aside">${n.secure ? "password" : "open"}</span>
              </label>`).join("")}</div>
            <div class="field">
              <label for="wifi-pass">Wi-Fi password</label>
              <input class="input" id="wifi-pass" type="password" autocomplete="off">
            </div>
            <p style="margin-top: var(--s2)"><button class="button" id="wifi-join">Join network</button></p>`;
      body = `<p>No connection yet. Plug in a network cable, or join Wi-Fi.</p>
        ${state.wifiError ? `<div class="notice notice--bad">${esc(state.wifiError)}</div>` : ""}
        <h2>Wi-Fi</h2>${list}`;
    }
    return {
      html: `<h1>Network</h1>
        <p class="lede">The installer needs the internet to fetch your login keys.</p>${body}`,
      actions: [
        { label: "Back", run: () => show("welcome") },
        { label: "Continue", primary: true, disabled: !state.online, run: () => show("access") },
      ],
      enter() {
        const check = async () => {
          const was = state.online;
          state.online = (await api("online")).online;
          if (!state.online && state.wifi === null) state.wifi = (await api("wifi")).networks;
          if (was !== state.online || state.wifi !== null && was === null) redraw();
        };
        check();
        every(4000, check);
      },
      bind() {
        const join = $("#wifi-join");
        if (join) join.onclick = async () => {
          const ssid = document.querySelector("input[name=ssid]:checked").value;
          join.disabled = true;
          join.textContent = "Joining";
          const res = await api("wifi", { ssid, password: $("#wifi-pass").value });
          state.wifiError = res.ok ? "" : res.error;
          if (res.ok) state.online = (await api("online")).online;
          redraw();
        };
      },
    };
  },

  access() {
    return {
      html: `<h1>Who can log in</h1>
        <p class="lede">You log in over SSH with the keys already on your GitHub account, so there is no password to set.</p>
        <div class="field">
          <label for="gh-user">GitHub username</label>
          <input class="input" id="gh-user" value="${esc(state.user)}" autocomplete="off" autocapitalize="off" spellcheck="false">
        </div>
        ${state.accessError ? `<div class="notice notice--bad">${esc(state.accessError)}</div>` : ""}`,
      actions: [
        { label: "Back", run: () => show("network") },
        {
          label: state.busy ? "Checking" : "Continue", primary: true, disabled: state.busy,
          async run() {
            state.user = $("#gh-user").value.trim();
            state.busy = true;
            redraw();
            const res = await api("keys", { user: state.user });
            state.busy = false;
            state.accessError = res.ok ? "" : res.error;
            state.keyCount = res.count || 0;
            res.ok ? show("disk") : redraw();
          },
        },
      ],
      focus: "#gh-user",
    };
  },

  disk() {
    const rows = state.disks.map((d) => `
      <label class="choice">
        <input type="radio" name="disk" value="${esc(d.path)}" ${d.path === state.disk ? "checked" : ""}>
        ${icon("pointer", "mark")}
        <span><span class="name">${esc(d.model)}</span><br><span class="detail">${esc(d.size)}, ${esc(d.kind)}</span></span>
        <span class="aside">${esc(d.path)}</span>
      </label>`).join("");
    return {
      html: `<h1>Disk</h1>
        <p class="lede">Choose the disk to install on. Everything on it will be erased when you confirm on the last screen.</p>
        ${state.disks.length
          ? `<div class="choices" role="radiogroup" aria-label="Disks">${rows}</div>`
          : `<div class="notice notice--bad">No internal disk was found.</div>`}`,
      actions: [
        { label: "Back", run: () => show("access") },
        { label: "Continue", primary: true, disabled: !state.disk, run: () => show("tailscale") },
      ],
      async enter() {
        const res = await api("disks");
        state.disks = res.disks;
        state.earlier = res.earlier;
        if (!state.disks.some((d) => d.path === state.disk)) state.disk = state.disks[0]?.path || "";
        redraw();
      },
      bind() {
        document.querySelectorAll("input[name=disk]").forEach((el) => {
          el.onchange = () => { state.disk = el.value; drawActions(); };
        });
      },
      focus: "input[name=disk]:checked",
    };
  },

  tailscale() {
    const ts = state.tailscale;
    const intro = `<h1>Tailscale</h1>
      <p class="lede">Tailscale lets you reach this computer from anywhere. It is the only way in from outside your network.</p>`;
    if (ts.state === "connected") {
      return {
        html: `${intro}<div class="notice notice--good"><strong>Connected.</strong> This computer will appear on your tailnet as <code>${esc(state.info.hostname)}</code>.</div>`,
        actions: [
          { label: "Back", run: () => show("disk") },
          { label: "Continue", primary: true, run: () => show("apps") },
        ],
      };
    }
    if (ts.state === "starting" || ts.state === "waiting") {
      return {
        html: `${intro}
          <div class="scan">
            <div class="qr">${ts.qr || ""}</div>
            <div>
              <h2 style="margin-top:0">Scan with your phone</h2>
              <p>Sign in to Tailscale and approve this device. This screen moves on by itself.</p>
              <p class="small muted" style="margin-top: var(--s2)">Or open this address on another device:</p>
              <p class="code">${esc(ts.url || "Getting a sign-in address.")}</p>
            </div>
          </div>`,
        actions: [
          { label: "Cancel", async run() { state.tailscale = await api("tailscale/cancel", {}); show("tailscale"); } },
          { label: "Waiting for sign-in", primary: true, disabled: true },
        ],
        enter: pollTailscale,
      };
    }
    return {
      html: `${intro}
        <p>You sign in by scanning a code with your phone. You can also skip this and set it up later.</p>
        ${ts.state === "failed" ? `<div class="notice notice--bad">${esc(ts.error)}</div>` : ""}`,
      actions: [
        { label: "Back", run: () => show("disk") },
        { label: "Skip for now", quiet: true, run: () => show("apps") },
        { label: "Connect Tailscale", primary: true, async run() { state.tailscale = await api("tailscale/start", {}); show("tailscale"); } },
      ],
    };
  },

  apps() {
    const group = (title, kind) => `<div>
      <h2>${title}</h2>
      <div class="choices">${state.info.apps.filter((a) => a.kind === kind).map((a) => `
        <label class="choice">
          <input type="checkbox" name="app" value="${esc(a.id)}" ${state.apps.has(a.id) ? "checked" : ""}>
          <span class="box">${icon("tick")}</span>
          <span class="name">${esc(a.label)}</span>
        </label>`).join("")}</div></div>`;
    return {
      html: `<h1>Apps</h1>
        <p class="lede">Choose what to install. Anything else can be added later.</p>
        <div class="columns">${group("Agents", "npm")}${group("Tools", "system")}</div>`,
      actions: [
        { label: "Back", run: () => show("tailscale") },
        { label: "Continue", primary: true, run: () => show("review") },
      ],
      bind() {
        document.querySelectorAll("input[name=app]").forEach((el) => {
          el.onchange = () => el.checked ? state.apps.add(el.value) : state.apps.delete(el.value);
        });
      },
      focus: "input[name=app]",
    };
  },

  review() {
    const disk = state.disks.find((d) => d.path === state.disk);
    const apps = state.info.apps.filter((a) => state.apps.has(a.id)).map((a) => a.label);
    const also = state.earlier && state.earlier !== state.disk
      ? ` The earlier install on <code>${esc(state.earlier)}</code> will be erased as well.` : "";
    return {
      html: `<h1>Review</h1>
        <p class="lede">Check these, then install.</p>
        <dl class="summary">
          <dt>Log in with</dt><dd>${state.keyCount} SSH key${state.keyCount === 1 ? "" : "s"} from github.com/${esc(state.user)}</dd>
          <dt>Disk</dt><dd>${esc(disk.model)}, ${esc(disk.size)} <span class="muted code">${esc(disk.path)}</span></dd>
          <dt>Tailscale</dt><dd>${state.tailscale.state === "connected" ? "Connected" : "Not set up"}</dd>
          <dt>Apps</dt><dd>${apps.length ? esc(apps.join(", ")) : "None"}</dd>
        </dl>
        <div class="notice notice--bad"><strong>Everything on ${esc(disk.model)} will be erased.</strong>${also}</div>`,
      actions: [
        { label: "Back", run: () => show("apps") },
        {
          label: "Erase disk and install", danger: true,
          async run() {
            await api("install", { disk: state.disk, user: state.user, apps: [...state.apps] });
            show("installing");
          },
        },
      ],
    };
  },

  installing() {
    const st = state.install || { phase: -1, phases: [], copied: 0, log: [] };
    const copying = st.phases[st.phase] === "Copying the system";
    const lit = Math.round((copying ? st.copied : 0) * 32);
    const cells = Array.from({ length: 32 }, (_, i) =>
      `<i style="--i:${i}" class="${copying && i < lit ? "is-on" : ""}"></i>`).join("");
    if (st.state === "failed") {
      return {
        html: `<h1>The install stopped</h1>
          <div class="notice notice--bad"><strong>${esc(st.error)}</strong></div>
          <p class="logline" style="white-space: pre-wrap">${esc(st.log.slice(-6).join("\n"))}</p>`,
        actions: [{ label: "Back to review", primary: true, run: () => show("review") }],
      };
    }
    return {
      html: `<h1>Installing</h1>
        <p class="lede">Leave the computer on. This takes about ten minutes.</p>
        <div class="meter ${copying && st.copied > 0 ? "" : "is-busy"}">${cells}</div>
        <ol class="phases">${st.phases.map((title, i) => `
          <li class="${i < st.phase ? "is-done" : i === st.phase ? "is-current" : ""}">
            ${icon(i === st.phase ? "pointer" : "tick")}<span>${esc(title)}</span>
          </li>`).join("")}</ol>
        <p class="logline">${esc(st.log[st.log.length - 1] || "")}</p>`,
      actions: [],
      enter() {
        const poll = async () => {
          state.install = await api("install");
          if (state.install.state === "done") return show("done");
          redraw();
        };
        poll();
        every(1000, poll);
      },
    };
  },

  done() {
    const { hostname, user } = state.info;
    const ts = state.tailscale.state === "connected";
    const st = state.install;
    const groups = (st.recoveryKey || "").split("-");
    const keyRows = [];
    for (let i = 0; i < groups.length; i += 4) keyRows.push(groups.slice(i, i + 4).join("-"));
    return {
      html: `<h1>Installed</h1>
        <p class="lede">Take out the USB stick, then restart.</p>
        <h2>Logging in</h2>
        <div class="lines">
          <div><span class="muted">On the same network</span><code>ssh ${esc(user)}@${esc(hostname)}.local</code></div>
          ${ts ? `<div><span class="muted">From anywhere</span><code>ssh ${esc(user)}@${esc(hostname)}</code></div>` : ""}
        </div>
        <p class="small muted" style="margin-top: var(--s1)">The apps you chose finish installing in the background after the first start.</p>
        ${st.recoveryKey ? `
        <h2>Disk recovery key</h2>
        <div class="scan" style="margin-top: var(--s1)">
          <div class="qr">${st.recoveryQr}</div>
          <div>
            <p>The disk is encrypted. If this computer's hardware fails or its BIOS is updated, this key is the only way to get back in. Save it now. Scanning the code copies it to your phone.</p>
            <p class="keycode" style="margin-top: var(--s2)">${keyRows.map(esc).join("-<br>")}</p>
          </div>
        </div>` : ""}`,
      actions: [{ label: "Restart", primary: true, run: () => api("restart", {}) }],
    };
  },
};

async function pollTailscale() {
  every(1500, async () => {
    const before = state.tailscale.state + state.tailscale.url;
    state.tailscale = await api("tailscale");
    if (state.tailscale.state === "connected") {
      clearInterval(timer);
      return show("apps");
    }
    if (before !== state.tailscale.state + state.tailscale.url) redraw();
  });
}

// ------------------------------------------------------------- drawing ---

let current = null;

function drawRail() {
  const at = STEPS.findIndex(([id]) => id === state.screen);
  const past = ["installing", "done"].includes(state.screen);
  $(".rail").classList.toggle("is-hidden", state.screen === "welcome");
  $("#rail").innerHTML = STEPS.map(([, label], i) => {
    const cls = past || i < at ? "is-done" : i === at ? "is-current" : "";
    return `<li class="${cls}" ${i === at ? 'aria-current="step"' : ""}>${icon(cls === "is-done" ? "tick" : "pointer")}<span>${label}</span></li>`;
  }).join("");
  $("#bar-note").textContent = at >= 0 ? `Step ${at + 1} of ${STEPS.length}` : "";
}

function drawActions() {
  const box = $("#actions");
  box.innerHTML = "";
  (current.actions || []).forEach((a, i) => {
    if (i === 1 && current.actions.length > 1) box.append(Object.assign(document.createElement("span"), { className: "spacer" }));
    const b = document.createElement("button");
    b.className = "button" + (a.primary ? " button--primary" : a.danger ? " button--danger" : a.quiet ? " button--quiet" : "");
    b.textContent = a.label;
    b.disabled = !!a.disabled;
    // Only a plain primary button answers Enter and takes focus. The erase
    // button never does: it has to be clicked or tabbed to on purpose.
    if (a.primary) b.dataset.main = "1";
    if (a.run) b.onclick = a.run;
    box.append(b);
  });
  if (current.actions?.length === 1) box.prepend(Object.assign(document.createElement("span"), { className: "spacer" }));
}

// Draw the current screen again, keeping what the person has typed.
function redraw() {
  const typed = {};
  document.querySelectorAll("#stage input:not([type=radio]):not([type=checkbox])").forEach((el) => { typed[el.id] = el.value; });
  const focused = document.activeElement?.id;
  current = { ...current, ...screens[state.screen](), enter: null };
  $("#stage").innerHTML = current.html;
  for (const [id, value] of Object.entries(typed)) { const el = document.getElementById(id); if (el) el.value = value; }
  drawActions();
  current.bind?.();
  if (focused) document.getElementById(focused)?.focus();
}

function show(name) {
  clearInterval(timer);
  state.screen = name;
  current = screens[name]();
  $("#stage").innerHTML = current.html;
  $("#stage").scrollTop = 0;
  drawRail();
  drawActions();
  current.bind?.();
  current.enter?.();
  const target = current.focus ? $(current.focus) : $("#actions [data-main]");
  target?.focus();
}

// Enter runs the main button; Escape goes back.
document.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && e.target.tagName !== "BUTTON") {
    const main = $("#actions [data-main]");
    if (main && !main.disabled) { e.preventDefault(); main.click(); }
  }
  if (e.key === "Escape") {
    const back = [...document.querySelectorAll("#actions .button")].find((b) => /^(Back|Cancel)/.test(b.textContent));
    back?.click();
  }
});

(async () => {
  state.info = await api("info");
  state.user = state.info.githubUser;
  state.apps = new Set(state.info.apps.filter((a) => a.on).map((a) => a.id));
  show("welcome");
})();
