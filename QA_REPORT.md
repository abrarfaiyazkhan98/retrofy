# Retrofy QA Report

Branch `release/qa-polish` (on top of `feature/artwork-glow` and
`fix/playlist-track-accuracy`), 2026-10-23. Nothing pushed or published.

## Executive summary

- **Release candidate:** 1.0.0+ (unreleased changes in `CHANGELOG.md`).
- **Assessment:** automated suite green. The Champion playlist bug was
  reproduced on a real device, its root cause found and fixed, and the fix
  verified on the device. Layout, boot screen, icon, Music sources, whole
  artwork and Ambient Mode verified on the device. Lifecycle and
  connectivity scenarios are **not yet executed** (the device disconnected
  mid-session).
- **Recommendation:** NOT READY (see Final verdict).

## Environment

- Device: Samsung Galaxy S25 Ultra (SM-S938U1), Android, USB debugging.
- Flutter 3.47.6, JDK 21, AGP 9.1, release build flavor `production`.
- Real-device checks below are marked **device**; everything else ran in
  `flutter test` (host).

## Test results

| Suite | Executed | Passed | Failed | Skipped | Blocked |
|---|---|---|---|---|---|
| `flutter test` (unit + widget), final run | 353 | 353 | 0 | 0 | 0 |
| `flutter analyze` | 1 | 1 (no issues) | 0 | 0 | 0 |
| Release APK build + install (device) | 1 | 1 | 0 | 0 | 0 |
| Manual device scenarios (Phase 3 list of 20) | 8 | 8 | 0 | 0 | 12 |

Baseline before this work: 299 tests, all passing.

Manual device scenarios executed (all passed after fixes): repeated cold
starts; scrolling to the bottom of a long playlist and selecting tracks
(Champion, 14 selections across positions 0-53); rapid tapping (two rows
within milliseconds: the first wins, the second is ignored); switching
between Library and Spotify (remembered across relaunch and reinstall,
playback untouched); entering and leaving Ambient Mode; switching between
artwork and lyrics. Blocked (device disconnected): 20 rapid skips,
lock/unlock, app switching, headphones, Wi-Fi loss and restore, force
stop and reopen, rapid wheel navigation, empty playlists, expired Spotify
auth, long background use, low memory, rotation (portrait-locked app).

## Bug report

| ID | Severity | Summary | Status |
|---|---|---|---|
| RB-1 | P1 | Champion playlist: tapping a track near the bottom plays another track | Fixed, device-verified |
| RB-6 | P1 | Playback check accepted a stale or ignored request (Now Playing could name a track that was not playing) | Fixed, test-verified; seen on device before the fix |
| RB-8 | P2 | After Retrofy restarts while Spotify plays, Now Playing shows "No Music" | Fixed, test-verified; device check pending |
| RB-7 | P2 | Lyrics never follow the song when LRCLIB's exact entry is plain only | Fixed, test-verified; device check pending |
| RB-2 | P2 | White flash at launch in light mode | Fixed, device-verified |
| RB-3 | P2 | App startup failures retried silently (about 30 s) before showing Retry | Fixed, test-verified |
| RB-4 | P2 | Display only about a third of the screen height on tall phones | Fixed, device-verified |
| RB-9 | P2 | Album covers cropped in Now Playing and Ambient Mode | Fixed, device-verified |
| RB-5 | P3 | Release build fails when the repo is in iCloud-synced Desktop | Worked around |

**RB-1.** Repro (device, 2026-10-23): Music → Spotify → Playlists →
Champion, scroll to the bottom, tap "Good Life" (position 50): Spotify
started "Ginseng Strip 2002" (position 51). Bisection by tapping rows:
positions 0-32 correct, 33 onwards one track late, in both shuffle states
seen. Root cause: "Be Alright" (Tkandz, CT24; position 33) cannot be
played on the account. The Spotify app leaves unplayable tracks out of a
playlist context, but Retrofy listed it from the Web API (requested
without a market) and counted it, so every later row started the next
track. Confirmed from both sides: Spotify would not play the track even on
its own, and the Web API with `market=from_token` marks exactly this one
track `is_playable: false`. Fix: list requests pass `market=from_token`
and leave unplayable tracks out, numbering positions as the app does.
Device verification after the fix: Right Above It, Quebec, Power Trip,
Good Life, WAIT FOR U (last), Change, and a re-tap of the playing track
all played exactly, with no correction; Next continued through the
playlist. Regression tests: `unplayable tracks are left out and later
positions follow the app`, `album and liked tracks ask for playability
too`, `spotify_selection_accuracy` (1-500 track playlists).

