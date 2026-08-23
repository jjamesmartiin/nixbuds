// Omarchpods web UI.
//
// Talks to the omarchpods core daemon over WebSocket (ws://localhost:2020).
// The daemon is the same JSON API the Textual TUI uses:
//   request:  { "method": "GetAll", "arguments": { ... } }
//   response: { "headphones": [...], "defaultbluetooth": {...}, "info": {...} }
// plus broadcast topics that arrive unprompted (onCapabilityChanged,
// OnConnectedChanged, OnActiveDeviceChanged, OnDefaultAdapterChangeEnabled).

"use strict";

const WS_URL = "ws://localhost:2020";
const RECONNECT_DELAY_MS = 3000;

// ANC modes, matching DeviceAncModes in the core.
const ANC_MODES = [
  { value: 1, label: "Off" },
  { value: 2, label: "Transparency" },
  { value: 4, label: "Adaptive" },
  { value: 8, label: "Wind Cancellation" },
  { value: 16, label: "Noise Cancellation" },
];

const state = {
  ws: null,
  connected: false,
  devices: [],          // { name, address, connected }
  adapter: { enabled: false },
  activeInfo: {},       // active device incl. capabilities
  activeAddress: null,
  reconnectTimer: null,
};

const $ = (id) => document.getElementById(id);

// ---------------------------------------------------------------------------
// WebSocket plumbing
// ---------------------------------------------------------------------------

function connect() {
  state.ws = new WebSocket(WS_URL);
  state.ws.onopen = () => {
    state.connected = true;
    setDaemonStatus(true);
    send("GetAll");
  };
  state.ws.onmessage = (evt) => {
    let msg;
    try {
      msg = JSON.parse(evt.data);
    } catch {
      return;
    }
    // Merge whatever the daemon sent; any of these keys may arrive alone.
    if (Array.isArray(msg.headphones)) state.devices = msg.headphones;
    if (msg.defaultbluetooth) state.adapter = msg.defaultbluetooth;
    if (msg.info) {
      state.activeInfo = msg.info;
      if (msg.info.address) state.activeAddress = msg.info.address;
    }
    render();
  };
  state.ws.onclose = () => {
    state.connected = false;
    setDaemonStatus(false);
    scheduleReconnect();
  };
  state.ws.onerror = () => state.ws.close();
}

function scheduleReconnect() {
  clearTimeout(state.reconnectTimer);
  state.reconnectTimer = setTimeout(connect, RECONNECT_DELAY_MS);
}

