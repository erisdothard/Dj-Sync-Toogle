// Tracklist detection and matching. Mirrors Packages/SetlistCore (Swift) so both versions behave the same.

const P = {
  leadingBullet: /^[-*•·▪►>]+\s+/,
  // "1. ", "1) ", "(1) ", "[1] ", "#1 ", "1: " but not "01:23"
  leadingIndex: /^(?:[([]?\d{1,3}(?:[.)\]]\s*|:\s+)|#\d{1,3}\s*)/,
  leadingTimestamp: /^[[(]?((?:\d{1,2}:)?\d{1,2}:\d{2})[\])]?\s*(?:[-–—:|]\s*)?/,
  trailingTimestamp: /\s*[[(@]?\s*((?:\d{1,2}:)?\d{1,2}:\d{2})\s*[\])]?\s*$/,
  mashupPrefix: /^(?:w\/\s*|(?:vs\.?|\+)\s+)/i,
  trailingBracket: /\s*\[([^\]]*)\]\s*$/,
  unidentified: /^(?:id|\?+|unknown|untitled)\s*[-–—]\s*(?:id|\?+|unknown|untitled)(?=\s|\(|\[|$).*$/i,
  unidentifiedPart: /^(?:id|\?+|unknown|untitled)(?:\s*[([].*)?$/i,
  separator: /\s+[-–—]\s+/,
  byForm: /^(.{1,80}?)\s+by\s+(.{1,60})$/i,
};

const byFormStopWords = new Set([
  "mixed", "recorded", "hosted", "presented", "powered", "produced", "mastered", "photo", "photos",
  "video", "tracklist", "set", "mix", "live set", "dj set", "compiled", "selected", "curated", "supported",
]);

const versionWords = [
  "remix", "mix", "edit", "bootleg", "dub", "version", "rework", "vip", "flip",
  "mashup", "live", "acoustic", "instrumental", "refix", "rmx", "extended", "original",
];

const collapse = (s) => s.replace(/\s+/g, " ").trim();
const looksLikeVersionTag = (s) => {
  const l = s.toLowerCase();
  return versionWords.some((w) => l.includes(w));
};

let nextId = 1;

export function parseLine(rawLine, index) {
  let line = rawLine.trim();
  if (!line || line.length > 200 || line.includes("http")) return null;

  line = line.replace(P.leadingBullet, "").replace(P.leadingIndex, "");

  let timestamp = null;
  let m = line.match(P.leadingTimestamp);
  if (m) {
    timestamp = m[1];
    line = line.replace(P.leadingTimestamp, "");
  } else if ((m = line.match(P.trailingTimestamp))) {
    timestamp = m[1];
    line = line.replace(P.trailingTimestamp, "");
  }
  line = line.replace(P.leadingIndex, "");

  let isMashup = false;
  if (P.mashupPrefix.test(line)) {
    isMashup = true;
    line = line.replace(P.mashupPrefix, "");
  }

  let label = null;
  m = line.match(P.trailingBracket);
  if (m) {
    const content = m[1].trim();
    if (content && !looksLikeVersionTag(content)) {
      label = content;
      line = line.replace(P.trailingBracket, "");
    }
  }
  line = collapse(line);
  if (!line) return null;

  const base = { id: nextId++, index, rawLine, timestamp, label, isMashupContinuation: isMashup };

  if (P.unidentified.test(line)) {
    return { ...base, artist: null, title: "ID", isUnidentified: true };
  }

  const parts = split(line);
  if (!parts || !isPlausible(parts.artist, parts.title)) return null;

  const unidentified = P.unidentifiedPart.test(parts.artist) || P.unidentifiedPart.test(parts.title);
  return { ...base, artist: parts.artist, title: parts.title, isUnidentified: unidentified };
}

function split(line) {
  const m = line.match(P.separator);
  if (m) {
    return { artist: collapse(line.slice(0, m.index)), title: collapse(line.slice(m.index + m[0].length)) };
  }
  const b = line.match(P.byForm);
  if (b && !byFormStopWords.has(collapse(b[1]).toLowerCase())) {
    return { artist: collapse(b[2]), title: collapse(b[1]) };
  }
  return null;
}

function isPlausible(artist, title) {
  if (!artist || !title) return false;
  if (artist.split(" ").length > 10 || title.split(" ").length > 16) return false;
  if (title.endsWith(".") && !title.endsWith("..")) return false;
  return true;
}

export function parseTracklist(text, { title = null, sourceURL = null } = {}) {
  const entries = [];
  let nonEmpty = 0;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    nonEmpty += 1;
    const entry = parseLine(line, entries.length + 1);
    if (entry) entries.push(entry);
  }
  const confidence = nonEmpty === 0 ? 0 : entries.length / nonEmpty;
  const searchable = entries.filter((e) => !e.isUnidentified);
  return { title, sourceURL, entries, confidence, searchable, isLikely: searchable.length >= 3 && confidence >= 0.4 };
}

// ---------- Normalizer ----------

const groupRe = /\(([^)]*)\)|\[([^\]]*)\]/g;
const inlineFeat = /\s+(feat\.?|ft\.?|featuring)\s+(.+)$/i;
const artistSep = /\s*(?:,|&|\+|\bx\b|\bvs\.?\b|\band\b|\bb2b\b)\s*/i;
const trailingNoise = /\s+(?:original mix|extended mix|radio edit|club mix|extended version|original version)\s*$/i;

const noiseTags = new Set([
  "original mix", "extended mix", "radio edit", "radio mix", "club mix", "extended version",
  "original version", "extended", "original", "album version", "single version", "explicit",
  "clean", "official audio", "official video", "official music video", "lyric video", "audio",
  "hq", "free download", "out now", "free dl", "premiere", "snippet", "preview", "full track",
]);

const remixWords = [
  "remix", "bootleg", "rework", "vip", "flip", "mashup", "edit", "dub", "mix", "version",
  "refix", "rmx", "cover", "live", "acoustic", "instrumental",
];

export function splitArtists(text) {
  return text.split(artistSep).map(collapse).filter(Boolean);
}

function classify(content) {
  const lowered = collapse(content).toLowerCase();
  if (!lowered) return { kind: "other" };
  if (noiseTags.has(lowered)) return { kind: "noise" };
  const feat = content.match(/^(?:feat\.?|ft\.?|featuring|with)\s+(.+)$/i);
  if (feat) return { kind: "featured", names: splitArtists(feat[1]) };
  if (remixWords.some((w) => lowered.endsWith(w) || lowered.includes(` ${w} `) || lowered.includes(` ${w}`))) {
    return { kind: "remix", tag: collapse(content) };
  }
  return { kind: "other" };
}

export function buildQuery(artistText, titleText) {
  let title = titleText || "";
  let featured = [];
  let remixTag = null;

  for (const g of title.matchAll(groupRe)) {
    const c = classify((g[1] ?? g[2] ?? "").trim());
    if (c.kind === "featured") featured.push(...c.names);
    else if (c.kind === "remix" && !remixTag) remixTag = c.tag;
  }
  title = title.replace(groupRe, " ");

  const f = title.match(inlineFeat);
  if (f) {
    featured.push(...splitArtists(f[2]));
    title = title.replace(inlineFeat, "");
  }

  const dash = title.match(/^(.+?)\s+[-–—]\s+(.+)$/);
  if (dash) {
    const c = classify(dash[2]);
    if (c.kind === "remix") {
      if (!remixTag) remixTag = c.tag;
      title = dash[1];
    } else if (c.kind === "featured") {
      featured.push(...c.names);
      title = dash[1];
    } else if (c.kind === "noise") {
      title = dash[1];
    }
  }
  title = title.replace(trailingNoise, "");

  let artist = artistText || "";
  const af = artist.match(inlineFeat);
  if (af) {
    featured.push(...splitArtists(af[2]));
    artist = artist.replace(inlineFeat, "");
  }

  const artists = splitArtists(artist);
  title = collapse(title);
  const searchTerm = collapse([artists.join(" "), title, remixTag].filter(Boolean).join(" "));
  const fallbackTerm = collapse([artists[0] ?? "", title].filter(Boolean).join(" "));
  return { artists, title, featured, remixTag, searchTerm, fallbackTerm, allArtists: [...artists, ...featured] };
}

export function tokens(text) {
  const folded = (text || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/\$/g, "s")
    .replace(/[^a-z0-9]+/g, " ");
  return new Set(folded.split(" ").filter(Boolean));
}

// ---------- Scorer ----------

export const ACCEPT_THRESHOLD = 0.62;

function similarity(a, b) {
  if (!a.size || !b.size) return 0;
  let inter = 0;
  for (const t of a) if (b.has(t)) inter += 1;
  const dice = (2 * inter) / (a.size + b.size);
  if (inter === Math.min(a.size, b.size)) return Math.max(dice, 0.8);
  return dice;
}

export function scoreCandidate(query, candidate) {
  const cq = buildQuery(candidate.artists.join(", "), candidate.title);
  const titleSim = similarity(tokens(query.title), tokens(cq.title));
  const qa = tokens(query.allArtists.join(" "));
  const artistSim = qa.size === 0 ? 0.5 : similarity(qa, tokens(cq.allArtists.join(" ")));
  let score = 0.6 * titleSim + 0.4 * artistSim;

  if (query.remixTag && cq.remixTag) {
    const s = similarity(tokens(query.remixTag), tokens(cq.remixTag));
    score += 0.15 * (2 * s - 1);
  } else if (!query.remixTag && cq.remixTag) {
    score -= 0.2;
  } else if (query.remixTag && !cq.remixTag) {
    score -= 0.25;
  }
  return Math.min(Math.max(score, 0), 1);
}

export function bestMatch(entry, candidates, query = buildQuery(entry.artist, entry.title)) {
  let best = null;
  let bestScore = 0;
  for (const c of candidates) {
    const s = scoreCandidate(query, c);
    if (s > bestScore) {
      bestScore = s;
      best = c;
    }
  }
  return { entry, candidate: best, score: bestScore, isConfident: !!best && bestScore >= ACCEPT_THRESHOLD };
}

// ---------- Detection helpers ----------

export function bestSetlist(texts, { title = null, sourceURL = null } = {}) {
  let best = { title, sourceURL, entries: [], confidence: 0, searchable: [], isLikely: false };
  let bestRank = -1;
  for (const text of texts) {
    const s = parseTracklist(text || "", { title, sourceURL });
    const rank = s.searchable.length * Math.max(s.confidence, 0.05) + (s.isLikely ? 100 : 0);
    if (rank > bestRank) {
      bestRank = rank;
      best = s;
    }
  }
  return best;
}

export function soleURL(text) {
  const t = (text || "").trim();
  if (!/^https?:\/\/\S+$/i.test(t)) return null;
  try { return new URL(t); } catch { return null; }
}

export function cleanTitle(title) {
  let t = collapse(title || "");
  if (!t) return null;
  t = t.replace(/\s*(\||-|–|—|·)\s*(free listening on soundcloud|stream .* on soundcloud|soundcloud|mixcloud|youtube music|youtube|1001tracklists|tracklist)\s*$/i, "");
  t = t.replace(/^stream\s+/i, "");
  if (t.length > 70) t = t.slice(0, 70).trim() + "…";
  return t || null;
}

export function youtubeVideoId(url) {
  let u;
  try { u = url instanceof URL ? url : new URL(url); } catch { return null; }
  const host = u.hostname.toLowerCase();
  const parts = u.pathname.split("/").filter(Boolean);
  const valid = (s) => (/^[A-Za-z0-9_-]{11}$/.test(s || "") ? s : null);
  if (host === "youtu.be" || host.endsWith(".youtu.be")) return valid(parts[0]);
  if (!(host === "youtube.com" || host.endsWith(".youtube.com") || host.endsWith("youtube-nocookie.com"))) return null;
  const v = u.searchParams.get("v");
  if (v) return valid(v);
  if (parts.length >= 2 && ["shorts", "embed", "live", "v"].includes(parts[0])) return valid(parts[1]);
  return null;
}

export function sourceKey(url) {
  const id = youtubeVideoId(url);
  if (id) return `youtube:${id}`;
  try {
    const u = new URL(url);
    return `${u.hostname.toLowerCase().replace(/^www\./, "")}/${u.pathname.replace(/^\/+|\/+$/g, "")}`;
  } catch {
    return String(url);
  }
}
