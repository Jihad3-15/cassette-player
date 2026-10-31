import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../core/models.dart';
import '../data/library_repository.dart';
import 'playback_controller.dart';

/// One slot in the queue. The same track can appear more than once (e.g. via
/// "play next"), so queue entries need their own identity.
class _Entry {
  final int key;
  final Track track;
  _Entry(this.key, this.track);
}

/// PlaybackController backed by just_audio (+ just_audio_background for the
/// notification / lock screen).
///
/// Design: this class owns the queue. The player's shuffle mode is never
/// enabled; instead the player's source list is always kept in actual play
/// order ([_order]), so the player's currentIndex indexes straight into
/// [queue]. [_original] keeps the unshuffled order for persistence and for
/// turning shuffle off again. Reordering for shuffle on/off removes and
/// re-inserts every source except the current one, so playback of the current
/// track is never interrupted.
class JustAudioPlaybackController extends PlaybackController {
  JustAudioPlaybackController(this._repo)
      : _player = AudioPlayer(maxSkipsOnError: 3) {
    _subscriptions
      ..add(_player.currentIndexStream.listen(_onCurrentIndex))
      ..add(_player.playerStateStream.listen(_onPlayerState))
      ..add(_player.durationStream.listen((_) => _notify()))
      // Errors (e.g. a corrupt file) are skipped by maxSkipsOnError; listening
      // here just makes sure the UI refreshes afterwards.
      ..add(_player.errorStream.listen((_) => _notify(), onError: (Object _) {}));
  }

  static const _positionSaveInterval = Duration(seconds: 5);
  static const _restartThreshold = Duration(seconds: 3);

  final LibraryRepository _repo;
  final AudioPlayer _player;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _random = Random();

  List<_Entry> _original = [];
  List<_Entry> _order = [];
  int _nextKey = 0;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;

  bool _disposed = false;
  bool _lastPlaying = false;
  int? _lastIndex;
  bool _handlingCompletion = false;
  Timer? _positionTimer;

  Future<void> _lock = Future<void>.value();
  Future<void> _saveChain = Future<void>.value();

  // ---------------------------------------------------------------- getters

  @override
  Track? get current {
    final i = currentIndex;
    return i < 0 ? null : _order[i].track;
  }

  @override
  List<Track> get queue =>
      List<Track>.unmodifiable(_order.map((e) => e.track));

  @override
  int get currentIndex {
    if (_order.isEmpty) return -1;
    final i = _player.currentIndex ?? 0;
    if (i < 0) return 0;
    if (i >= _order.length) return _order.length - 1;
    return i;
  }

  @override
  bool get playing => _player.playing;

  @override
  bool get shuffle => _shuffle;

  @override
  RepeatMode get repeat => _repeat;

  @override
  Duration? get duration {
    final d = _player.duration;
    if (d != null) return d;
    final t = current;
    if (t == null || t.durationMs <= 0) return null;
    return t.duration;
  }

  @override
  Duration get position => _order.isEmpty ? Duration.zero : _player.position;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  // ---------------------------------------------------------------- startup

