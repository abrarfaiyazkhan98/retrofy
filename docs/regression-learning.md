# Regression learning

Confirmed defects found while bringing Spotify playback up on a real device
(Samsung Galaxy S25 Ultra, SM-S938U1). Each entry states what was verified and
how; anything not yet observed working on the phone says so.

Statuses: **Verified fixed** (seen working on the device), **Fixed, tests
only** (regression test proves it, not yet re-checked on the device),
**Superseded** (replaced by a later fix).

---

## 1. Sign-in rejected Spotify's genuine redirect

- **Status:** Verified fixed. After the fix the user signed in and saw their
  playlists.
- **Symptom:** After approving in the browser, the Spotify menu showed
  "Spotify sign in failed" and no library.
- **Reproduction:** Spotify → Sign In to Spotify → approve.
- **Root cause:** Spotify returns `retrofy://spotify-callback/?code=…` (with a
  `/` path) for the registered `retrofy://spotify-callback`. The redirect
  check compared paths exactly (`''` vs `'/'`).
- **Evidence:** logcat `Spotify redirect received: retrofy://spotify-callback/?`
  followed by `Spotify sign-in failed: redirect_mismatch`.
- **Files:** `lib/core/spotify/spotify_auth.dart` (`codeFrom`).
- **Fix:** Treat an empty path and `/` as the same; scheme, host, other paths
  and the `state` check still reject foreign redirects.
- **Regression test:** `spotify_auth_test.dart` "accepts the root path Spotify
  adds to the redirect" plus negative cases for other paths and hosts.
- **Prevention:** Unit tests for platform callbacks must use a value captured
  from a real device, not a hand-written guess.

## 2. Volume change on Now Playing threw a provider cycle

- **Status:** Fixed, tests only.
- **Symptom:** Turning the click wheel on Now Playing (volume) did nothing.
- **Root cause:** `appVolumeActiveProvider` watches the settings controller,
  and the settings controller read that provider back
  (`CircularDependencyError`).
- **Evidence:** logcat `CircularDependencyError … Provider<bool>` from
  `SettingsPreferencesControllerNotifier.increaseVolume`.
- **Files:** `lib/features/settings/controller/settings_preferences_controller.dart`.
- **Fix:** The controller computes the condition from its own state.
- **Regression test:** `test/unit_tests/features/settings/app_volume_test.dart`
  fails with the same error on the old code and passes now.
- **Prevention:** A notifier must never read a provider derived from itself;
  cover new derived providers with a test that keeps them alive.

## 3. Spotify's built-in approval screen was blocked by Android

- **Status:** Superseded by #4.
- **Symptom:** Selecting a song did nothing; no approval screen appeared.
- **Root cause:** With `showAuthView(true)` the Spotify app opens its approval
  activity from the background, which current Android blocks.
- **Evidence:** logcat `Background activity launch blocked! … callingPackage:
  com.spotify.music … AuthorizationActivityInternalProxy`.
- **Fix:** Connect with `showAuthView(false)`; on `UserNotAuthorizedException`
  request `app-remote-control` through Spotify's Android auth library from
  Retrofy's foreground activity, then connect again.

## 4. Approval crashed Retrofy, which restarted on the home screen

- **Status:** Verified fixed on the device (2026-10-23).
- **Symptom:** Select song → Spotify approval → back in Retrofy on the home
  screen, no music.
- **Root cause:** Spotify auth library 5.0.0 requires its
  `RedirectUriReceiverActivity` to declare an intent filter for the redirect
  URI it is given and throws in `LoginActivity.onCreate` otherwise. The
  uncaught exception killed the process; Android relaunched Retrofy fresh,
  losing the pending song.
- **Evidence:** logcat `FATAL EXCEPTION … IllegalStateException: No
  intent-filter found for RedirectUriReceiverActivity matching redirect URI
  'retrofy://spotify-callback'` at `LoginActivity.kt:101`, then `Process
  com.abrarfaiyazkhan.retrofy (pid 776) has died: fg TOP` and a new process.
  Reproduced twice (pids 776, 2167).
- **Files:** `android/app/src/main/AndroidManifest.xml`,
  `SpotifyRemoteBridge.kt`, `spotify_config.dart`, `spotify_remote.dart`,
  `spotify_playback_controller.dart`, `docs/spotify-setup.md`.
- **Fix:** The library gets its own redirect, `retrofy://spotify-app-remote`,
  declared on its receiver, so it never competes with sign-in's
  `retrofy://spotify-callback`. Before launching the library, the bridge runs
  the same check and reports an error instead of crashing. The URI must be
  registered on the Spotify dashboard.
- **Regression test:** `test/unit_tests/android/spotify_manifest_test.dart`
  (fails on the old manifest); `spotify_playback_test.dart` asserts the new
  redirect reaches the native connect call.
