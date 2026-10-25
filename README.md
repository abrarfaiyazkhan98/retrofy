<div align="center">

# 🎵 Retrofy

An iPod Classic-inspired music player for Android, with a rotating click wheel,
Cover Flow and an immersive Now Playing screen. Retrofy plays your local music,
streams from Subsonic-compatible servers, and controls **Spotify Premium**
through the official Spotify app.

</div>

> **Based on [Classipod](https://github.com/adeeteya/Classipod) by Aditya R.**
> This product includes software developed by Aditya R.
>
> Retrofy is an independent personal project. It is not affiliated with,
> endorsed by, or sponsored by Aditya R, Spotify, Samsung, or Google.
> Spotify is a trademark of Spotify AB.

Retrofy targets Android (built and tested on a Samsung Galaxy S25 Ultra,
Android 17). The iOS, macOS, Windows, Linux and web projects inherited from
Classipod are kept but have not been tested with Retrofy's changes, and the
Spotify features are Android-only.

## ✨ What Retrofy adds

### 🎧 Spotify (Premium)

- **Sign in with Spotify** in the browser using OAuth 2.0 with PKCE. No Client
  Secret is ever included; tokens are stored in Android Keystore-backed
  secure storage and refreshed automatically.
- **Browse** your playlists, saved albums, followed artists and their albums,
  Liked Songs, Recently Played, and search, all in the iPod lists.
- **Play through the Spotify app** with the official Spotify App Remote SDK.
  The click wheel controls play/pause, previous/next, seeking, shuffle and
  repeat; Now Playing follows Spotify's track, progress and artwork.
- The first playback asks once for permission to control Spotify, from
  inside Retrofy.

### 🖼️ Immersive Now Playing

- The album cover fills the iPod screen, with a tinted overlay taken from the
  cover so text stays readable on any artwork.
- The progress bar picks up the cover's accent colour.
- Gentle crossfades between tracks; reduced motion is respected.

### 🎤 Synced lyrics

- Time-synced lyrics with the sung line highlighted and kept in view.
- Sources: lyrics embedded in your files, `.lrc` files next to local songs,
  and, for Spotify songs, [LRCLIB](https://lrclib.net) (community-contributed;
  credited on screen).

### 🎬 Watch Video

- From Now Playing (hold the centre button), **Watch Video** pauses playback
  and opens a YouTube search for the song's official video. Videos do not play
  inside Retrofy (see *Known limitations*).

### 🌙 Ambient Mode and battery

- Optional **Ambient Mode** (Settings, off by default): after 30 seconds
  without input while music plays, Now Playing turns into a black screen with
  a small cover. It keeps no wake lock and is not Samsung's Always On Display.
- Retrofy stops its timers when it is not visible, so it uses no measurable CPU
  in the background while Spotify plays.

### 🗃️ Everything from Classipod

Local music with Cover Flow, artists, albums, genres, playlists, ratings,
search, shuffle by song or album, repeat, sleep timer, themes, device colours,
click-wheel sounds and haptics, and Subsonic/Navidrome streaming.

### 🎵 Supported audio formats

Retrofy imports a format when its metadata can be read and at least one
configured playback backend can play it. Playback availability therefore varies
by platform:

| Format         | Extensions               | Expected playback                               |
|----------------|--------------------------|-------------------------------------------------|
| MP3            | `.mp3`                   | Android, iOS, Windows, Linux, web               |
| PCM WAV        | `.wav`                   | Android, iOS, Windows, Linux, web               |
| FLAC           | `.flac`                  | Android, iOS, Windows, Linux, major browsers    |
| AAC in MP4     | `.m4a`, `.mp4`           | Android, iOS, Windows, Linux, major browsers    |
| Ogg Vorbis     | `.ogg`                   | Android, Windows, Linux, supporting browsers    |
| Ogg Opus       | `.opus`                  | Android, Windows, Linux, supporting browsers    |
| Raw ADTS AAC   | `.aac`                   | Android, iOS, Windows, Linux; browser-dependent |
| AIFF / AIFF-C  | `.aif`, `.aiff`, `.aifc` | iOS, Windows, Linux                             |
| Monkey's Audio | `.ape`                   | Windows, Linux                                  |
| QuickTime      | `.mov`                   | iOS, Windows, Linux; browser-dependent          |

## 📲 Install on Android

1. Build the APK (see [Building](#-building)) or use one you built.
2. On the phone: **Settings → About phone → Software information**, tap
   **Build number** seven times, then enable **Developer options → USB
   debugging**.
3. Connect the phone and install:

   ```bash
   adb install -r Retrofy-1.0.0.apk
   ```

   Or copy the APK to the phone, open it and allow installs from that app.
4. For Spotify, install the Spotify app and log in to a Premium account.

## 🔑 Spotify setup

Spotify features need your own Spotify Developer app. Follow
**[docs/spotify-setup.md](docs/spotify-setup.md)**: register the package name
`com.abrarfaiyazkhan.retrofy`, your signing certificate's SHA-1, and the
redirect URIs `retrofy://spotify-callback` and `retrofy://spotify-app-remote`,
then put your Client ID in a git-ignored `spotify.config.json`
(see `spotify.config.example.json`). Without it the app builds and runs, and
the Spotify menu says **Spotify Not Configured**.

## 🛠️ Building

```bash
flutter pub get
flutter build apk --release --flavor production \
  --target-platform android-arm64 \
  --dart-define-from-file=spotify.config.json
```

Release signing reads `android/key.properties` (git-ignored); keep the keystore
and passwords outside the repository.

## ⚠️ Known limitations

- **Spotify Development Mode** (Spotify's rules since February 2026): the app
  owner needs Premium; up to five users; only playlists you own or collaborate
  on list their tracks (others offer Play and Shuffle Play); search returns at
  most 10 results; artist pages list albums only.
- Choosing a specific track requires Spotify Premium.
- **Video** plays in YouTube, not inside Retrofy: finding the official video
  ID requires the YouTube Data API with an API key, which Retrofy does not
  ship.
- **Always On Display:** Samsung's AOD and lock screen show Spotify's own media
  player; apps cannot add content to Samsung's AOD.
- Lyrics depend on community-contributed LRCLIB entries for Spotify songs;
  many songs have none.
- After a fresh launch, Now Playing shows Spotify's current song only after you
  play something from Retrofy.
- The sleep timer's "end of song" option applies to local and Subsonic
  playback only.
- Spotify content is not part of Cover Flow or the local Songs/Albums lists.

## 🧪 Testing

`flutter analyze` and `flutter test` (299 tests) pass. Real-device results and
every confirmed defect with its regression test are in
[docs/testing-report.md](docs/testing-report.md) and
[docs/regression-learning.md](docs/regression-learning.md).

## Connect to Subsonic or Navidrome

Open **Settings → Library Settings → Subsonic** and enter the server's base
URL (including any reverse-proxy path), username and password. Retrofy
supports token-authenticated Subsonic API 1.13+ servers, including Navidrome.
The connection is checked before saving. Native apps combine server and local music; Web shows
the server library instead of demo songs while enabled.

**Configure Subsonic** edits the connection or removes it. Turning Subsonic off
keeps its configuration and cache, hides its tracks, and stops server playback.
**Hide Local Music** shows only server music while Subsonic is enabled.
**Prevent Duplicate Tracks** hides matching filenames without deleting files.
Saved playlist entries remain available when the same server is reconnected.
**Refresh Library** fetches a new catalog; **Re-index** also clears cached
server artwork. Failed scans retain the previous catalog. Ratings and edits
stay in Retrofy and are not written back to the server.

Native passwords use OS secure storage. Web passwords last only until reload;
re-enter the password through Configure Subsonic or when starting playback.
Metadata and artwork are cached, but audio is streamed and requires a connection.
Server playlist synchronization and offline audio downloads are not included.

Web servers must allow CORS from the Retrofy origin. Browsers block HTTP
servers from an HTTPS app. Native apps allow HTTP for user-configured servers,
including LAN IP addresses, using app-wide Android and Apple transport
exceptions because server hosts are not known at build time. HTTPS certificates
are still validated. HTTP traffic is unencrypted; prefer HTTPS when available.
Transport configuration changes require rebuilding and reinstalling the app;
hot reload does not apply them.
Linux secure storage requires the system Secret Service/libsecret; Windows
builds require the Visual Studio ATL component used by flutter_secure_storage.

## 🔌 Plugins

| Name                                                                                          | Usage                                                                               |
|-----------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| [**audio_service**](https://pub.dev/packages/audio_service)                                   | To support background audio playback                                                |
| [**audio_service_mpris**](https://pub.dev/packages/audio_service_mpris) | Linux system media controls |
| [**audio_service_win**](https://pub.dev/packages/audio_service_win) | Windows system media controls |
| [**flutter_secure_storage**](https://pub.dev/packages/flutter_secure_storage) | Store native server credentials securely |
| [**http**](https://pub.dev/packages/http) | Connect to Subsonic-compatible servers |
| [**battery_plus**](https://pub.dev/packages/battery_plus)                                     | Shows phone battery level and status                                                |
| [**cupertino_icons**](https://pub.dev/packages/cupertino_icons)                               | For ios style icons                                                                 |
| [**device_preview_plus**](https://pub.dev/packages/device_preview_plus)                       | For visualizing how the app looks on different devices and screens                  |
| [**disable_battery_optimization**](https://github.com/adeeteya/Disable-Battery-Optimizations) | To Disable vendor or android specific battery optimizations for background playback |
| [**file_picker**](https://pub.dev/packages/file_picker)                                       | To select the directory from which the music files are scanned                      |
| [**flutter_localizations**](https://pub.dev/packages/flutter_localizations)                   | For in-app localization map data                                                    |
| [**flutter_riverpod**](https://pub.dev/packages/flutter_riverpod)                             | For State Management                                                                |
| [**flutter_taglib**](https://github.com/adeeteya/flutter_taglib)                               | To read local audio metadata and embedded artwork                                   |
| [**go_router**](https://pub.dev/packages/go_router)                                           | To handle routing within the app                                                    |
| [**hive_ce**](https://pub.dev/packages/hive_ce)                                               | To Cache Auio Metadata and store playlists                                          |
| [**hive_ce_flutter**](https://pub.dev/packages/hive_ce_flutter)                               | For flutter specific libs of hive                                                   |
| [**intl**](https://pub.dev/packages/intl)                                                     | For internalization and localization of the app                                     |
| [**just_audio**](https://pub.dev/packages/just_audio)                                         | To play audio files                                                                 |
| [**just_audio_media_kit**](https://pub.dev/packages/just_audio_media_kit)                     | To play audio files on Windows and Linux                                            |
| [**media_kit_libs_linux**](https://pub.dev/packages/media_kit_libs_linux)                     | Media kit Libraries for Linux                                                       |
| [**media_kit_libs_windows_audio**](https://pub.dev/packages/media_kit_libs_windows_audio)     | Media kit Libraries for Windows                                                     |
| [**on_audio_query**](https://github.com/adeeteya/on_audio_query)                              | To discover music through Android MediaStore                                   |
| [**path_provider**](https://pub.dev/packages/path_provider)                                   | To fetch app data directories                                                       |
| [**permission_handler**](https://pub.dev/packages/permission_handler)                         | To check and request for file and audio access permissions                          |
| [**shared_preferences**](https://pub.dev/packages/shared_preferences)                         | To store system settings                                                            |
| [**tutorial_coach_mark**](https://pub.dev/packages/tutorial_coach_mark)                       | To provide app tutorial to the users                                                |
| [**universal_html**](https://pub.dev/packages/universal_html)                                 | For Launching the app in full-screen mode on web versions                           |
| [**url_launcher**](https://pub.dev/packages/url_launcher)                                     | For opening links (Go to Artist, legal pages)                                                |
| [**vibration**](https://pub.dev/packages/vibration)                                           | Used for vibration while using device controls                                      |
| [**vibration_web**](https://pub.dev/packages/vibration_web)                                   | Used for vibration on the webapp version                                            |
| [**build_runner**](https://pub.dev/packages/build_runner)                                     | For code generation                                                                 |
| [**flutter_lints**](https://pub.dev/packages/flutter_lints)                                   | For using recommended flutter lints                                                 |
| [**flutter_test**](https://pub.dev/packages/flutter_test)                                     | For unit and widget testing the app                                                 |
| [**hive_ce_generator**](https://pub.dev/packages/hive_ce_generator)                           | For automatically generating Hive TypeAdapters                                      |
| [**riverpod_lint**](https://pub.dev/packages/riverpod_lint)                                   | For using riverpod specific linting rules                                           |

## 🤓 Authors

- **Retrofy changes:** [Abrar Faiyaz Khan](https://github.com/abrarfaiyazkhan98)
- **Original Classipod:** [Aditya R](https://github.com/adeeteya)

## 🔖 LICENCE

Copyright (c) 2025 Aditya R. Distributed under the
[BSD-4-Clause licence](LICENSE), which also covers Retrofy's changes.
This product includes software developed by Aditya R.

The bundled Spotify App Remote SDK (`android/app/libs`) is Copyright (c) 2015-2018
Spotify AB, licensed under the Apache License 2.0; see
`android/app/libs/LICENSE-spotify-android-sdk.txt` and
`android/app/libs/NOTICE-spotify-android-sdk.txt`.

## 🙏 Attributions

<a href="https://www.flaticon.com/free-icons/ipod" title="ipod icons">Ipod icons created by
Freepik - Flaticon</a>