  @override
  Future<void> init() => _run(() async {
        try {
          final snap = await _repo.loadPlaybackSnapshot();
          if (snap == null || snap.queueTrackIds.isEmpty) {
            _repeat = snap?.repeat ?? RepeatMode.off;
            _shuffle = snap?.shuffle ?? false;
            await _player.setLoopMode(_loopModeFor(_repeat));
            return;
          }

          final unique = snap.queueTrackIds.toSet().toList();
          final found = await _repo.tracksByIds(unique);
          final byId = <int, Track>{for (final t in found) t.id: t};

          final entries = <_Entry>[];
          var restoredIndex = -1;
          var currentSurvived = false;
          for (var i = 0; i < snap.queueTrackIds.length; i++) {
            final track = byId[snap.queueTrackIds[i]];
            final usable = track != null && _fileExists(track.filePath);
            if (i == snap.currentIndex) {
              // If the saved current track is gone, continue from the next
              // surviving track (or the last one if nothing follows).
              restoredIndex = entries.length;
              currentSurvived = usable;
            }
            if (usable) entries.add(_newEntry(track));
          }
          if (entries.isEmpty) {
            await _clearQueue();
            return;
          }
          if (restoredIndex < 0 || restoredIndex >= entries.length) {
            restoredIndex = restoredIndex < 0 ? 0 : entries.length - 1;
            currentSurvived = false;
          }

          _repeat = snap.repeat;
          _shuffle = snap.shuffle;
          _original = entries;
          final start = entries[restoredIndex];
          _order = _shuffle ? _shuffledAround(start) : List.of(entries);
          final orderIndex = _order.indexOf(start);
          final positionMs = currentSurvived ? max(0, snap.positionMs) : 0;

          await _player.setShuffleModeEnabled(false);
          await _player.setLoopMode(_loopModeFor(_repeat));
          await _player.setAudioSources(
            _order.map(_sourceFor).toList(),
            initialIndex: orderIndex,
            initialPosition: Duration(milliseconds: positionMs),
            preload: false,
          );
          if (!currentSurvived) _saveSnapshot();
        } catch (_) {
          // A bad snapshot must never break startup: start empty instead.
          _original = [];
          _order = [];
          _shuffle = false;
          _repeat = RepeatMode.off;
          try {
            await _player.clearAudioSources();
          } catch (_) {
            // Nothing more to recover.
          }
        }
      });

  // ------------------------------------------------------------- transport

  @override
  Future<void> playTracks(List<Track> tracks,
          {int startIndex = 0, bool shuffle = false}) =>
      _run(() => _playTracksImpl(tracks, startIndex: startIndex, shuffle: shuffle));

  Future<void> _playTracksImpl(List<Track> tracks,
      {required int startIndex, required bool shuffle}) async {
    final entries = <_Entry>[];
    var start = 0;
    for (var i = 0; i < tracks.length; i++) {
      if (i == startIndex) start = entries.length;
      if (_fileExists(tracks[i].filePath)) entries.add(_newEntry(tracks[i]));
    }
    if (entries.isEmpty) {
      await _clearQueue();
      return;
    }
    if (start >= entries.length) start = entries.length - 1;

    _shuffle = shuffle;
    _original = entries;
    final startEntry = entries[start];
    _order = shuffle ? _shuffledAround(startEntry) : List.of(entries);
    _lastIndex = null;
    try {
      await _player.setAudioSources(
        _order.map(_sourceFor).toList(),
        initialIndex: _order.indexOf(startEntry),
        initialPosition: Duration.zero,
        preload: false,
      );
    } catch (_) {
      // A source that fails to load is skipped via maxSkipsOnError; an
      // interrupted load is superseded by whatever interrupted it.
    }
    _saveSnapshot(currentEntry: startEntry);
    _notify();
    _startPlayback();
  }