- **Verification:** With `retrofy://spotify-app-remote` registered, the phone
  resolved each redirect to exactly one activity (`cmd package
  query-activities`). The user selected a song and approved; logcat showed
  `App Remote connection failed: not_authorized` → `START_AUTH_FLOW` in the
  Spotify app → `App Remote approval result: code`, all in one process with no
  crash, and Spotify's media session reported PLAYING. After a force-stop and
  cold start, a song chosen only with the click wheel played without a new
  approval prompt and Now Playing matched Spotify's track and artwork.
- **Prevention:** Read a dependency's breaking-change notes before upgrading;
  never infer a library's requirements from the absence of manifest entries.

## 5. A leftover redirect at startup showed a valid session as signed out

- **Status:** Fixed, tests only.
- **Symptom:** After the crash in #4, the Spotify menu showed "Spotify sign in
  failed" and a Sign In row although a token was stored.
- **Root cause:** On a cold start the pending redirect was processed before
  the saved token was loaded and, finding no sign-in attempt, was reported as
  a failure.
- **Evidence:** logcat `Spotify redirect pending at startup` then `Spotify
  sign-in failed: no pending sign-in` in a freshly started process.
- **Files:** `lib/core/spotify/spotify_auth_controller.dart`.
- **Fix:** Load the saved session first; ignore redirects with no pending
  attempt.
- **Regression test:** `spotify_auth_controller_test.dart` "a leftover
  redirect at startup keeps the saved session" and "a stray redirect while
  signed out is not shown as a failure" (both fail on the old code).

## 6. First play could time out during approval and repeat on extra taps

- **Status:** Fixed; the single first-approval play was observed on the
  device, the repeat-tap guard and long-approval timeout are covered by tests
  only.
- **Root cause (code inspection):** The connect timeout was 60 s, shorter
  than a user may spend on the approval screen; the track list accepted new
  selections while a request was waiting and gave no feedback.
- **Fix:** 3-minute connect timeout; a "Connecting to Spotify…" row; further
  selections are ignored until the request finishes; the request continues
  after approval exactly once.
- **Regression tests:** `spotify_playback_test.dart` "the chosen track plays
  exactly once after approval"; `spotify_screens_test.dart` "repeated taps
  while connecting send one request".

---

## Device checks of existing controls (2026-10-23, Spotify playing)

Observed by comparing Spotify's media session before and after each
click-wheel press on the phone:

| Action | Result |
| --- | --- |
| Play/pause | PLAYING → PAUSED → PLAYING, position kept |
| Next / previous | moved to the next and previous tracks |
| Open Now Playing | title, artist, album, artwork and progress matched Spotify |
| Home, wait 10 s, reopen | same process; progress and controls still in sync |
| Force-stop, cold start, play from Playlists | played without a new prompt |

