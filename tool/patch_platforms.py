#!/usr/bin/env python3
"""Apply Cassette's platform configuration to the generated android/ and ios/
folders (created by `flutter create` in tool/bootstrap_platforms.sh).

Idempotent: every edit checks the current state first, so running it twice is
safe. Fails loudly (exit 1) if an expected anchor is missing, so template
changes in a future Flutter release surface in CI instead of being ignored.

Sources followed:
- just_audio_background 0.0.1-beta.17 README, "Android setup" / "iOS setup"
  https://github.com/ryanheise/just_audio/blob/minor/just_audio_background/README.md
- audio_service README, "Android setup" + "Custom Android activity"
  https://github.com/ryanheise/audio_service/blob/minor/audio_service/README.md
- file_picker wiki, Setup -> iOS (NSAppleMusicUsageDescription for FileType.audio)
  https://github.com/miguelpruivo/flutter_file_picker/wiki/Setup#ios

Standard library only.
"""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

APP_LABEL = "Cassette"

# Highest minimum among the plugins (checked on GitHub):
#   file_picker 10.x android minSdk 21; sqflite_android 19; audio_service 19;
#   just_audio 16. Flutter's own default (flutter.minSdkVersion) is 24 today.
MIN_ANDROID_SDK = 21
# iOS: audio_service darwin podspec 13.0; just_audio, sqflite_darwin,
#   file_picker 10.x, audio_session 12.0. Flutter's template default is 15.0.
MIN_IOS = (13, 0)

ANDROID_PERMISSIONS = [
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
]

SERVICE_BLOCK = """\
        <!-- Background playback (audio_service / just_audio_background). -->
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
"""

RECEIVER_BLOCK = """\
        <!-- Headset / Bluetooth media buttons (audio_service). -->
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
"""

# Excludes every app-data domain from both Android 12+ cloud backup and
# device-to-device transfer. Paired with allowBackup="false" (Android <= 11).
DATA_EXTRACTION_RULES = """\
<?xml version="1.0" encoding="utf-8"?>
<!-- Cassette keeps the music library on this device only.
     Nothing is backed up to the cloud or copied during device transfer. -->
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" path="." />
        <exclude domain="file" path="." />
        <exclude domain="database" path="." />
        <exclude domain="sharedpref" path="." />
        <exclude domain="external" path="." />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" path="." />
        <exclude domain="file" path="." />
        <exclude domain="database" path="." />
        <exclude domain="sharedpref" path="." />
        <exclude domain="external" path="." />
    </device-transfer>
</data-extraction-rules>
"""

APPLE_MUSIC_USAGE = (
    "Cassette only uses this if you choose to import a song from your music "
    "library. Songs are copied into the app and stay on this iPhone."
)

changes: list[str] = []


