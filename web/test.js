import assert from "node:assert/strict";
import { parseTracklist, parseLine, buildQuery, splitArtists, tokens, bestMatch, bestSetlist, cleanTitle, youtubeVideoId, soleURL } from "./setlist-core.js";

let passed = 0;
const test = (name, fn) => { fn(); passed += 1; };

test("soundcloud style description", () => {
  const s = parseTracklist(`Recorded live at Printworks, London.

Tracklist:
1. Kölsch - Grey
2. Bicep - Glue
3. ID - ID
4. Ben Böhmer - Beyond Beliefs (Extended Mix) [Anjunadeep]
5. Lane 8 feat. Fractures - Little Voices
w/ Bonobo - Cirrus (Acapella)

Follow me on Instagram`);
  assert.equal(s.entries.length, 6);
  assert.equal(s.entries[0].artist, "Kölsch");
  assert.equal(s.entries[2].isUnidentified, true);
  assert.equal(s.entries[3].label, "Anjunadeep");
  assert.equal(s.entries[3].title, "Beyond Beliefs (Extended Mix)");
  assert.equal(s.entries[5].isMashupContinuation, true);
  assert.equal(s.isLikely, true);
  assert.equal(s.searchable.length, 5);
});

test("timestamps", () => {
  assert.equal(parseLine("[00:00] Artist - Title", 1).timestamp, "00:00");
  assert.equal(parseLine("1:23:45 Artist - Title", 1).timestamp, "1:23:45");
  assert.equal(parseLine("12:30 - Artist - Title", 1).artist, "Artist");
  assert.equal(parseLine("Artist - Title @ 45:10", 1).timestamp, "45:10");
  assert.equal(parseLine("[00:00] 03. Artist - Title", 1).artist, "Artist");
  assert.equal(parseLine("0:00 Bicep - Glue", 1).artist, "Bicep");
});

test("indexes", () => {
  assert.equal(parseLine("01. Artist - Title", 1).artist, "Artist");
  assert.equal(parseLine("(7) Artist - Title", 1).artist, "Artist");
  assert.equal(parseLine("#12 Artist - Title", 1).artist, "Artist");
  assert.equal(parseLine("01:23 Artist - Title", 1).artist, "Artist");
  assert.equal(parseLine("2 Unlimited - No Limit", 1).artist, "2 Unlimited");
  assert.equal(parseLine("Jean-Michel Jarre - Oxygène, Pt. 4", 1).artist, "Jean-Michel Jarre");
});

test("unidentified variants", () => {
  for (const l of ["ID - ID", "id – id", "? - ?", "ID - ID (Kölsch Edit)", "Artist - ID", "ID - Known Title"]) {
    const e = parseLine(l, 1);
    assert.ok(e, l);
    assert.equal(e.isUnidentified, true, l);
  }
});

test("rejects prose", () => {
  assert.equal(parseLine("Thanks for listening, see you next time!", 1), null);
  assert.equal(parseLine("Mixed by DJ Someone", 1), null);
  assert.equal(parseLine("https://soundcloud.com/x/y", 1), null);
  assert.equal(parseLine("This was a great night - thanks to everyone.", 1), null);
  assert.equal(parseLine("Glue by Bicep", 1).artist, "Bicep");
});

