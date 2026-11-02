# DJ Sync Toggle

Share a DJ set from anywhere on your iPhone, flip one toggle, and the tracklist lands in Spotify or
Apple Music as a playlist.

Works with:

- **YouTube mixes** with the tracklist in the description ("bio") or in a pinned/top comment, shared straight from the YouTube app
- **SoundCloud** and **Mixcloud** sets with the tracklist in the description
- **Copied text** from 1001Tracklists, Instagram captions, Telegram, anywhere
- **Screenshots** of a tracklist (OCR on device)

```
Share sheet ─► detect tracklist ─► match each track ─► save playlist
   (URL / text /    SetlistCore         Spotify or          new playlist
    screenshot)     parser              Apple Music          + history
                        │                   ▲
                        └── Auto-sync ON ───┘   (OFF: review matches first)
```

## No Mac? Use the web version

`web/` is the same flow as a static web app, deployed to GitHub Pages at
**https://erisdothard.github.io/Dj-Sync-Toogle/**. It runs entirely in the browser: Spotify login
(PKCE, your own Client ID), YouTube description + comments through the Data API, Mixcloud through
its API, pasted text for everything else. A one-action iOS Shortcut ("Open URLs" with the shared
link appended to `?share=`) puts it in the share sheet; the page shows the steps. Spotify only,
since Apple Music on the web needs a paid developer token.

Test the parser with `node web/test.js`.

## How it works

1. The **share extension** receives a URL, text, or image.
2. `SetlistExtractor` turns it into text: YouTube through the Data API (if you add a key) or the
   page's embedded `shortDescription`; Mixcloud through its public API; other pages through their
   HTML; images through Vision OCR.
3. `TracklistParser` finds lines shaped like `03. [12:45] Artist - Title (Remix) [Label]`,
   handles `w/` mashups and `ID - ID`, and scores how likely the text really is a tracklist.
4. `TrackNormalizer` + `MatchScorer` search the catalog and pick the right version: remixes are
   matched to remixes, "Extended Mix" counts as the original, and anything under the confidence
   threshold is flagged "Unsure".
5. With **Auto-sync on**, the playlist is created immediately and you get a summary. With it off,
   you tick or untick matches, rename the playlist, and save.
6. Every sync is written to **History** (with the tracks that were not found) so you can retry later.
   Sharing the same set twice is detected.

## Project layout

| Path | What |
|---|---|
| `Packages/SetlistCore` | Pure Swift: parser, normalizer, matcher, HTML/JSON extractors. Tested with `swift test`, runs on macOS and Linux. |
| `Shared/` | iOS code compiled into both targets: settings, Keychain, Spotify + Apple Music clients, extraction, sync engine, the SwiftUI flow. |
| `App/` | The app: settings, Spotify login, Apple Music permission, "Try it" tester, history. |
| `ShareExtension/` | The share sheet entry point. Hosts the same flow view as the app. |
| `project.yml` | XcodeGen spec that generates `DJSyncToggle.xcodeproj`. |

## Setup

Requirements: macOS with Xcode 15 or newer, an Apple developer account (free for running on your
own device; paid for MusicKit / Apple Music), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/erisdothard/Dj-Sync-Toogle.git
cd Dj-Sync-Toogle
make generate            # creates Config/Secrets.xcconfig from the example and the .xcodeproj
open DJSyncToggle.xcodeproj
```

Then:

1. Put your Team ID in `Config/Secrets.xcconfig` (`DEVELOPMENT_TEAM`).
2. In Xcode, let automatic signing register both bundle IDs (`com.syntra.djsynctoggle` and
   `com.syntra.djsynctoggle.share`) and the app group `group.com.syntra.djsynctoggle`. Rename the
   prefix in `project.yml` and `Shared/AppGroup.swift` if you want your own.
3. **Apple Music**: enable the MusicKit app service for **both** App IDs in the developer portal.
   Library writes only work on a real device signed into Apple Music.
4. **Spotify**: see below.
5. Run on a device. Open the app, connect a service, then share a YouTube mix to "DJ Sync".

### Spotify: the 5-user reality

Spotify's Web API puts every new app in *development mode*: at most 5 allowlisted users, the app
owner must have Premium, and the only way out is a partner application that (per community
reports) requires an established product with hundreds of thousands of monthly users. Nothing an
indie app can meet.

So this app uses **bring-your-own Client ID**. Each user creates a free Spotify app for themselves
and pastes its Client ID into Settings; the app walks them through it. That keeps every user
inside Spotify's own rules (an app managing a single account) and needs no backend.

To create one: [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) → Create
app → Redirect URI `djsynctoggle://spotify-callback` → tick Web API → copy the Client ID.
The PKCE flow is used, so there is no client secret anywhere.

If you distribute a build to friends, you can also bake a default ID into `Secrets.xcconfig` and
add them to that app's allowlist (5 people max).

### YouTube

By default the description is read from the watch page's embedded player JSON. That works today
but is unofficial. For a stable, compliant path create a free **YouTube Data API v3** key in
Google Cloud, restrict it to the iOS bundle IDs, and paste it into Settings → Advanced (or
`YOUTUBE_API_KEY` in the xcconfig). One video costs 2 of the 10,000 free daily quota units
(description + comments). **Comments are only read with a key**: they are not part of the page
HTML, so without one only the description is checked.

## Testing

```bash
make test-core                        # parser / matcher unit tests, no Xcode needed
```

CI (`.github/workflows/ci.yml`) runs those tests and builds the full app for the iOS Simulator on
every push, so the project is known to compile even when the change was made without a Mac.

In the app, **Tools → Try it** runs the exact share-sheet pipeline on pasted text or a link.

## Known limitations

- **1001Tracklists** pages are Cloudflare-protected and have no public API, so links are not
  fetched. Copy the tracklist text (or screenshot it) and share that instead.
- **SoundCloud** has no open API for new apps; the description is read from the page's embedded
  JSON. Private sets will not work.
- **Unreleased tracks ("ID - ID")** are listed but cannot be searched.
- **Apple Music** playlists created by apps are private and cannot be shared through the API, and
  the share extension cannot open the Music app directly (copy the link, or open from History).
- The share extension has roughly 120 MB of memory; very large screenshots are downscaled by iOS.
- Matching is title/artist based like every playlist tool. Version mistakes (original vs remix vs
  live) are the common failure; the review step and the "Unsure" badge exist for that reason.

## Roadmap

- Listen mode with ShazamKit for sets that have no tracklist at all
- Append to an existing playlist instead of creating one per set
- Android share target

## Alternatives considered

Trakd, setlist.id, DJ Set Analyzer and friends identify tracks by audio fingerprinting and keep
their own tracklist databases. Playlist converters (SongShift, Soundiiz, TuneMyMusic) move whole
playlists between services. None of them sit in the iOS share sheet, read a YouTube bio, and let
you decide per set whether to review or just save. That gap is what this project is for.
