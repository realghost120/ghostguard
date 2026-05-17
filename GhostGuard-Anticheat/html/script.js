const RESOURCE = (window.GetParentResourceName && GetParentResourceName()) || "GhostGuard-Anticheat";

const nui = (name, data = {}) =>
  fetch(`https://${RESOURCE}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(data),
  }).then(r => r.json().catch(() => ({})));

const state = {
  tab: "players",
  players: [],
  bans: [],
  logs: [],
  alerts: [],
  selected: null, // { type, key, raw }
};

const els = {
  body: document.body,

  onlineCount: document.getElementById("onlineCount"),
  btnClose: document.getElementById("btnClose"),
  btnRefresh: document.getElementById("btnRefresh"),
  tabs: Array.from(document.querySelectorAll(".tab")),

  leftTitle: document.getElementById("leftTitle"),
  leftList: document.getElementById("leftList"),
  leftEmpty: document.getElementById("leftEmpty"),

  rightTitle: document.getElementById("rightTitle"),
  rightEmpty: document.getElementById("rightEmpty"),

  playerDetails: document.getElementById("playerDetails"),
  banDetails: document.getElementById("banDetails"),
  logDetails: document.getElementById("logDetails"),
  alertDetails: document.getElementById("alertDetails"),

  // player
  pdName: document.getElementById("pdName"),
  pdId: document.getElementById("pdId"),
  pdPing: document.getElementById("pdPing"),
  pdIdent: document.getElementById("pdIdent"),
  reason: document.getElementById("reason"),
  banTime: document.getElementById("banTime"),
  btnGoto: document.getElementById("btnGoto"),
  btnFreeze: document.getElementById("btnFreeze"),
  btnKick: document.getElementById("btnKick"),
  btnBan: document.getElementById("btnBan"),

  // ban
  bdId: document.getElementById("bdId"),
  bdName: document.getElementById("bdName"),
  bdReason: document.getElementById("bdReason"),
  bdCreated: document.getElementById("bdCreated"),
  bdExpires: document.getElementById("bdExpires"),
  bdIdent: document.getElementById("bdIdent"),
  btnUnban: document.getElementById("btnUnban"),

  // logs
  logBox: document.getElementById("logBox"),

  // alerts
  adTime: document.getElementById("adTime"),
  adName: document.getElementById("adName"),
  adId: document.getElementById("adId"),
  adType: document.getElementById("adType"),
  adDetails: document.getElementById("adDetails"),
  adIdent: document.getElementById("adIdent"),
  dmText: document.getElementById("dmText"),
  btnSendDM: document.getElementById("btnSendDM"),
};

function showApp(on) {
  els.body.classList.toggle("hidden", !on);

  if (on) {
    // Default: players
    state.selected = null;
    selectTab("players", true);
  }
}

function setOnlineCount(n) {
  if (els.onlineCount) els.onlineCount.textContent = `${n} online`;
}

function clearRight() {
  els.rightEmpty.classList.remove("hidden");
  els.playerDetails.classList.add("hidden");
  els.banDetails.classList.add("hidden");
  els.logDetails.classList.add("hidden");
  els.alertDetails.classList.add("hidden");
}

function selectTab(tab, forceRefresh = false) {
  state.tab = tab;
  state.selected = null;

  els.tabs.forEach(t => t.classList.toggle("active", t.dataset.tab === tab));

  render(); // render UI structure first

  if (forceRefresh) refreshCurrentTab();
}

function refreshCurrentTab() {
  if (state.tab === "players") return nui("requestPlayers");
  if (state.tab === "bans") return nui("requestBans");
  if (state.tab === "logs") return nui("requestLogs");
  if (state.tab === "alerts") return nui("requestAlerts");
}

function render() {
  clearRight();

  let list = [];

  if (state.tab === "players") {
    els.leftTitle.textContent = "Spelare online";
    els.rightTitle.textContent = "Player Info (Live)";
    setOnlineCount(state.players.length);

    list = state.players.map(p => ({
      key: String(p.id),
      title: p.name,
      meta: `ID: ${p.id}`,
      right: `${p.ping} ms`,
      raw: p,
    }));
  }

  if (state.tab === "bans") {
    els.leftTitle.textContent = "Bans";
    els.rightTitle.textContent = "Ban Info";

    list = state.bans.map(b => ({
      key: String(b.ban_id),
      title: b.name || "Unknown",
      meta: `Ban ID: ${b.ban_id}`,
      right: b.expires_at ? fmtDate(b.expires_at) : "PERM",
      raw: b,
    }));
  }

  if (state.tab === "logs") {
    els.leftTitle.textContent = "Logs (Live)";
    els.rightTitle.textContent = "Server Logs";

    list = state.logs.slice(0, 120).map((l, idx) => ({
      key: String(idx),
      title: l.title || "Log",
      meta: l.meta || "",
      right: l.time || "",
      raw: l,
    }));

    // default show log feed even without selection
    els.rightEmpty.classList.add("hidden");
    els.logDetails.classList.remove("hidden");
    els.logBox.textContent = (state.logs || []).map(l => l.line).join("\n");
  }

  if (state.tab === "alerts") {
    els.leftTitle.textContent = "Cheat Alerts (Live)";
    els.rightTitle.textContent = "Alert Info";

    list = state.alerts.map((a, idx) => ({
      key: String(idx),
      title: `${a.name} (ID ${a.id})`,
      meta: a.type || "Unknown",
      right: a.time || "",
      raw: a,
    }));
  }

  els.leftList.innerHTML = "";
  els.leftEmpty.style.display = list.length ? "none" : "block";

  list.forEach(item => {
    const div = document.createElement("div");
    div.className = "row";

    if (state.selected && state.selected.type === state.tab && state.selected.key === item.key) {
      div.classList.add("active");
    }

    div.innerHTML = `
      <div>
        <div class="name">${escapeHtml(item.title)}</div>
        <div class="meta">${escapeHtml(item.meta)}</div>
      </div>
      <div class="ping">${escapeHtml(item.right)}</div>
    `;

    div.onclick = () => {
      state.selected = { type: state.tab, key: item.key, raw: item.raw };
      renderRight();
      render(); // refresh active highlight
    };

    els.leftList.appendChild(div);
  });

  renderRight();
}

function renderRight() {
  clearRight();

  // logs: always show feed
  if (state.tab === "logs") {
    els.rightEmpty.classList.add("hidden");
    els.logDetails.classList.remove("hidden");
    els.logBox.textContent = (state.logs || []).map(l => l.line).join("\n");
    return;
  }

  if (!state.selected || state.selected.type !== state.tab) return;

  els.rightEmpty.classList.add("hidden");

  if (state.tab === "players") {
    const p = state.selected.raw;
    els.playerDetails.classList.remove("hidden");
    els.pdName.textContent = p.name || "-";
    els.pdId.textContent = p.id ?? "-";
    els.pdPing.textContent = p.ping ?? "-";
    els.pdIdent.textContent = p.identifier || "-";
  }

  if (state.tab === "bans") {
    const b = state.selected.raw;
    els.banDetails.classList.remove("hidden");
    els.bdId.textContent = b.ban_id || "-";
    els.bdName.textContent = b.name || "-";
    els.bdReason.textContent = b.reason || "-";
    els.bdCreated.textContent = b.created_at ? fmtDate(b.created_at) : "-";
    els.bdExpires.textContent = b.expires_at ? fmtDate(b.expires_at) : "PERMANENT";
    els.bdIdent.textContent = (b.identifiers && b.identifiers[0]) ? b.identifiers[0] : "-";
  }

  if (state.tab === "alerts") {
    const a = state.selected.raw;
    els.alertDetails.classList.remove("hidden");
    els.adTime.textContent = a.time || "-";
    els.adName.textContent = a.name || "-";
    els.adId.textContent = a.id ?? "-";
    els.adType.textContent = a.type || "-";
    els.adDetails.textContent = a.details || "-";
    els.adIdent.textContent = a.identifier || "-";
  }
}

/* ===== Actions ===== */
els.btnClose.onclick = () => nui("close").then(() => showApp(false));
els.btnRefresh.onclick = () => refreshCurrentTab();

els.tabs.forEach(t => {
  t.onclick = () => {
    selectTab(t.dataset.tab, true);
  };
});

els.btnGoto.onclick = () => {
  const p = state.selected?.raw;
  if (!p) return toast("Välj en spelare.");
  nui("teleportTo", { id: p.id });
};

els.btnFreeze.onclick = () => {
  const p = state.selected?.raw;
  if (!p) return toast("Välj en spelare.");
  nui("freezePlayer", { id: p.id });
};

els.btnKick.onclick = () => {
  const p = state.selected?.raw;
  if (!p) return toast("Välj en spelare.");
  const reason = (els.reason.value || "").trim();
  if (!reason) return toast("Skriv anledning för kick.");
  nui("kickPlayer", { id: p.id, reason }).then(() => toast("Kick skickad."));
};

els.btnBan.onclick = () => {
  const p = state.selected?.raw;
  if (!p) return toast("Välj en spelare.");
  const reason = (els.reason.value || "").trim();
  if (!reason) return toast("Skriv anledning för ban.");
  nui("banPlayer", { id: p.id, reason, time: "P" }).then(() => {
    toast("Ban skickad (permanent).");
    refreshCurrentTab();
    nui("requestBans");
  });
};

els.btnUnban.onclick = () => {
  const b = state.selected?.raw;
  if (!b) return toast("Välj en ban.");
  nui("unban", { ban_id: b.ban_id }).then(() => {
    toast("Unban klar.");
    nui("requestBans");
    state.selected = null;
    render();
  });
};

els.btnSendDM.onclick = () => {
  const a = state.selected?.raw;
  if (!a) return toast("Välj en alert.");
  const msg = (els.dmText.value || "").trim();
  if (!msg) return toast("Skriv ett meddelande.");
  nui("sendDM", { id: a.id, msg }).then(() => toast("DM skickat."));
  els.dmText.value = "";
};

/* ===== Incoming from Lua ===== */
window.addEventListener("message", (event) => {
  const m = event.data || {};

  if (m.action === "open") {
    showApp(true);
    // refresh everything once so tabs have data
    nui("requestPlayers");
    nui("requestBans");
    nui("requestLogs");
    nui("requestAlerts");
    return;
  }

  if (m.action === "close") {
    showApp(false);
    return;
  }

  if (m.action === "updatePlayers") {
    state.players = m.players || [];
    if (state.tab === "players") render();
    setOnlineCount(state.players.length);
    return;
  }

  if (m.action === "updateBans") {
    state.bans = m.bans || [];
    if (state.tab === "bans") render();
    return;
  }

  if (m.action === "updateLogs") {
    state.logs = m.logs || [];
    if (state.tab === "logs") render();
    return;
  }

  if (m.action === "updateAlerts") {
    state.alerts = m.alerts || [];
    if (state.tab === "alerts") render();
    return;
  }

  if (m.action === "pushLog") {
    if (m.log) state.logs.unshift(m.log);
    state.logs = state.logs.slice(0, 300);
    if (state.tab === "logs") render();
    return;
  }

  if (m.action === "pushAlert") {
    if (m.alert) state.alerts.unshift(m.alert);
    state.alerts = state.alerts.slice(0, 150);
    if (state.tab === "alerts") render();
    return;
  }
});

/* ESC */
window.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    nui("close").then(() => showApp(false));
  }
});

/* Helpers */
function toast(text) {
  const old = els.rightTitle.textContent;
  els.rightTitle.textContent = text;
  setTimeout(() => (els.rightTitle.textContent = old), 1200);
}

function escapeHtml(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function fmtDate(iso) {
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return String(iso || "-");
  }
}
