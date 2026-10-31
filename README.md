# Cassette Player

A local-only music library for your phone. Import audio files you already have, and Cassette copies them into the app, reads their tags and cover art, and plays them, with lock-screen and headset controls and background playback.

## Privacy

- **No network.** The public release makes no network calls. Release Android builds don't even request the `INTERNET` permission.
- **Optional YouTube build.** A separate personal build (`--dart-define=YOUTUBE_IMPORT=true`) adds "Add from YouTube link", which talks to YouTube only to fetch the audio you ask for and saves it on the phone. It is never published to the Releases page. Downloading from YouTube breaks YouTube's Terms of Service; only save audio you have the right to (your own uploads, Creative Commons, or creator-permitted downloads).
- **No cloud backup.** On Android, `allowBackup` is off and data-extraction rules exclude everything from cloud backup and device-to-device transfer. On iPhone, the app's files are not shared through the Files app.
- Your music, library database and artwork live in app-private storage on the device. If you uninstall the app, they are deleted.

## Install on Android

1. On your phone, open the [latest release](https://github.com/Jihad3-15/cassette-player/releases/tag/latest) and tap **Cassette.apk**.
2. When Android asks, allow your browser to **install unknown apps**, then tap **Install**.

The APK is signed with a CI debug key. If an update won't install over the old version, uninstall the old one first. That also deletes your imported library.

## Install on iPhone (Sideloadly)

1. On a Mac or Windows PC, install [Sideloadly](https://sideloadly.io) and download **Cassette-unsigned.ipa** from the [latest release](https://github.com/Jihad3-15/cassette-player/releases/tag/latest).
2. Connect your iPhone, drag the IPA into Sideloadly, sign in with your Apple ID, and click **Start**.
3. On the iPhone, go to **Settings > Privacy & Security > Developer Mode**, turn it on, and restart when asked.
4. Go to **Settings > General > VPN & Device Management**, tap your Apple ID, and tap **Trust**.

Limits with a free Apple ID: the app **expires after 7 days** (re-sideload to renew; your data is kept if you install over the existing app), and you can have at most **3 sideloaded apps** at a time.

## How builds work

This repo contains only the Dart code. There are no `android/` or `ios/` folders. On every push and pull request, GitHub Actions (`.github/workflows/build.yml`):

1. Runs `tool/bootstrap_platforms.sh`, which generates `android/` and `ios/` with `flutter create` and then runs `tool/patch_platforms.py` to apply the app name, permissions, background-audio service, backup opt-out and iOS `Info.plist` keys.
2. Runs `flutter analyze`.
3. Builds a release APK (Ubuntu) and an unsigned iOS app (macOS), and packages the app as an IPA.
4. On pushes to `main`, it replaces the assets on the `latest` prerelease with `Cassette.apk` and `Cassette-unsigned.ipa`.

To build locally with Flutter installed, run `bash tool/bootstrap_platforms.sh`, then `flutter pub get`, then `flutter build apk --release`.

## Personal YouTube build

Every push also builds `Cassette-YouTube.apk` and `Cassette-YouTube-unsigned.ipa` with the YouTube feature switched on. They are attached to the workflow run in the Actions tab (signed-in GitHub users only), not to the public release. YouTube changes its systems often, so this feature will break from time to time until the extractor library is updated.
