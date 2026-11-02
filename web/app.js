import { parseTracklist, bestSetlist, bestMatch, buildQuery, soleURL, cleanTitle, youtubeVideoId, sourceKey } from "./setlist-core.js";

// ---------- Storage ----------
const store = {
  get: (k, d) => { try { const v = localStorage.getItem(k); return v === null ? d : JSON.parse(v); } catch { return d; } },
  set: (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} },
};
const settings = Object.assign({ autoSync: true, clientId: "", ytKey: "", prefix: "" }, store.get("settings", {}));
const saveSettings = () => store.set("settings", settings);
const history = store.get("history", []);
const saveHistory = () => store.set("history", history);

// ---------- DOM ----------
const $ = (id) => document.getElementById(id);
const baseURL = location.origin + location.pathname.replace(/index\.html$/, "");
const REDIRECT_URI = baseURL;

$("autoSync").checked = settings.autoSync;
$("clientId").value = settings.clientId;
$("ytKey").value = settings.ytKey;
$("redirectUri").textContent = REDIRECT_URI;
$("referrer").textContent = baseURL + "*";
$("shortcutUrl").textContent = baseURL + "?share=";
const autoHint = () => { $("autoHint").textContent = settings.autoSync ? "Shared sets are saved without asking." : "You review the matches before saving."; };
autoHint();

$("autoSync").onchange = (e) => { settings.autoSync = e.target.checked; saveSettings(); autoHint(); };
$("clientId").oninput = (e) => { settings.clientId = e.target.value.trim(); saveSettings(); };
$("ytKey").oninput = (e) => { settings.ytKey = e.target.value.trim(); saveSettings(); };
$("copyRedirect").onclick = () => navigator.clipboard?.writeText(REDIRECT_URI);
$("go").onclick = () => run({ text: $("input").value });