**RB-6.** Seen on device: when the tapped track was already playing,
Spotify repeated the old track once before switching, and the check took
that as success; when Spotify ignored a request without reporting, the
check accepted it and Now Playing named the requested track. Fix: the
check notes the track playing before each request, waits for Spotify to
settle when they match, and judges ignored requests by what is playing.
Tests: `Spotify ignoring the direct request is reported`, `re-tapping
the playing track waits for Spotify to settle`.

**RB-7.** Good Life (Graduation, 3:27) has only plain lyrics on LRCLIB's
exact entry; a same-length entry is synced. Fix: search for a synced entry
within two seconds of the track's length. Tests in `lyrics_sources`.

**RB-8.** Fix: Retrofy remembers that Spotify was played last and, on
start, reconnects to the Spotify app and mirrors it without starting
playback. Tests: `spotify_session_resume`.

**RB-9.** User report. Fix: the whole cover is shown (fit, not crop),
across the display's width at the top with the text below. Verified on
device with Graduation and Coming For The Game.

**RB-2.** Root cause: the light `LaunchTheme` drew `@android:color/white`.
Fix: black launch window in all themes plus an Android 12+ splash.
Verified by device screen captures during launch.

**RB-3.** Root cause: Riverpod 3 retries failing providers by default; the
spinner hid it. Fix: `retry: null` on app startup. Test:
`Displays Error Widget`.

**RB-4.** Root cause: fixed 300 px display height. Fix: `DeviceLayout`
gives the display 75% of the usable height with a minimum wheel size.
Tests: `device_layout`. Verified on device (display about 75%, wheel about
180 dp).

**RB-5.** iCloud creates `name 2.ext` conflict copies in `build/` (and once
restored a whole `build 2` folder), and R8 rejects duplicate classes.
Workaround: `build/` is a symlink to `~/Library/Caches/retrofy-build`.
Recommended: move the repository out of Desktop.

## Performance report

| Metric | Result | How |
|---|---|---|
| Cold start to first frame | 327, 192, 199, 152, 336, 189, 178 ms | `am start -W` TotalTime, device |
| Boot screen to menu | under 2 s with a cached library | screen captures, device |
| APK size | 76.9 MB (universal, 3 ABIs) | release build; per-ABI split would give about 25 MB for arm64 |
| Frame timing (glow, Ambient Mode) | not measured | needs a device session with `--dart-define=RETROFY_FRAME_STATS=true` |
| Memory, CPU, battery | not measured | needs a profiling session |

## Not implemented yet

- YouTube in-app video: plan only; needs a YouTube Data API key.
- Artwork glow on the regular Now Playing screen: waiting on a design
  decision (the cover currently fills the display).
- Audio-reactive glow: no legitimate data source in the current engines.

## Manual test steps

1. Install `app-production-release.apk` (`adb install -r`).
2. Champion: Spotify → Playlists → Champion; tap 3–4 tracks near the
   bottom with shuffle off, then on; note tapped vs playing. Capture with
   `adb logcat -s flutter:I | grep "Spotify started"`.
3. Lifecycle: play, lock 5 min, unlock; switch apps; force stop and reopen
   (session restored?).
4. Connectivity: Wi-Fi off during Spotify browsing and playback; restore.
5. Ambient Mode: Now Playing → options → Ambient Mode; toggle lyrics,
   swipe tracks, close; repeat 10 times.
6. Wheel: scroll fast through a 500+ song list; check no accidental
   selections.

## Final verdict

**NOT READY.** All known P0/P1 bugs are fixed and the Champion fix is
verified on the device, but 12 of 20 critical manual scenarios (lifecycle,
connectivity, long background use) have not been executed, and frame,
memory and battery measurements are still missing. Expected to move to
READY WITH KNOWN LIMITATIONS once those pass.
