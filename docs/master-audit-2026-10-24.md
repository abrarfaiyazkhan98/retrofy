# Retrofy master audit and redesign — 2026-10-24

Branch `feature/oled-now-playing-redesign` (from `release/qa-polish`).
Device: Samsung Galaxy S25 Ultra (SM-S938U1), release build, flavor
`production`, Spotify Premium account, Sony WH-1000XM6 over Bluetooth.

## 1. Audit

**Stack.** Flutter 3.47.6 (Dart), Riverpod 3, go_router, Hive CE,
just_audio + audio_service for local/Subsonic files. Spotify: Web API
(PKCE, read-only) for browsing and the official Android App Remote SDK
(Kotlin `SpotifyRemoteBridge`) to control the Spotify app, which decodes all
audio. Lyrics: embedded tags, `.lrc` files, LRCLIB for Spotify tracks.

**Playback state.** One process-wide source per engine, independent of the
activity: `SpotifyPlaybackController` mirrors App Remote player-state
events (no polling; a 500 ms progress ticker runs only while a progress bar
or lyrics listen and the app is visible), `LibraryAudioHandler` for local
files, and `nowPlayingDetailsProvider` exposes the current track to every
screen. MainActivity declares `configChanges` for size, orientation and
layout, so split screen, resizing and rotation never recreate it; the
audio_service engine is cached, so even recreation keeps Dart state.

### Confirmed bugs, root causes and fixes

| # | Bug (how found) | Root cause | Fix |
|---|---|---|---|
| A1 | Split Screen Mode preview said "No Music" while Spotify played (device) | The Music preview only drew random **local** covers and fell back to "No Music" without a library | Fall back to the playing cover; Now Playing preview shows the real cover |
| A2 | Now Playing said "No Music" for a Spotify session resumed after restart (device) | Screen tested `metadataList.isEmpty`; a resumed session has a track but no listed queue | Test `currentMetadata == null` |
| A3 | Android split screen: title and progress drawn over the cover (device) | Cover laid out at full width with the text overlaid; screens got a size derived from the **window** (`width - 50`), not the display | Window-driven Now Playing geometry; display reports its own size |
| A4 | Shuffle Songs silent for Spotify users (code) | Always shuffled the local library and paused Spotify first | Shuffle My Music uses Spotify Liked Songs when Spotify is the source |
| A5 | Shuffle My Music repeated the same track (device) | App Remote `play()` of the context already playing keeps the current track | Skip to the next shuffled track when the track did not change |
| A6 | Lyrics stayed "unavailable" after one LRCLIB 503 (device) | Failures were not cached but never retried while shown | Retry every 30 s while the track is on screen |
| A7 | 360×220 window overflowed by 17 px (widget test) | Panel beside the cover could get narrower than its progress row | Panel keeps at least 240 dp |
| A8 | Licence notice missing from the app (code) | The repository licence is 4-clause BSD (Aditya R), whose clause 2 needs the notice in binaries | Settings › Legal registers it on the licence page |

### Architectural notes

- Single authoritative state already existed per engine; this work removed
  places that second-guessed it (A2) and added nothing that competes with
  Spotify's own queue: Spotify shuffles contexts itself.
- Artist identity: App Remote reports artist URIs; they are now carried
  with names so Go to Artist never searches by name. Web API `tracks/{id}`
  is the fallback.
- Regression risks: `NowPlayingPanel` replaces `NowPlayingWidget`; the
  ambient screen is unchanged. Device Color and Donate settings are removed
  (old preference values are simply ignored).

## 2. Implemented changes