def fail(msg: str) -> None:
    print(f"patch_platforms: ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def note(msg: str) -> None:
    changes.append(msg)
    print(f"  changed: {msg}")


def read(path: Path) -> str:
    if not path.is_file():
        fail(f"expected file not found: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def write_if_changed(path: Path, old: str, new: str) -> None:
    if new != old:
        path.write_text(new, encoding="utf-8")


# --------------------------------------------------------------------------- #
# Android
# --------------------------------------------------------------------------- #

def set_attr(tag: str, name: str, value: str) -> str:
    """Set attribute `name` on an XML start tag string (no '>' handling)."""
    pattern = re.compile(r'(\s)' + re.escape(name) + r'\s*=\s*"[^"]*"')
    m = pattern.search(tag)
    if m:
        current = re.search(r'"([^"]*)"', m.group(0)).group(1)
        if current == value:
            return tag
        note(f'AndroidManifest: {name}="{current}" -> "{value}"')
        return tag[: m.start()] + f'{m.group(1)}{name}="{value}"' + tag[m.end():]
    # Insert right after the element name, on its own line.
    m = re.match(r"<([\w.:-]+)", tag)
    if not m:
        fail(f"cannot parse start tag: {tag[:60]}")
    note(f'AndroidManifest: added {name}="{value}" to <{m.group(1)}>')
    indent = "\n        "
    return tag[: m.end()] + f'{indent}{name}="{value}"' + tag[m.end():]


def patch_android_manifest() -> None:
    path = ROOT / "android/app/src/main/AndroidManifest.xml"
    old = read(path)
    text = old

    # <manifest> start tag: add the tools namespace (used by tools:ignore).
    m = re.search(r"<manifest\b[^>]*>", text)
    if not m:
        fail("AndroidManifest: <manifest> start tag not found")
    manifest_tag = m.group(0)
    if "xmlns:tools=" not in manifest_tag:
        new_tag = manifest_tag.replace(
            "<manifest",
            '<manifest xmlns:tools="http://schemas.android.com/tools"',
            1,
        )
        text = text[: m.start()] + new_tag + text[m.end():]
        note("AndroidManifest: added xmlns:tools to <manifest>")

    # Remove INTERNET from the main manifest. Debug/profile manifests keep it
    # (the Flutter tool needs it for hot reload); release builds get none.
    internet = re.compile(
        r'[ \t]*<uses-permission\s+android:name="android\.permission\.INTERNET"\s*/>[ \t]*\n?'
    )
    if internet.search(text):
        text = internet.sub("", text)
        note("AndroidManifest: removed INTERNET permission from main manifest")

    # Permissions, inserted right after the <manifest ...> start tag.
    m = re.search(r"<manifest\b[^>]*>\n?", text)
    insert_at = m.end()
    to_add = []
    for perm in ANDROID_PERMISSIONS:
        if f'android:name="{perm}"' not in text:
            to_add.append(f'    <uses-permission android:name="{perm}"/>\n')
            note(f"AndroidManifest: added permission {perm}")
    if to_add:
        text = text[:insert_at] + "".join(to_add) + text[insert_at:]

    # <application> attributes.
    m = re.search(r"<application\b[^>]*>", text)
    if not m:
        fail("AndroidManifest: <application> start tag not found")
    app_tag = m.group(0)
    for name, value in [
        ("android:label", APP_LABEL),
        ("android:allowBackup", "false"),
        ("android:fullBackupContent", "false"),
        ("android:dataExtractionRules", "@xml/data_extraction_rules"),
    ]:
        app_tag = set_attr(app_tag, name, value)
    text = text[: m.start()] + app_tag + text[m.end():]

    # The launcher activity must be (or extend) AudioServiceActivity. We keep
    # the template's .MainActivity and make it extend AudioServiceActivity
    # (audio_service README, "Custom Android activity").
    m = re.search(r"<activity\b[^>]*android:name=\"([^\"]+)\"", text)
    if not m:
        fail("AndroidManifest: <activity android:name=...> not found")
    activity = m.group(1)
    if not activity.endswith("MainActivity") and activity != "com.ryanheise.audioservice.AudioServiceActivity":
        fail(f"AndroidManifest: unexpected activity name {activity!r}")

    # Service + media button receiver, inserted before </application>.
    if "</application>" not in text:
        fail("AndroidManifest: </application> not found")
    blocks = ""
    if "com.ryanheise.audioservice.AudioService\"" not in text:
        blocks += SERVICE_BLOCK
        note("AndroidManifest: added AudioService <service>")
    if "com.ryanheise.audioservice.MediaButtonReceiver" not in text:
        blocks += RECEIVER_BLOCK
        note("AndroidManifest: added MediaButtonReceiver <receiver>")
    if blocks:
        text = re.sub(r"([ \t]*)</application>", lambda mm: blocks + mm.group(0), text, count=1)

    write_if_changed(path, old, text)


def write_data_extraction_rules() -> None:
    path = ROOT / "android/app/src/main/res/xml/data_extraction_rules.xml"
    if path.is_file() and path.read_text(encoding="utf-8") == DATA_EXTRACTION_RULES:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(DATA_EXTRACTION_RULES, encoding="utf-8")
    note(f"wrote {path.relative_to(ROOT)}")


def patch_main_activity() -> None:
    src = ROOT / "android/app/src/main"
    kt = sorted(src.glob("kotlin/**/MainActivity.kt"))
    java = sorted(src.glob("java/**/MainActivity.java"))
    if len(kt) + len(java) != 1:
        fail(f"expected exactly one MainActivity, found {[str(p) for p in kt + java]}")

    if kt:
        path = kt[0]
        old = read(path)
        text = old
        if "AudioServiceActivity()" not in text:
            text, n = re.subn(
                r"class\s+MainActivity\s*:\s*FlutterActivity\s*\(\s*\)",
                "class MainActivity : AudioServiceActivity()",
                text,
            )
            if n != 1:
                fail(f"{path.relative_to(ROOT)}: 'class MainActivity : FlutterActivity()' not found")
            note(f"{path.relative_to(ROOT)}: MainActivity now extends AudioServiceActivity")
        if "import com.ryanheise.audioservice.AudioServiceActivity" not in text:
            if "import io.flutter.embedding.android.FlutterActivity" in text:
                text = text.replace(
                    "import io.flutter.embedding.android.FlutterActivity",
                    "import com.ryanheise.audioservice.AudioServiceActivity",
                    1,
                )
            else:
                text, n = re.subn(r"^(package [^\n]+\n)", r"\1\nimport com.ryanheise.audioservice.AudioServiceActivity\n", text, count=1, flags=re.M)
                if n != 1:
                    fail(f"{path.relative_to(ROOT)}: package line not found")
            note(f"{path.relative_to(ROOT)}: import AudioServiceActivity")
        write_if_changed(path, old, text)
    else:
        path = java[0]
        old = read(path)
        text = old
        if "extends AudioServiceActivity" not in text:
            text, n = re.subn(r"extends\s+FlutterActivity\b", "extends AudioServiceActivity", text)
            if n != 1:
                fail(f"{path.relative_to(ROOT)}: 'extends FlutterActivity' not found")
            text = text.replace(
                "import io.flutter.embedding.android.FlutterActivity;",
                "import com.ryanheise.audioservice.AudioServiceActivity;",
            )
            if "import com.ryanheise.audioservice.AudioServiceActivity;" not in text:
                fail(f"{path.relative_to(ROOT)}: FlutterActivity import not found")
            note(f"{path.relative_to(ROOT)}: MainActivity now extends AudioServiceActivity")
        write_if_changed(path, old, text)


def patch_min_sdk() -> None:
    app = ROOT / "android/app"
    candidates = [p for p in (app / "build.gradle.kts", app / "build.gradle") if p.is_file()]
    if not candidates:
        fail("android/app/build.gradle(.kts) not found")
    path = candidates[0]
    old = read(path)
    # Kotlin DSL: `minSdk = X`; Groovy: `minSdk X`, `minSdk = X`, `minSdkVersion X`.
    pattern = re.compile(r"^(\s*)(minSdk(?:Version)?)(\s*=\s*|\s+)([^\s/]+)", re.M)
    m = pattern.search(old)
    if not m:
        fail(f"{path.relative_to(ROOT)}: minSdk line not found")
    value = m.group(4)
    if value.isdigit():
        if int(value) >= MIN_ANDROID_SDK:
            return
        new_value = str(MIN_ANDROID_SDK)
    elif value == "flutter.minSdkVersion":
        # Flutter's default is 24 on current stable (gradle_utils.dart
        # minSdkVersionInt). Keep it; it is above every plugin's minimum.
        return
    else:
        fail(f"{path.relative_to(ROOT)}: unrecognised minSdk value {value!r}")
    text = old[: m.start(4)] + new_value + old[m.end(4):]
    note(f"{path.relative_to(ROOT)}: minSdk {value} -> {new_value}")
    write_if_changed(path, old, text)


# --------------------------------------------------------------------------- #
# iOS
# --------------------------------------------------------------------------- #

def patch_info_plist() -> None:
    path = ROOT / "ios/Runner/Info.plist"
    if not path.is_file():
        fail("ios/Runner/Info.plist not found")
    raw = path.read_bytes()
    plist = plistlib.loads(raw)
    changed = False
    if not isinstance(plist, dict):
        fail("Info.plist root is not a dict")

    def set_key(key: str, value) -> None:
        nonlocal changed
        if plist.get(key) != value:
            changed = True
            note(f"Info.plist: {key} = {value!r}")
            plist[key] = value

    set_key("CFBundleDisplayName", APP_LABEL)

    modes = list(plist.get("UIBackgroundModes", []))
    if "audio" not in modes:
        modes.append("audio")
        plist["UIBackgroundModes"] = modes
        changed = True
        note("Info.plist: UIBackgroundModes += audio")

    # Keep the app's files private: no Files-app / iTunes exposure of Documents.
    set_key("UIFileSharingEnabled", False)
    set_key("LSSupportsOpeningDocumentsInPlace", False)

    # file_picker FileType.audio presents MPMediaPickerController, which
    # requires this key (wiki: Setup -> iOS). Missing it crashes the app.
    set_key("NSAppleMusicUsageDescription", APPLE_MUSIC_USAGE)

    # Only rewrite when something changed, so a second run leaves the file
    # byte-for-byte identical.
    if changed:
        path.write_bytes(plistlib.dumps(plist, fmt=plistlib.FMT_XML, sort_keys=False))


def _ver(s: str) -> tuple[int, ...]:
    return tuple(int(x) for x in s.split("."))


def patch_ios_deployment_target() -> None:
    target = ".".join(str(x) for x in MIN_IOS)

    pbx = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    old = read(pbx)
    found = re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);", old)
    if not found:
        fail("project.pbxproj: IPHONEOS_DEPLOYMENT_TARGET not found")

    def bump(m: re.Match) -> str:
        return f"IPHONEOS_DEPLOYMENT_TARGET = {target};" if _ver(m.group(1)) < MIN_IOS else m.group(0)

    text = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);", bump, old)
    if text != old:
        note(f"project.pbxproj: IPHONEOS_DEPLOYMENT_TARGET raised to {target}")
        pbx.write_text(text, encoding="utf-8")

    # The Podfile is usually generated later (at build time) by the Flutter
    # tool, whose post_install aligns pod targets. Patch it only if present.
    podfile = ROOT / "ios/Podfile"
    if podfile.is_file():
        old = podfile.read_text(encoding="utf-8")
        m = re.search(r"^platform :ios, '([\d.]+)'", old, re.M)
        if m and _ver(m.group(1)) < MIN_IOS:
            text = old[: m.start(1)] + target + old[m.end(1):]
            podfile.write_text(text, encoding="utf-8")
            note(f"Podfile: platform :ios {m.group(1)} -> {target}")


def main() -> None:
    for d in ("android", "ios"):
        if not (ROOT / d).is_dir():
            fail(f"{d}/ missing; run tool/bootstrap_platforms.sh first")

    print("patch_platforms: Android")
    patch_android_manifest()
    write_data_extraction_rules()
    patch_main_activity()
    patch_min_sdk()

    print("patch_platforms: iOS")
    patch_info_plist()
    patch_ios_deployment_target()

    if changes:
        print(f"patch_platforms: {len(changes)} change(s) applied")
    else:
        print("patch_platforms: already up to date, nothing changed")


if __name__ == "__main__":
    main()