Not yet checked on the device: volume via the wheel during Spotify playback
(#2), scrubbing (seek), shuffle/repeat changes, screen lock.

---

## 7. Two music players on the lock screen while Spotify played

- **Status:** Verified fixed on the device.
- **Symptom:** With a Spotify song started from Retrofy, Retrofy's media
  session stayed `active=true` with a paused local track and its
  `classipod` media notification stayed posted beside Spotify's player.
- **Root cause:** Handing playback to Spotify paused the local engine;
  `audio_service` keeps a paused session and its notification.
- **Evidence:** `dumpsys media_session` (Retrofy `active=true`,
  `PAUSED`, stale local track) and `cmd notification list`.
- **Files:** `lib/core/services/audio_player_service.dart`.
- **Fix:** Stop (idle) the local engine instead of pausing it.
- **Regression test:** `spotify_playback_test.dart` asserts the handler is
  idle after Spotify takes over (fails with the old `pause()`).
- **Verification:** On the phone, Retrofy's session became `active=false`
  and only Spotify's notifications were live.

## 8. Lyrics lookup failed once on the phone

- **Status:** Mitigated; exact cause not confirmed.
- **Symptom:** No lyrics page; log `Lyrics lookup failed: HttpException`.
- **Evidence:** The same request returned 200 from the Mac five times. The
  log did not record the status code, so the phone's response is unknown.
- **Fix:** Log the status code; retry once on 503/429 honouring
  `Retry-After` (LRCLIB's server source sheds load with 503 +
  `Retry-After: 1`). After this the lookup succeeded on the device.
- **Regression test:** `lyrics_test.dart` "one retry after LRCLIB sheds
  load".
- **Prevention:** Error logs must include the status code (no personal
  data) so a single failure is diagnosable.

## 9. Flaky test: failed restored remote song starts fresh

- **Status:** Fixed (pre-existing since the first baseline).
- **Root cause:** The test read a Hive checkpoint after a fixed 10 ms
  delay; under the parallel suite the disk write took longer.
- **Fix:** Wait for the checkpoint condition (2 s cap) instead of sleeping.
- **Verification:** Three consecutive full-suite runs passed.

## 10. APK size grew between builds (105 → 136 MB)

- **Status:** Explained; not an app-size problem.
- **Root cause:** Incremental packaging updates the APK in place and leaves
  dead space: entries compressed to 42.8 MB inside a 100.6 MB file.
- **Fix:** Delete the previous APK before release-style builds and build
  arm64-only for this phone: 59.7 MB.

## 11. Spotify progress ticker ran without listeners

- **Status:** Fixed, tests only.
- **Root cause (code inspection):** The 500 ms ticker ran whenever Spotify
  played, even in the background with nothing displaying progress.
- **Fix:** Start it only while the progress bar or lyrics listen.
- **Regression test:** `spotify_playback_test.dart` "the progress ticker
  runs only while something listens".

## 12. Retrofy used CPU in the background while Spotify played

- **Status:** Verified fixed on the device.
- **Symptom:** With Spotify playing and Retrofy backgrounded (Now Playing
  last open), Retrofy used 840 ms of CPU per minute.
- **Root cause (code + measurement):** Dart `Timer.periodic` timers keep
  firing in the background: the Spotify progress ticker (500 ms, its
  progress bar stays subscribed) and `MarqueeText` (50 ms) whose scroll
  animation stalls off screen, so each tick woke the app for nothing.
- **Evidence:** `/proc/<pid>/stat` user+system time over 60 s.
- **Files:** `spotify_playback_controller.dart`, `marquee_text.dart`.
- **Fix:** The ticker stops when the app is hidden and emits a fresh
  position on return; marquee timers pause when the app is not resumed or
  their route is covered (`TickerMode`).
- **Regression test:** `spotify_playback_test.dart` "the progress ticker
  stops while Retrofy is in the background".
- **Verification:** Same conditions after the fix: 0 ms per minute
  backgrounded (below the 10 ms accounting tick); 230 ms per minute with
  the phone locked during a track change; visible use unchanged (~2 s/min).

## Device facts (Galaxy S25 Ultra, Android 17, One UI 9.0)

- Media buttons (`KEYCODE_MEDIA_PLAY`, the Bluetooth/headset path) are
  routed to Spotify's session and resumed playback.
- The notification shade showed exactly one player (Spotify's).
- With Spotify playing, the Always On Display showed no music
  information. Spotify owns the media session, so this is the phone's AOD
  configuration; third-party apps cannot draw on Samsung's AOD.
- In-app video was not built: the official way to find a video ID is the
  YouTube Data API, which needs a key the user chose not to create. The
  embedded player itself (IFrame API in a WebView with an app-ID Referer)
  would otherwise be permitted.

---

## 13. Release build: "Install the Spotify app" although Spotify was installed

- **Status:** Verified fixed on the device (signed release 1.0.0).
- **Symptom:** In the R8-shrunk release, selecting a song showed "Install
  the Spotify app" above the playlist; debug and profile builds worked.
- **Root cause:** App Remote finds Spotify by reflection
  (`Class.forName("…ReleaseSpotifyLocator").getConstructor().newInstance()`).
  The SDK's consumer rule keeps only the class name; R8 full mode removed the
  unreferenced constructor, so `isSpotifyInstalled()` returned false.
- **Evidence:** Spotify installed and visible (`queriesPackages`); `dexdump`
  of the release APK showed `ReleaseSpotifyLocator` without `<init>`;
  bytecode of `SpotifyLocator` shows the reflective lookup.
- **Files:** `android/app/proguard-rules.pro`.
- **Fix:** Keep the locators' constructors and members and the
  `PackageProvider` interface. No other reflection exists in either Spotify
  library (checked by bytecode scan).
- **Regression test:** `test/unit_tests/android/release_build_rules_test.dart`.
- **Verification:** On the phone the release played, paused, skipped, and kept
  working after backgrounding.

## 14. Release build: Spotify error classes renamed by R8

- **Status:** Fixed; verified indirectly (release playback works).
- **Root cause:** The Kotlin bridge mapped errors by
  `javaClass.simpleName`; R8 renamed all nine App Remote exception classes,
  which would have turned the first-time approval into an "unknown" error.
- **Fix:** Match by type (`is UserNotAuthorizedException`).
- **Regression test:** `release_build_rules_test.dart`.

## 15. Release build failed: missing Jackson classes

- **Status:** Fixed.
- **Root cause:** App Remote ships optional Jackson mappers; Retrofy uses its
  Gson mapper and does not bundle Jackson.
- **Fix:** R8's generated `-dontwarn` rules for exactly those classes.
- **Prevention (13–15):** Test the shrunk release build on a device before
  publishing; debug and profile builds do not run R8.