  @override
  Future<void> play() => _run(() async {
        if (_order.isEmpty) return;
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero, index: currentIndex);
        }
        _startPlayback();
      });

  @override
  Future<void> pause() => _run(() async {
        await _player.pause();
        _savePosition();
      });

  @override
  Future<void> togglePlay() => playing ? pause() : play();

  @override
  Future<void> next() => _run(() async {
        if (_order.isEmpty) return;
        var i = currentIndex + 1;
        if (i >= _order.length) {
          if (_repeat == RepeatMode.off) return;
          i = 0;
        }
        await _player.seek(Duration.zero, index: i);
      });

  @override
  Future<void> previous() => _run(() async {
        if (_order.isEmpty) return;
        if (_player.position > _restartThreshold) {
          await _player.seek(Duration.zero);
          return;
        }
        var i = currentIndex - 1;
        if (i < 0) {
          if (_repeat == RepeatMode.all) {
            i = _order.length - 1;
          } else {
            await _player.seek(Duration.zero);
            return;
          }
        }
        await _player.seek(Duration.zero, index: i);
      });

  @override
  Future<void> seek(Duration position) => _run(() async {
        if (_order.isEmpty) return;
        await _player.seek(position < Duration.zero ? Duration.zero : position);
        _savePosition();
      });

  @override
  Future<void> skipToQueueIndex(int index) => _run(() async {
        if (index < 0 || index >= _order.length) return;
        await _player.seek(Duration.zero, index: index);
        _startPlayback();
      });

  // ------------------------------------------------------- shuffle / repeat

  @override
  Future<void> setShuffle(bool enabled) => _run(() async {
        if (enabled == _shuffle) return;
        _shuffle = enabled;
        if (_order.isNotEmpty) {
          final cur = currentIndex;
          final entry = _order[cur];
          final newOrder = enabled ? _shuffledAround(entry) : List.of(_original);
          await _reorderAround(cur, newOrder, newOrder.indexOf(entry));
          _saveSnapshot(currentEntry: entry);
        } else {
          _saveSnapshot();
        }
        _notify();
      });

  @override
  Future<void> cycleRepeat() => _run(() async {
        _repeat = switch (_repeat) {
          RepeatMode.off => RepeatMode.all,
          RepeatMode.all => RepeatMode.one,
          RepeatMode.one => RepeatMode.off,
        };
        await _player.setLoopMode(_loopModeFor(_repeat));
        _saveSnapshot();
        _notify();
      });

  // ---------------------------------------------------------- queue edits

  @override
  Future<void> playNext(Track track) => _run(() async {
        if (!_fileExists(track.filePath)) return;
        if (_order.isEmpty) {
          await _playTracksImpl([track], startIndex: 0, shuffle: _shuffle);
          return;
        }
        final cur = currentIndex;
        final curEntry = _order[cur];
        final entry = _newEntry(track);
        final origPos = _original.indexOf(curEntry);
        _original.insert(origPos < 0 ? _original.length : origPos + 1, entry);
        _order.insert(cur + 1, entry);
        await _player.insertAudioSource(cur + 1, _sourceFor(entry));
        _saveSnapshot();
        _notify();
      });

  @override
  Future<void> addToQueue(Track track) => _run(() async {
        if (!_fileExists(track.filePath)) return;
        if (_order.isEmpty) {
          await _playTracksImpl([track], startIndex: 0, shuffle: _shuffle);
          return;
        }
        final entry = _newEntry(track);
        _original.add(entry);
        _order.add(entry);
        await _player.addAudioSource(_sourceFor(entry));
        _saveSnapshot();
        _notify();
      });

  @override
  Future<void> removeTrackEverywhere(int trackId) => _run(() async {
        _original.removeWhere((e) => e.track.id == trackId);
        var changed = false;
        for (var i = _order.length - 1; i >= 0; i--) {
          if (_order[i].track.id != trackId) continue;
          changed = true;
          _order.removeAt(i);
          // If this was the current item the player moves on by itself.
          await _player.removeAudioSourceAt(i);
        }
        if (!changed) return;
        if (_order.isEmpty) {
          await _clearQueue();
          return;
        }
        _saveSnapshot();
        _notify();
      });

  // ------------------------------------------------------------- internals

  /// Serialises all queue/transport operations so they never interleave, and
  /// swallows engine errors so callers (the UI) never see an exception.
  Future<void> _run(Future<void> Function() op) {
    final result = _lock.then((_) async {
      if (_disposed) return;
      try {
        await op();
      } catch (_) {
        // Engine failures (interrupted loads, platform errors) are not fatal.
      }
    });
    _lock = result;
    return result;
  }

  void _startPlayback() {
    // AudioPlayer.play() only completes when playback stops, so don't await.
    unawaited(_player.play().catchError((Object _) {}));
  }

  _Entry _newEntry(Track track) => _Entry(_nextKey++, track);

  List<_Entry> _shuffledAround(_Entry first) {
    final rest = _original.where((e) => !identical(e, first)).toList()
      ..shuffle(_random);
    return [first, ...rest];
  }

  /// Rewrites the player's list to [newOrder] without touching the source at
  /// [cur] (which must be newOrder[newCur]), so the current track keeps
  /// playing. [_order] is mutated in lockstep with each player call.
  Future<void> _reorderAround(int cur, List<_Entry> newOrder, int newCur) async {
    final len = _order.length;
    if (cur + 1 < len) {
      _order.removeRange(cur + 1, len);
      await _player.removeAudioSourceRange(cur + 1, len);
    }
    if (cur > 0) {
      _order.removeRange(0, cur);
      await _player.removeAudioSourceRange(0, cur);
    }
    final before = newOrder.sublist(0, newCur);
    final after = newOrder.sublist(newCur + 1);
    if (before.isNotEmpty) {
      _order.insertAll(0, before);
      await _player.insertAudioSources(0, before.map(_sourceFor).toList());
    }
    if (after.isNotEmpty) {
      _order.addAll(after);
      await _player.addAudioSources(after.map(_sourceFor).toList());
    }
  }

  Future<void> _clearQueue() async {
    _original = [];
    _order = [];
    _lastIndex = null;
    await _player.stop();
    await _player.clearAudioSources();
    _saveSnapshot();
    _notify();
  }

  AudioSource _sourceFor(_Entry entry) {
    final t = entry.track;
    final art = t.artworkPath;
    return AudioSource.file(
      t.filePath,
      tag: MediaItem(
        id: '${t.id}-${entry.key}',
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.durationMs > 0 ? t.duration : null,
        artUri: art != null && _fileExists(art) ? Uri.file(art) : null,
      ),
    );
  }

  static bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static LoopMode _loopModeFor(RepeatMode mode) => switch (mode) {
        RepeatMode.off => LoopMode.off,
        RepeatMode.all => LoopMode.all,
        RepeatMode.one => LoopMode.one,
      };

  // --------------------------------------------------------- stream events

  void _onCurrentIndex(int? index) {
    if (_disposed) return;
    if (index != _lastIndex) {
      _lastIndex = index;
      if (_order.isNotEmpty) _saveSnapshot();
    }
    _notify();
  }

  void _onPlayerState(PlayerState state) {
    if (_disposed) return;
    if (state.processingState == ProcessingState.completed &&
        state.playing &&
        !_handlingCompletion) {
      _handleCompletion();
    }
    if (state.playing != _lastPlaying) {
      _lastPlaying = state.playing;
      if (state.playing) {
        _positionTimer?.cancel();
        _positionTimer =
            Timer.periodic(_positionSaveInterval, (_) => _savePosition());
      } else {
        _positionTimer?.cancel();
        _positionTimer = null;
        _savePosition();
      }
    }
    _notify();
  }

  /// The end of the queue was reached with repeat off (with repeat on the
  /// player loops and never completes): stop on the last track, paused, at 0.
  void _handleCompletion() {
    _handlingCompletion = true;
    unawaited(_run(() async {
      try {
        await _player.pause();
        if (_order.isNotEmpty) {
          await _player.seek(Duration.zero, index: currentIndex);
        }
        _savePosition();
      } finally {
        _handlingCompletion = false;
      }
    }));
  }

  // ------------------------------------------------------------ persistence

  /// [currentEntry] overrides the engine's index, which can lag behind
  /// right after the source list was rewritten.
  void _saveSnapshot({_Entry? currentEntry}) {
    final ids = _original.map((e) => e.track.id).toList();
    var idx = 0;
    if (_order.isNotEmpty) {
      final o = _original.indexOf(currentEntry ?? _order[currentIndex]);
      if (o >= 0) idx = o;
    }
    final snap = PlaybackSnapshot(
      queueTrackIds: ids,
      currentIndex: idx,
      positionMs: _order.isEmpty ? 0 : _player.position.inMilliseconds,
      shuffle: _shuffle,
      repeat: _repeat,
    );
    _enqueueSave(() => _repo.savePlaybackSnapshot(snap));
  }

  void _savePosition() {
    if (_order.isEmpty) return;
    final ms = _player.position.inMilliseconds;
    _enqueueSave(() => _repo.savePlaybackPosition(ms));
  }

  /// Writes run one after another, in order, and never throw.
  void _enqueueSave(Future<void> Function() write) {
    _saveChain = _saveChain.then((_) async {
      try {
        await write();
      } catch (_) {
        // Persistence is best effort; playback must not depend on it.
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _savePosition();
    _disposed = true;
    _positionTimer?.cancel();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    unawaited(_player.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
