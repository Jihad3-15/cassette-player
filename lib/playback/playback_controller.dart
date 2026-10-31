import 'package:flutter/foundation.dart';

import '../core/models.dart';

/// Owns the queue, shuffle, repeat and resume. The audio engine underneath
/// only plays what it's told. Implemented by JustAudioPlaybackController in
/// just_audio_playback_controller.dart. Call notifyListeners() whenever any
/// getter below changes (except position; use positionStream for that).
abstract class PlaybackController extends ChangeNotifier {
  /// Restores the last session PAUSED (never auto-plays). Missing tracks are
  /// skipped. Safe to call when nothing was saved.
  Future<void> init();

  Track? get current;

  /// Queue in play order (shuffled order when shuffle is on).
  List<Track> get queue;
  int get currentIndex; // index into [queue], -1 when empty
  bool get playing;
  bool get shuffle;
  RepeatMode get repeat;
  Duration? get duration;
  Duration get position;
  Stream<Duration> get positionStream;

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false});
  Future<void> play();
  Future<void> pause();
  Future<void> togglePlay();
  Future<void> next();

  /// Restarts the track if more than 3s in, otherwise goes to previous.
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> skipToQueueIndex(int index);
  Future<void> setShuffle(bool enabled);
  Future<void> cycleRepeat(); // off -> all -> one -> off
  Future<void> playNext(Track track);
  Future<void> addToQueue(Track track);

  /// Removes a deleted track from the queue if present.
  Future<void> removeTrackEverywhere(int trackId);
}
