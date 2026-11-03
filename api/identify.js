// Vercel serverless function: identify the tracks in a DJ set by audio fingerprinting (AudD).
// The AudD token lives in the AUDD_API_TOKEN environment variable, never in the page.
//
// POST /api/identify  { "url": "https://www.youtube.com/watch?v=..." }
// -> { "tracks": [{ "offset": "12:00", "artist": "...", "title": "..." }], "scanned": 42 }

export const config = { maxDuration: 60 };

const AUDD_ENDPOINT = "https://enterprise.audd.io/";
// AudD bills one request per 12-second chunk. every=1 + skip=4 scans 12 s out of every 60 s,
// which still catches each track of a normal DJ set and costs 60 requests per hour of audio.
const SAMPLING = { every: "1", skip: "4", accurate_offsets: "true" };
const MAX_CHUNKS = 600; // 10 hours at the sampling above
const ALLOWED_HOSTS = /^(?:(?:www|m|music)\.)?(?:youtube\.com|youtu\.be|mixcloud\.com|soundcloud\.com)$/i;

function json(res, status, body) {
  res.status(status).setHeader("Content-Type", "application/json").send(JSON.stringify(body));
}

function allowedURL(raw) {
  try {
    const u = new URL(String(raw));
    if (u.protocol !== "https:" || !ALLOWED_HOSTS.test(u.hostname)) return null;
    return u.href;
  } catch {
    return null;
  }
}

function sameSite(req) {
  const origin = req.headers.origin || req.headers.referer || "";
  const host = req.headers["x-forwarded-host"] || req.headers.host || "";
  return origin === "" || origin.startsWith(`https://${host}`) || origin.startsWith(`http://${host}`);
}

// Collapse AudD's per-chunk results into one entry per track, in play order.
function toTracks(result) {
  const tracks = [];
  for (const chunk of result || []) {
    const song = chunk.songs?.[0];
    if (!song?.artist || !song?.title) continue;
    const last = tracks[tracks.length - 1];
    if (last && last.artist === song.artist && last.title === song.title) continue;
    tracks.push({ offset: chunk.offset, artist: song.artist, title: song.title });
  }
  return tracks;
}

export default async function handler(req, res) {
  if (req.method !== "POST") return json(res, 405, { error: "POST only" });
  if (!sameSite(req)) return json(res, 403, { error: "Forbidden" });
  const token = process.env.AUDD_API_TOKEN;
  if (!token) return json(res, 503, { error: "Audio identification is not configured on this deployment." });

  const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};
  const url = allowedURL(body.url);
  if (!url) return json(res, 400, { error: "Send a YouTube, Mixcloud or SoundCloud link." });

  const form = new URLSearchParams({ api_token: token, url, limit: String(MAX_CHUNKS), ...SAMPLING });
  let data;
  try {
    const r = await fetch(AUDD_ENDPOINT, { method: "POST", body: form });
    data = await r.json();
  } catch (e) {
    return json(res, 502, { error: `Audio service did not answer: ${e.message}` });
  }
  if (data.status !== "success") {
    const msg = data.error?.error_message || "Audio service error";
    return json(res, 502, { error: msg });
  }
  return json(res, 200, { tracks: toTracks(data.result), scanned: (data.result || []).length });
}