function send(method, args) {
  if (state.ws && state.ws.readyState === WebSocket.OPEN) {
    state.ws.send(JSON.stringify(args ? { method, arguments: args } : { method }));
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

function toggleAdapter() {
  const enable = !state.adapter.enabled;
  send(enable ? "EnableDefaultBluetoothAdapter" : "DisableDefaultBluetoothAdapter");
  state.adapter.enabled = enable; // optimistic; corrected by broadcast
  render();
}

function toggleDevice(address) {
  const device = state.devices.find((d) => d.address === address);
  if (!device) return;
  send(device.connected ? "DisconnectDevice" : "ConnectDevice", { address });
}

function setAnc(address, modeValue) {
  send("SetCapabilities", {
    address,
    capabilities: { anc: { selected: modeValue } },
  });
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function setDaemonStatus(ok) {
  const el = $("daemon-status");
  el.textContent = ok ? "daemon connected" : "daemon offline — retrying…";
  el.className = "status-pill " + (ok ? "status-on" : "status-off");
}

function render() {
  renderAdapter();
  renderDeviceList();
  renderDetail();
}

function renderAdapter() {
  const card = $("adapter-card");
  card.classList.remove("hidden");

  const btn = $("adapter-toggle");
  btn.textContent = state.adapter.enabled ? "Disable" : "Enable";
  btn.className = "toggle" + (state.adapter.enabled ? " on" : "");
  btn.disabled = !state.connected;

  $("adapter-note").textContent = state.adapter.enabled
    ? "Bluetooth adapter is on."
    : "Bluetooth adapter is off — no devices can connect.";
}

function renderDeviceList() {
  const list = $("device-list");
  $("device-count").textContent = state.devices.length
    ? state.devices.length + " device" + (state.devices.length === 1 ? "" : "s")
    : "";

  list.innerHTML = "";

  if (!state.devices.length) {
    const empty = document.createElement("p");
    empty.className = "muted empty";
    empty.textContent = "No headphones found. Pair them with Bluetooth first.";
    list.appendChild(empty);
    return;
  }

  for (const device of state.devices) {
    const row = document.createElement("div");
    row.className = "device" + (device.address === state.activeAddress ? " active" : "");
    row.addEventListener("click", () => {
      state.activeAddress = device.address;
      render();
    });

    const dot = document.createElement("span");
    dot.className = "dot" + (device.connected ? " connected" : "");

    const info = document.createElement("div");
    info.className = "info";
    const name = document.createElement("div");
    name.className = "name";
    name.textContent = device.name || "(unnamed device)";
    const addr = document.createElement("div");
    addr.className = "addr";
    addr.textContent = device.address;

    const btn = document.createElement("button");
    btn.className = "btn" + (device.connected ? " disconnect" : "");
    btn.textContent = device.connected ? "Disconnect" : "Connect";
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      toggleDevice(device.address);
    });

    info.append(name, addr);
    row.append(dot, info, btn);
    list.appendChild(row);
  }
}

function renderDetail() {
  const detail = $("device-detail");
  const activeName = $("active-name");

  if (!state.activeInfo || !state.activeInfo.address) {
    detail.innerHTML = "";
    const empty = document.createElement("p");
    empty.className = "muted empty";
    empty.textContent = "No active device.";
    detail.appendChild(empty);
    activeName.textContent = "";
    return;
  }

  activeName.textContent = state.activeInfo.name || "";

  const caps = state.activeInfo.capabilities || {};
  const sections = [];

  // Battery
  const battery = caps.battery;
  if (battery) {
    const box = document.createElement("div");
    box.className = "battery";
    for (const part of ["case", "left", "right", "single"]) {
      const data = battery[part];
      if (!data) continue;
      const pct = typeof data.battery === "number" ? data.battery : null;
      const row = document.createElement("div");
      row.className = "detail-row";
      row.append(el("span", part[0].toUpperCase() + part.slice(1)));
      if (pct === null) {
        row.append(el("span", data.status || "Unknown"));
        box.appendChild(row);
        continue;
      }
      row.append(el("span", pct + "%" + (data.charging ? " ⚡" : "")));
      box.appendChild(row);

      const bar = document.createElement("div");
      bar.className = "bar";
      const fill = document.createElement("span");
      fill.style.width = Math.max(0, Math.min(100, pct)) + "%";
      if (pct < 20) fill.className = "critical";
      else if (pct < 50) fill.className = "low";
      bar.appendChild(fill);
      box.appendChild(bar);
    }
    sections.push(section("Battery", box));
  }

  // Ear detection
  const ear = caps.earDetection;
  if (ear && ear.status) {
    const box = document.createElement("div");
    const row = document.createElement("div");
    row.className = "detail-row";
    row.append(el("span", "Status"), el("span", ear.status));
    box.appendChild(row);
    sections.push(section("Ear detection", box));
  }

  // ANC modes
  const anc = caps.anc;
  if (anc) {
    const box = document.createElement("div");
    const modes = document.createElement("div");
    modes.className = "anc-modes";
    const available = anc.options || 0;
    for (const mode of ANC_MODES) {
      const btn = document.createElement("button");
      btn.className = "anc-mode" + (anc.selected === mode.value ? " selected" : "");
      btn.textContent = mode.label;
      const supported = (available & mode.value) !== 0;
      btn.disabled = anc.readonly || !supported;
      btn.addEventListener("click", () => setAnc(state.activeAddress, mode.value));
      modes.appendChild(btn);
    }
    if (!available) {
      const p = document.createElement("p");
      p.className = "muted";
      p.textContent = "ANC modes unavailable for this device.";
      box.appendChild(p);
    }
    box.appendChild(modes);
    sections.push(section("Noise control", box));
  }

  detail.innerHTML = "";
  if (!sections.length) {
    const p = document.createElement("p");
    p.className = "muted empty";
    p.textContent = "No capability data yet for this device.";
    detail.appendChild(p);
  }
  for (const s of sections) detail.appendChild(s);
}

function section(title, content) {
  const box = document.createElement("div");
  box.style.marginBottom = "14px";
  const h = document.createElement("h3");
  h.textContent = title;
  h.style.cssText = "font-size:12px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin:0 0 6px";
  box.append(h, content);
  return box;
}

function el(tag, text) {
  const e = document.createElement(tag);
  if (text !== undefined) e.textContent = text;
  return e;
}

// ---------------------------------------------------------------------------

$("adapter-toggle").addEventListener("click", toggleAdapter);
connect();
