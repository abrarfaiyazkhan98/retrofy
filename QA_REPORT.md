# Retrofy QA Report

Branch `release/qa-polish` (on top of `feature/artwork-glow` and
`fix/playlist-track-accuracy`), 2026-10-23. Nothing pushed or published.

## Executive summary

- **Release candidate:** 1.0.0+ (unreleased changes in `CHANGELOG.md`).
- **Assessment:** automated suite green; the new layout, boot screen and
  icon verified on a real device; the reported Champion playlist bug has a
  safety net but its root cause is **not yet reproduced**; most manual
  lifecycle and connectivity scenarios are **not yet executed**.
- **Recommendation:** NOT READY (see Final verdict).

## Environment

- Device: Samsung Galaxy S25 Ultra (SM-S938U1), Android, USB debugging.
- Flutter 3.47.6, JDK 21, AGP 9.1, release build flavor `production`.
- Real-device checks below are marked **device**; everything else ran in
  `flutter test` (host).

## Test results

| Suite | Executed | Passed | Failed | Skipped | Blocked |
|---|---|---|---|---|---|
| `flutter test` (unit + widget), final run | 341 | 341 | 0 | 0 | 0 |
| `flutter analyze` | 1 | 1 (no issues) | 0 | 0 | 0 |
| Release APK build + install (device) | 1 | 1 | 0 | 0 | 0 |
| Manual device scenarios (Phase 3 list of 20) | 3 | 3 | 0 | 0 | 17 |

Baseline before this work: 299 tests, all passing.

Manual device scenarios executed: cold start (4 launches), boot sequence
frames, main layout proportions. The other 17 (rapid track selection on
long playlists, source switching, 20 rapid skips, lock/unlock, app
switching, headphones, Wi-Fi loss and restore, force stop, Ambient Mode
cycling, lyrics toggling, rapid wheel navigation, empty playlists, expired
Spotify auth, long background use, low memory, repeated cold/warm starts)
are **blocked** on hands-on device time; see Manual test steps.

## Bug report

| ID | Severity | Summary | Status |
|---|---|---|---|
| RB-1 | P1 | Champion playlist: tapping a track near the bottom sometimes plays another track | Safety net shipped; root cause unconfirmed |
| RB-2 | P2 | White flash at launch in light mode | Fixed, device-verified |
| RB-3 | P2 | App startup failures retried silently (about 30 s) before showing Retry | Fixed, test-verified |
| RB-4 | P2 | Display only about a third of the screen height on tall phones | Fixed, device-verified |
| RB-5 | P3 | Release build fails when the repo is in iCloud-synced Desktop | Worked around |

**RB-1.** Repro: Spotify → Playlists → Champion, tap a track near the
bottom. Not yet reproduced by us. Code path: the row's Web API playlist
position is sent to the Spotify app (`skipToIndex`); nothing checked what
Spotify then played. Candidate causes (unverified): Spotify's shuffle state,
or playlist entries the Spotify app skips (local files, episodes,
unavailable tracks) shifting later positions. Fix: after every tap Retrofy
waits for Spotify's player state; a different track is replaced by the
tapped track on its own; if Spotify still plays another track the row shows
"Spotify played a different song". Mismatches are logged (`Spotify started X
instead of Y`) for diagnosis. Regression tests:
`spotify_selection_accuracy` (1–500 track playlists, first/middle/last,
corrected contexts, refused tracks, shuffle, stale reports, playlist
switching). Limitation: when corrected, the song plays without its playlist
context until the root cause is known.

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

**RB-5.** iCloud creates `name 2.ext` conflict copies in `build/`, and R8
rejects duplicate classes. Workaround: `build/` is a symlink to
`~/Library/Caches/retrofy-build`. Recommended: move the repository out of
Desktop.

## Performance report

| Metric | Result | How |
|---|---|---|
| Cold start to first frame | 327, 192, 199, 152 ms | `am start -W` TotalTime, device |
| Boot screen to menu | under 2 s with a cached library | screen captures, device |
| APK size | 76.9 MB (universal, 3 ABIs) | release build; per-ABI split would give about 25 MB for arm64 |
| Frame timing (glow, Ambient Mode) | not measured | needs a device session with `--dart-define=RETROFY_FRAME_STATS=true` |
| Memory, CPU, battery | not measured | needs a profiling session |

## Not implemented yet

- YouTube in-app video: plan only; needs a YouTube Data API key.
- Artwork glow on the regular Now Playing screen: waiting on a design
  decision (the cover currently fills the display).
- Music source switch inside Music (Spotify still a main menu row).
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

**NOT READY.** RB-1 (P1) is mitigated but its root cause is unconfirmed,
and 17 of 20 critical manual scenarios have not been executed.