test("normalizer", () => {
  let q = buildQuery("Ben Böhmer", "Beyond Beliefs (Extended Mix)");
  assert.equal(q.title, "Beyond Beliefs");
  assert.equal(q.remixTag, null);
  q = buildQuery("Bicep", "Glue (Kölsch Remix) [Ninja Tune]");
  assert.equal(q.remixTag, "Kölsch Remix");
  assert.equal(q.searchTerm, "Bicep Glue Kölsch Remix");
  q = buildQuery("Bicep", "Glue - Kölsch Remix");
  assert.equal(q.title, "Glue");
  assert.equal(q.remixTag, "Kölsch Remix");
  q = buildQuery("Someone", "Chapter 1 - The Beginning");
  assert.equal(q.title, "Chapter 1 - The Beginning");
  q = buildQuery("Lane 8 feat. Fractures", "Little Voices");
  assert.deepEqual(q.artists, ["Lane 8"]);
  assert.deepEqual(q.featured, ["Fractures"]);
  q = buildQuery("Ultravox", "Dancing With Tears In My Eyes");
  assert.equal(q.title, "Dancing With Tears In My Eyes");
  assert.deepEqual(splitArtists("Above & Beyond"), ["Above", "Beyond"]);
  assert.deepEqual(splitArtists("Camelphat x Elderbrook"), ["Camelphat", "Elderbrook"]);
  assert.deepEqual(splitArtists("Andhim"), ["Andhim"]);
  assert.deepEqual(splitArtists("Band of Horses"), ["Band of Horses"]);
  assert.deepEqual([...tokens("Kölsch – Grey!")], ["kolsch", "grey"]);
  assert.deepEqual([...tokens("Above & Beyond")], ["above", "and", "beyond"]);
});

test("scorer", () => {
  const c = (title, artists, id = "x") => ({ id, title, artists });
  const entry = (artist, title) => ({ id: 1, artist, title });
  let m = bestMatch(entry("Bicep", "Glue"), [c("Glue", ["Bicep"])]);
  assert.ok(m.score >= 0.95 && m.isConfident);
  m = bestMatch(entry("Bicep", "Glue"), [c("Glue - Kölsch Remix", ["Bicep", "Kölsch"], "remix"), c("Glue", ["Bicep"], "orig")]);
  assert.equal(m.candidate.id, "orig");
  m = bestMatch(entry("Bicep", "Glue (Kölsch Remix)"), [c("Glue", ["Bicep"], "orig"), c("Glue - Kölsch Remix", ["Bicep", "Kölsch"], "remix")]);
  assert.equal(m.candidate.id, "remix");
  assert.ok(m.isConfident);
  m = bestMatch(entry("Ben Böhmer", "Beyond Beliefs"), [c("Beyond Beliefs - Extended Mix", ["Ben Bohmer"])]);
  assert.ok(m.isConfident);
  m = bestMatch(entry("Bicep", "Glue"), [c("Apricots", ["Bicep"])]);
  assert.equal(m.isConfident, false);
  m = bestMatch(entry("Bicep", "Glue"), []);
  assert.equal(m.candidate, null);
});

test("youtube description beats truncated meta", () => {
  const desc = "Summer vibes & good times.\n\nTracklist:\n0:00 Bicep - Glue\n3:45 Kölsch - Grey\n7:10 Ben Böhmer - Beyond Beliefs\n11:00 ID - ID\n\nFollow me: https://instagram.com/x";
  const s = bestSetlist([desc, "Tracklist: 0:00 Bicep - Glue 3:45 ..."], { title: cleanTitle("Summer Mix 2024 - YouTube") });
  assert.equal(s.title, "Summer Mix 2024");
  assert.equal(s.entries.length, 4);
  assert.equal(s.entries[1].timestamp, "3:45");
  assert.equal(s.isLikely, true);
});

test("helpers", () => {
  assert.equal(cleanTitle("Boiler Room Set | Free Listening on SoundCloud"), "Boiler Room Set");
  assert.equal(youtubeVideoId("https://youtu.be/dQw4w9WgXcQ?si=abc"), "dQw4w9WgXcQ");
  assert.equal(youtubeVideoId("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10"), "dQw4w9WgXcQ");
  assert.equal(youtubeVideoId("https://m.youtube.com/shorts/dQw4w9WgXcQ"), "dQw4w9WgXcQ");
  assert.equal(youtubeVideoId("https://soundcloud.com/a/b"), null);
  assert.ok(soleURL(" https://soundcloud.com/a/b \n"));
  assert.equal(soleURL("check https://soundcloud.com/a/b"), null);
});

console.log(`${passed} test groups passed`);