- **OLED device**: `DeviceStyle.oledBlack` (#000000 body, no gradient,
  noise or shadows; wheel #212122, centre button keeps its shading). Device
  Color setting and its screen removed.
- **About → Settings › Legal**; **Donate removed** (user request).
- **Now Playing**: cover + album-coloured panel (`ArtworkPalette.panel`,
  cached per cover, implicit 450 ms colour transition, zero with reduced
  motion, ≥ 7:1 white-text contrast), title, artist · album, live lyrics,
  progress, Go to Artist. `NowPlayingGeometry` picks portrait / side-by-side
  and drops lyrics, then the cover, before any control.
- **Lyrics in Now Playing**: synced follow, plain scroll, "Lyrics
  unavailable for this track."; wheel scroll in lyrics mode, select or label
  tap returns to the sung line; touch drag pauses following.
- **Go to Artist** (`lib/features/now_playing/artist/`): Spotify app via
  `spotify:artist:<id>`, browser fallback, picker for several artists,
  library browse for local tracks. Replaces Browse Album/Artist.
- **Shuffle My Music**; **Match Your Mood** (`lib/features/mood/`): moods
  and tempos, `TrackFeatureSource` abstraction, labelled match basis.
- Native bridge: `artistUris`, `queue`.

## 3. Spotify limitations (verified)

- `GET /v1/audio-features` returns **HTTP 403** for Retrofy's client ID
  (seen on the device, 17:30:48). Audio features and recommendations were
  closed to apps created after 27 Nov 2024. Retrofy therefore has **no BPM,
  energy or valence data**: Tempo is never matched for Spotify music, and
  moods use playlist names (labelled) or a labelled Liked Songs fallback.
- Development Mode: playlist items are only listed for playlists the user
  owns or collaborates on; others still play as a whole (no preview).
- Track choice and `queue` need Premium; free accounts can still shuffle
  Liked Songs and playlists (contexts).
- Lyrics: LRCLIB community lyrics with attribution; Spotify's own lyrics are
  not available to third-party apps and are not scraped.
- Local files are not analysed for BPM, so library tempo matching is
  unavailable (shown as such).

## 4. Test results

| Suite | Executed | Passed | Failed |
|---|---|---|---|
| `flutter test` (unit + widget), final | 411 | 411 | 0 |
| `flutter analyze` | 1 | no issues | 0 |
| Release APK build | 1 | 1 | 0 |

Baseline before this work: 353 tests, all passing. New tests: OLED body,
display size, split-screen preview, Now Playing geometry (10 window sizes),
panel contrast, redesign widget tests (resumed session, lyrics, missing
lyrics, Go to Artist, five split-screen sizes, resize without restart),
artist links and fallback, Shuffle My Music (5), mood engine (14), mood
preview (3), lyrics retry.

**Device (executed, passed):** OLED body; Split Screen Mode previews;
Now Playing redesign with live synced lyrics and album-coloured panel;
Go to Artist picker and the Spotify artist page (Lil Tjay) opened in the
Spotify app; Android split screen enter, resize and exit with the same
track and no restart; Next and play/pause in split screen; background →
foreground; Match Your Mood (Chill → labelled Liked Songs fallback →
Start → Spotify plays, Now Playing in sync); Shuffle My Music (after A5);
"Lyrics unavailable" message; Legal › licences page.

**Not executed:** lock/unlock (device PIN), rotation (app is
portrait-locked by design), battery saver, process death, network loss,
expired token on device, free-account behaviour on device, integration
tests (`integration_test` is not set up in this repo).

## 5. Performance

- Removed four 100 px blur box shadows drawn every frame behind the device.
- Palette extraction stays cached (48 covers, 24 px thumbnails).
- Lyrics follow the existing event stream; no new timers except a one-shot
  30 s lyrics retry while a failed track is visible.
- Match Your Mood's first run pages all Liked Songs (about 10 s on this
  account); later runs reuse the cached list. No frame metrics were taken.

## 6. Remaining issues

- **Unattributed Spotify pauses on the device** (17:32:21, 17:33:25, 17:39:56,
  17:40:15). Retrofy made no audio-focus request and sent no pause; one
  happened while Spotify was in front. A Sony WH-1000XM6 was connected
  (wear detection / Speak-to-Chat pause playback). Not fixed, not proven.
- Mood previews for fallbacks show a sample; Spotify's shuffle picks the
  actual order.
- The status bar of the display follows the app theme (light grey in the
  light theme) rather than the reference's black.

## 7. Build

`flutter build apk --release --flavor production -t lib/main.dart
--dart-define-from-file=spotify.config.json` →
`build/app/outputs/flutter-apk/app-production-release.apk` (78.7 MB). Install
with `adb install -r <apk>`.