// ---------- Spotify (PKCE) ----------
const spotify = {
  get tokens() { return store.get("spotifyTokens", null); },
  set tokens(v) { store.set("spotifyTokens", v); },
  get profile() { return store.get("spotifyProfile", null); },
  set profile(v) { store.set("spotifyProfile", v); },
  get connected() { const t = this.tokens; return !!t && (!!t.refresh_token || t.expires_at > Date.now()); },

  async login(pendingShare) {
    if (!settings.clientId) throw new Error("Add a Spotify Client ID first.");
    const verifier = rand(64);
    const challenge = b64url(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
    const state = rand(16);
    store.set("pkce", { verifier, state, pendingShare: pendingShare || null });
    const p = new URLSearchParams({
      client_id: settings.clientId, response_type: "code", redirect_uri: REDIRECT_URI,
      code_challenge_method: "S256", code_challenge: challenge, state,
      scope: "playlist-modify-private playlist-modify-public playlist-read-private",
    });
    location.href = "https://accounts.spotify.com/authorize?" + p;
  },

  async handleCallback() {
    const q = new URLSearchParams(location.search);
    if (!q.get("code") && !q.get("error")) return null;
    const pkce = store.get("pkce", null);
    window.history.replaceState(null, "", baseURL);
    if (q.get("error")) throw new Error("Spotify refused the login: " + q.get("error"));
    if (!pkce || pkce.state !== q.get("state")) throw new Error("Login answer did not match. Try again.");
    const res = await fetch("https://accounts.spotify.com/api/token", {
      method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "authorization_code", code: q.get("code"), redirect_uri: REDIRECT_URI,
        client_id: settings.clientId, code_verifier: pkce.verifier }),
    });
    if (!res.ok) throw new Error("Token exchange failed: " + (await res.text()).slice(0, 200));
    const t = await res.json();
    this.tokens = { access_token: t.access_token, refresh_token: t.refresh_token, expires_at: Date.now() + t.expires_in * 1000 };
    this.profile = await this.api("GET", "me");
    localStorage.removeItem("pkce");
    return pkce.pendingShare;
  },

  async accessToken() {
    const t = this.tokens;
    if (!t) throw new Error("Connect Spotify first.");
    if (t.expires_at - Date.now() > 60_000) return t.access_token;
    if (!t.refresh_token) throw new Error("Spotify session expired. Connect again.");
    const res = await fetch("https://accounts.spotify.com/api/token", {
      method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: t.refresh_token, client_id: settings.clientId }),
    });
    if (!res.ok) { this.tokens = null; throw new Error("Spotify session expired. Connect again."); }
    const n = await res.json();
    this.tokens = { access_token: n.access_token, refresh_token: n.refresh_token || t.refresh_token, expires_at: Date.now() + n.expires_in * 1000 };
    return n.access_token;
  },

  async api(method, path, body, retried = false) {
    const token = await this.accessToken();
    const res = await fetch("https://api.spotify.com/v1/" + path, {
      method, headers: { Authorization: "Bearer " + token, ...(body ? { "Content-Type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status === 429 && !retried) {
      const wait = Math.min(Number(res.headers.get("Retry-After") || 1), 10);
      await new Promise((r) => setTimeout(r, wait * 1000));
      return this.api(method, path, body, true);
    }
    if (!res.ok) throw new Error(`Spotify ${res.status}: ${(await res.text()).slice(0, 160)}`);
    return res.status === 204 ? null : res.json();
  },

  async search(term, limit = 5) {
    const r = await this.api("GET", `search?${new URLSearchParams({ q: term, type: "track", limit })}`);
    return (r.tracks?.items || []).map((t) => ({
      id: t.uri, title: t.name, artists: t.artists.map((a) => a.name), url: t.external_urls?.spotify,
    }));
  },

  async createPlaylist(name, description, uris) {
    const me = this.profile || (this.profile = await this.api("GET", "me"));
    const pl = await this.api("POST", `users/${encodeURIComponent(me.id)}/playlists`, { name, description, public: false });
    for (let i = 0; i < uris.length; i += 100) {
      await this.api("POST", `playlists/${pl.id}/tracks`, { uris: uris.slice(i, i + 100) });
    }
    return { id: pl.id, name: pl.name, url: pl.external_urls?.spotify };
  },

  disconnect() { localStorage.removeItem("spotifyTokens"); localStorage.removeItem("spotifyProfile"); },
};

function rand(n) {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
  return Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => chars[b % chars.length]).join("");
}
function b64url(buf) {
  return btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function renderSpotify() {
  const on = spotify.connected;
  $("spotifyStatus").textContent = on ? `Connected as ${spotify.profile?.display_name || spotify.profile?.id || "you"}` : "Not connected";
  $("spotifyBtn").textContent = on ? "Disconnect" : "Connect";
  $("spotifySetup").classList.toggle("hidden", on);
  $("spotifyBtn").onclick = async () => {
    if (on) { spotify.disconnect(); renderSpotify(); return; }
    try { await spotify.login(null); } catch (e) { alert(e.message); }
  };
}

// ---------- Sources ----------
async function fetchYouTube(videoId) {
  if (!settings.ytKey) throw new Error("Add a YouTube API key to read YouTube descriptions.");
  const api = (path, params) => fetch(`https://www.googleapis.com/youtube/v3/${path}?${new URLSearchParams({ ...params, key: settings.ytKey })}`)
    .then(async (r) => { if (!r.ok) throw new Error(`YouTube ${r.status}: ${(await r.json().catch(() => ({})))?.error?.message || ""}`); return r.json(); });
  const v = await api("videos", { part: "snippet", id: videoId });
  const item = v.items?.[0];
  if (!item) throw new Error("Video not found.");
  const texts = [item.snippet.description];
  try {
    const c = await api("commentThreads", { part: "snippet", videoId, order: "relevance", maxResults: 50, textFormat: "plainText" });
    for (const t of c.items || []) {
      const s = t.snippet.topLevelComment.snippet.textOriginal;
      if (s && s.length >= 40) texts.push(s);
    }
  } catch { /* comments disabled or quota: description alone is fine */ }
  return { title: item.snippet.title, texts };
}

async function fetchMixcloud(url) {
  const parts = new URL(url).pathname.split("/").filter(Boolean);
  if (parts.length < 2) throw new Error("Not a Mixcloud set link.");
  const r = await fetch(`https://api.mixcloud.com/${parts[0]}/${parts[1]}/`);
  if (!r.ok) throw new Error("Mixcloud did not answer.");
  const j = await r.json();
  return { title: j.name, texts: [j.description || ""] };
}

async function detect(text) {
  const url = soleURL(text);
  if (!url) return parseTracklist(text);
  const id = youtubeVideoId(url);
  let page;
  if (id) page = await fetchYouTube(id);
  else if (/(^|\.)mixcloud\.com$/i.test(url.hostname)) page = await fetchMixcloud(url);
  else throw new Error("This site can't be read from a browser. Copy the tracklist text and share that instead.");
  return bestSetlist(page.texts, { title: cleanTitle(page.title), sourceURL: url.href });
}

// ---------- Flow ----------
const flow = $("flow");
const inputCard = $("inputCard");
let state = null;

function show(html) { flow.innerHTML = html; flow.classList.remove("hidden"); inputCard.classList.add("hidden"); window.scrollTo(0, 0); }
function reset() { flow.classList.add("hidden"); inputCard.classList.remove("hidden"); state = null; $("input").value = ""; }
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const statusView = (icon, title, msg, buttons = "") =>
  `<div class="status"><div class="big">${icon}</div><b>${esc(title)}</b>${msg ? `<p class="muted">${esc(msg)}</p>` : ""}${buttons}</div>`;

async function run({ text }, { ignoreDuplicate = false } = {}) {
  if (!text || !text.trim()) return;
  show(statusView("🔎", "Looking for a tracklist…"));
  let setlist;
  try {
    setlist = await detect(text);
  } catch (e) {
    return show(statusView("⚠️", "Could not read that", e.message, `<button class="secondary" id="back">Back</button>`)), ($("back").onclick = reset);
  }
  if (!setlist.isLikely) {
    const n = setlist.searchable.length;
    return show(statusView("❓", "No tracklist found", n ? `Only ${n} track line${n === 1 ? "" : "s"} found.` : "Try sharing the tracklist text or a different link.",
      `<button class="secondary" id="back">Back</button>`)), ($("back").onclick = reset);
  }
  if (!spotify.connected) {
    show(statusView("🎧", "Connect Spotify to continue", "You'll come straight back here afterwards.",
      `<button class="primary" id="connect">Connect Spotify</button><button class="secondary" id="back">Back</button>`));
    $("connect").onclick = () => spotify.login(text).catch((e) => alert(e.message));
    $("back").onclick = reset;
    return;
  }
  const previous = !ignoreDuplicate && setlist.sourceURL && history.find((h) => h.sourceKey === sourceKey(setlist.sourceURL));
  if (previous) {
    show(statusView("✅", "Already synced", `Saved as “${previous.playlistName}” on ${new Date(previous.date).toLocaleString()}.`,
      `<button class="primary" id="again">Sync again</button><button class="secondary" id="back">Back</button>`));
    $("again").onclick = () => run({ text }, { ignoreDuplicate: true });
    $("back").onclick = reset;
    return;
  }
  state = { setlist, text, matches: [], selected: new Set(), playlistName: defaultName(setlist) };
  await match();
}

function defaultName(setlist) {
  const base = cleanTitle(setlist.title) || "DJ Set";
  return `${settings.prefix}${base} · ${new Date().toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" })}`.slice(0, 100);
}

async function match() {
  const entries = state.setlist.searchable;
  let done = 0;
  const render = () => show(`<div class="status"><b>Matching ${done} of ${entries.length} tracks on Spotify…</b><div class="bar"><div style="width:${(100 * done) / entries.length}%"></div></div></div>`);
  render();
  const results = new Array(entries.length);
  let next = 0;
  const worker = async () => {
    while (next < entries.length) {
      const i = next++;
      results[i] = await matchOne(entries[i]);
      done += 1;
      render();
    }
  };
  await Promise.all(Array.from({ length: Math.min(3, entries.length) }, worker));
  state.matches = results;
  state.selected = new Set(results.filter((m) => m.isConfident).map((m) => m.entry.id));
  if (settings.autoSync) await save();
  else review();
}

async function matchOne(entry) {
  const q = buildQuery(entry.artist, entry.title);
  let candidates = await spotify.search(q.searchTerm).catch(() => []);
  let m = bestMatch(entry, candidates, q);
  if (!m.isConfident && q.fallbackTerm !== q.searchTerm) {
    candidates = candidates.concat(await spotify.search(q.fallbackTerm).catch(() => []));
    m = bestMatch(entry, candidates, q);
  }
  return m;
}

function review() {
  const { matches, selected, setlist } = state;
  const unid = setlist.entries.filter((e) => e.isUnidentified);
  show(`
    <input type="text" id="plName" value="${esc(state.playlistName)}">
    <p class="caption"><span id="selCount">${selected.size}</span> of ${matches.length} tracks selected</p>
    <div id="matchList">${matches.map((m) => matchRow(m, selected.has(m.entry.id))).join("")}</div>
    ${unid.length ? `<p class="caption">Unreleased / ID tracks (not searchable):</p>${unid.map((e) => `<p class="muted">${esc(e.rawLine)}</p>`).join("")}` : ""}
    <button class="primary" id="saveBtn">Save to Spotify</button>
    <button class="secondary" id="back">Cancel</button>`);
  $("plName").oninput = (e) => { state.playlistName = e.target.value; };
  $("back").onclick = reset;
  $("saveBtn").onclick = save;
  const updateBtn = () => { $("saveBtn").disabled = selected.size === 0; $("saveBtn").textContent = `Save ${selected.size} tracks to Spotify`; $("selCount").textContent = selected.size; };
  updateBtn();
  for (const el of flow.querySelectorAll(".match")) {
    el.onclick = () => {
      const id = Number(el.dataset.id);
      const m = matches.find((x) => x.entry.id === id);
      if (!m.candidate) return;
      if (selected.has(id)) selected.delete(id); else selected.add(id);
      el.classList.toggle("on", selected.has(id));
      updateBtn();
    };
  }
}

function matchRow(m, on) {
  const e = m.entry;
  const label = e.artist ? `${e.artist} - ${e.title}` : e.title;
  const c = m.candidate;
  return `<div class="match ${on ? "on" : ""} ${c ? "" : "none"}" data-id="${e.id}">
    <div class="check">${on ? "✓" : ""}</div>
    <div class="t"><b>${esc(label)}</b>${c ? `<span>${esc(c.title)} · ${esc(c.artists.join(", "))}</span>` : `<span class="bad">No match found</span>`}</div>
    ${c ? `<span class="pill ${m.isConfident ? "ok" : "unsure"}">${m.isConfident ? "Match" : "Unsure"}</span>` : ""}
  </div>`;
}

async function save() {
  const { matches, selected, setlist } = state;
  const uris = matches.filter((m) => selected.has(m.entry.id) && m.candidate).map((m) => m.candidate.id);
  if (!uris.length) { review(); return alert("No tracks selected."); }
  show(statusView("💾", "Saving playlist…"));
  try {
    const name = state.playlistName.trim() || defaultName(setlist);
    let description = "Synced with DJ Sync Toggle" + (setlist.sourceURL ? ` from ${setlist.sourceURL}` : "");
    const pl = await spotify.createPlaylist(name, description.slice(0, 300), uris);
    const savedIds = new Set(matches.filter((m) => selected.has(m.entry.id) && m.candidate).map((m) => m.entry.id));
    const unmatched = setlist.entries.filter((e) => !savedIds.has(e.id)).map((e) => (e.artist ? `${e.artist} - ${e.title}` : e.rawLine));
    history.unshift({ date: Date.now(), setTitle: cleanTitle(setlist.title) || "DJ Set", sourceURL: setlist.sourceURL || null,
      sourceKey: setlist.sourceURL ? sourceKey(setlist.sourceURL) : null, playlistName: pl.name, playlistURL: pl.url,
      savedCount: savedIds.size, totalCount: setlist.entries.length, unmatched });
    history.length = Math.min(history.length, 200);
    saveHistory(); renderHistory();
    show(`<div class="status"><div class="big">✅</div><b>Saved to Spotify</b><p class="muted">${esc(pl.name)}<br>${savedIds.size} of ${setlist.entries.length} tracks</p>
      ${pl.url ? `<a class="primary" style="display:block;text-decoration:none;padding:12px" href="${esc(pl.url)}">Open playlist</a>` : ""}
      ${unmatched.length ? `<p class="caption" style="text-align:left">Not saved (${unmatched.length}):</p>${unmatched.map((u) => `<p class="muted" style="text-align:left;margin:2px 0">${esc(u)}</p>`).join("")}` : ""}
      <button class="secondary" id="back">Done</button></div>`);
    $("back").onclick = reset;
  } catch (e) {
    show(statusView("⚠️", "Saving failed", e.message, `<button class="primary" id="rev">Review matches</button><button class="secondary" id="back">Back</button>`));
    $("rev").onclick = review;
    $("back").onclick = reset;
  }
}

function renderHistory() {
  $("histCount").textContent = history.length;
  $("history").innerHTML = history.length ? history.map((h) => `<div class="hist">
    ${h.playlistURL ? `<a href="${esc(h.playlistURL)}">${esc(h.playlistName)}</a>` : esc(h.playlistName)}
    <small>${h.savedCount}/${h.totalCount} tracks · ${new Date(h.date).toLocaleString()}${h.unmatched?.length ? ` · ${h.unmatched.length} not found` : ""}</small>
  </div>`).join("") : `<p class="muted">Nothing synced yet.</p>`;
}

// ---------- Boot ----------
(async () => {
  renderHistory();
  try {
    const pending = await spotify.handleCallback();
    renderSpotify();
    if (pending) return run({ text: pending });
  } catch (e) {
    renderSpotify();
    alert(e.message);
  }
  const q = new URLSearchParams(location.search);
  const shared = q.get("share") || q.get("text") || q.get("url");
  if (shared) {
    window.history.replaceState(null, "", baseURL);
    $("input").value = shared;
    run({ text: shared });
  }
})();
