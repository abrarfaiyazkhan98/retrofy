# Retrofy 1.0.0 — testing report

Device: Samsung Galaxy S25 Ultra (SM-S938U1), Android 17, One UI 9.0,
Android System WebView 155. Spotify Premium account, official Spotify app.

Statuses: **Verified on device** (observed on the phone, usually checked
against Spotify's own media session), **Automated tests only**, **Not
tested**, **Not implemented**.

## Signed release 1.0.0 (R8, arm64)

Installed APK pulled back from the phone: byte-identical to the build,
signed by the release key (SHA-1 `A7:8C:53:F5:AA:73:B9:93:68:B7:11:C3:4C:F5:88:2E:A2:84:6F:C2`),
version 1.0.0 (28), cold start 222 ms.

| Check | Status |
| --- | --- |
| Sign in with Spotify after a fresh install | Verified on device |
| First approval and playback of a chosen song | Verified on device |
| Play/pause, next, previous | Verified on device |
| Background then return, controls still work | Verified on device |
| One media session (Spotify), no Retrofy notification | Verified on device |
| Crashes or process deaths during the session | None |

## Automated

- `flutter analyze`: no issues.
- `flutter test`: 299 tests, all passing on consecutive full runs.
- Key regression tests are listed with each defect in
  [regression-learning.md](regression-learning.md); each was shown to fail
  against the code it guards.

## Spotify

| Check | Status |
| --- | --- |
| Sign in with Spotify (browser, PKCE) | Verified on device |
| Playlists and library lists load | Verified on device |
| First playback approval (`app-remote-control`) then the chosen song plays | Verified on device |
| Play/pause, next, previous from the click wheel | Verified on device |
| Now Playing title, artist, album, artwork match Spotify | Verified on device |
| Background and reopen keep playback and progress in sync | Verified on device |
| Force-stop, cold start, play again without a new approval | Verified on device |
| Seek by scrubbing | Automated tests only |
| Shuffle and repeat changes | Automated tests only |
| Reconnect after Spotify drops the connection | Automated tests only |
| Token refresh and expired session | Automated tests only |
| Media key (Bluetooth/headset path) routes to Spotify | Verified on device |

## Now Playing, lyrics, video

| Check | Status |
| --- | --- |
| Cover fills the iPod screen, readable text, cover-tinted progress | Verified on device |
| Crossfade between tracks | Verified on device |
| Text contrast over white, black, saturated and grey covers | Automated tests only |
| Synced lyrics from LRCLIB, highlighted line matches Spotify's position | Verified on device |
| Lyrics from tags and `.lrc` files | Automated tests only |
| Watch Video pauses Spotify and opens the YouTube search; Back returns | Verified on device |
| Video inside the iPod screen | Not implemented (needs a YouTube Data API key) |

## Lock screen, AOD, ambient, battery

| Check | Status |
| --- | --- |
| Only Spotify's player in the notification shade (no duplicate) | Verified on device |
| Lock-screen media controls | Spotify's player; Verified on device (shade) |
| Always On Display music info | Verified on device: none shown, even for Spotify (phone's AOD configuration) |
| Ambient Mode appears after 30 s, tap returns, off by default | Automated tests only |
| Background CPU while Spotify plays | Verified on device: 840 ms/min before, 0 ms/min after |
| Battery discharge runs | Not tested (skipped by choice) |

## Performance (profile build, arm64)

| Metric | Result |
| --- | --- |
| Cold start (median of valid runs) | ~330–350 ms (debug build: 900 ms) |
| Hot start | ~45 ms |
| Menu and list scrolling | build p95 < 2.3 ms, raster p95 < 7.2 ms, none over 16.7 ms |
| Track change with artwork crossfade | raster p95 < 6.8 ms; about one frame over 8.3 ms per change |
| Memory on Now Playing vs main menu | ~490 MB PSS for both (renderer baseline; artwork adds none measurable) |
| APK (arm64, freshly packaged) | 59.8 MB profile build |

## Local music and Subsonic

| Check | Status |
| --- | --- |
| Local playback after Spotify (hand-back, controls go to local engine) | Automated tests only |
| Local file played and shown in the new Now Playing | Verified on device |
| Subsonic | Automated tests only (existing suite) |
