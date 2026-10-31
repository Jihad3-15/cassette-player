import 'package:audio_session/audio_session.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// Sets up background playback (notification, lock screen, headset buttons)
/// and configures the audio session for music. Call once from main() before
/// any AudioPlayer is created.
Future<void> initAudioBackground() async {
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.jihad.cassette.channel.audio',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
    );
  } catch (_) {
    // Background controls are unavailable; foreground playback still works.
  }
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (_) {
    // Fall back to the platform's default audio session.
  }
}
