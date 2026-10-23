# Spotify setup (Android)

Retrofy plays Spotify by remote-controlling the official Spotify app through
the Spotify App Remote SDK, and reads your library through the Spotify Web API.
Audio is never downloaded or decoded by Retrofy.

## Requirements

- An Android phone with the Spotify app installed and logged in.
- Spotify Premium for choosing individual tracks. Without Premium, the
  Play/Shuffle Play rows of albums and playlists still work, and since February
  2026 the owner of a Development Mode app must have Premium for it to work at
  all.

## 1. Create the app on the Spotify Developer Dashboard

1. Open <https://developer.spotify.com/dashboard> and create an app.
2. Under **Which API/SDKs are you planning to use?** select **Web API** and
   **Android**.
3. Add **both** redirect URIs exactly as written:

   ```
   retrofy://spotify-callback
   retrofy://spotify-app-remote
   ```

   The first is used for signing in. The second is used once, when Spotify
   asks you to let Retrofy control playback (Spotify's Android auth library
   requires its own redirect address).

4. Under **Android packages**, add:
   - Package name: `com.abrarfaiyazkhan.retrofy`
   - SHA-1 fingerprint of the certificate that signs your APK. For debug
     builds this is your local debug keystore:

     ```bash
     keytool -list -v -alias androiddebugkey -storepass android \
       -keystore ~/.android/debug.keystore | grep SHA1
     ```

     Add the release keystore's SHA-1 as well if you build release APKs.
5. Under **User Management**, add the Spotify account email you will sign in
   with (Development Mode allows up to five users).
6. Copy the **Client ID**. Do not copy or use the Client Secret: Retrofy uses
   PKCE and never needs it.

## 2. Configure the build

Create `spotify.config.json` in the repository root (it is ignored by Git):

```json
{
  "SPOTIFY_CLIENT_ID": "your 32 character client id"
}
```

Build with it:

```bash
flutter build apk --debug --flavor production \
  --dart-define-from-file=spotify.config.json
```

Without this file the app still builds and runs; the Spotify menu shows
"Spotify Not Configured".

## 3. First run

1. Open **Spotify → Sign In to Spotify**. The browser opens Spotify's login
   page; approve the requested permissions and you return to Retrofy.
2. The first time you play something, Retrofy shows "Connecting to
   Spotify…" and the Spotify app asks you to allow Retrofy to control
   playback. After you approve, the song you chose starts.

## Permissions requested

| Scope | Used for |
| --- | --- |
| `playlist-read-private` | Your private playlists |
| `playlist-read-collaborative` | Collaborative playlists |
| `user-library-read` | Liked Songs and saved albums |
| `user-follow-read` | Followed artists |
| `user-read-recently-played` | Recently Played |

Playback control (`app-remote-control`) is granted separately inside the
Spotify app.

## Signing out

**Spotify → Sign Out** deletes the stored tokens from the device. Spotify has
no token revocation endpoint for PKCE apps; to revoke access completely,
remove Retrofy at <https://www.spotify.com/account/apps/>.

## Known limitations

- Development Mode only lists items of playlists you own or collaborate on.
  Other playlists show Play and Shuffle Play rows only.
- Search returns at most 10 tracks, albums and artists (Development Mode
  limit).
- Artist pages list albums only; artist top tracks are unavailable to
  Development Mode apps.
- Recently Played and search results start a single track; Spotify then
  continues with its own autoplay.
- Lists load up to 2,000 items.
- Spotify follows the device volume, so the click wheel changes the system
  volume while Spotify plays, even with in-app volume mode selected.
- The sleep timer's "end of current song" option applies to local and
  Subsonic playback only; timed sleep pauses Spotify.
- Spotify content does not appear in Cover Flow or in the local Songs, Albums
  and Artists lists.
- Ratings given to Spotify tracks last for the current session only.
