import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

/// Tags parsed from an audio file, already cleaned and with fallbacks applied.
class ParsedTags {
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? genre;
  final int durationMs;

  const ParsedTags({
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    required this.durationMs,
  });
}

/// An embedded cover image.
class EmbeddedArtwork {
  final Uint8List bytes;

  /// File extension without the dot: 'jpg' or 'png'.
  final String extension;

  const EmbeddedArtwork(this.bytes, this.extension);
}

const String unknownArtist = 'Unknown Artist';
const String unknownAlbum = 'Unknown Album';

/// Reads tags from [audioFile]. Never throws: if parsing fails, falls back to
/// values derived from [originalName] (the file name the user picked).
ParsedTags readTags(File audioFile, String originalName) {
  final fallback = _fromFileName(originalName);

  AudioMetadata? meta;
  try {
    meta = readMetadata(audioFile, getImage: false);
  } catch (_) {
    meta = null;
  }
  if (meta == null) {
    return ParsedTags(
      title: fallback.title,
      artist: fallback.artist ?? unknownArtist,
      album: unknownAlbum,
      durationMs: 0,
    );
  }

  final title = _clean(meta.title);
  final artist = _clean(meta.artist);
  final album = _clean(meta.album);

  String? genre;
  for (final g in meta.genres) {
    final c = _clean(g);
    if (c != null) {
      genre = c;
      break;
    }
  }

  final yearValue = meta.year?.year;
  final trackValue = meta.trackNumber;
  final discValue = meta.discNumber;

  return ParsedTags(
    // If the file has a title tag but no artist, keep the tag title and only
    // borrow the artist from an "Artist - Title" file name.
    title: title ?? fallback.title,
    artist: artist ?? fallback.artist ?? unknownArtist,
    album: album ?? unknownAlbum,
    albumArtist: _clean(meta.albumArtist),
    trackNumber: (trackValue != null && trackValue > 0) ? trackValue : null,
    discNumber: (discValue != null && discValue > 0) ? discValue : null,
    year: (yearValue != null && yearValue > 0 && yearValue < 10000)
        ? yearValue
        : null,
    genre: genre,
    durationMs: meta.duration?.inMilliseconds ?? 0,
  );
}

/// Reads the embedded cover (front cover preferred). Returns null if there is
/// none, it can't be parsed, or it is larger than [maxBytes]. Never throws.
EmbeddedArtwork? readArtwork(File audioFile, {required int maxBytes}) {
  try {
    final meta = readMetadata(audioFile, getImage: true);
    final pictures = meta.pictures;
    if (pictures.isEmpty) return null;

    var chosen = pictures.first;
    for (final pic in pictures) {
      if (pic.pictureType == PictureType.coverFront) {
        chosen = pic;
        break;
      }
    }

    final bytes = chosen.bytes;
    if (bytes.isEmpty || bytes.length > maxBytes) return null;

    final ext = _imageExtension(bytes, chosen.mimetype);
    if (ext == null) return null;
    return EmbeddedArtwork(bytes, ext);
  } catch (_) {
    return null;
  }
}

String? _imageExtension(Uint8List bytes, String mimetype) {
  // Trust the bytes first; mime types in tags are often wrong or missing.
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'jpg';
  }
  final mime = mimetype.toLowerCase();
  if (mime.contains('png')) return 'png';
  if (mime.contains('jpeg') || mime.contains('jpg')) return 'jpg';
  return null;
}

class _NameFallback {
  final String title;
  final String? artist;
  const _NameFallback(this.title, this.artist);
}

_NameFallback _fromFileName(String originalName) {
  final base = p.basenameWithoutExtension(originalName).trim();
  final sep = base.indexOf(' - ');
  if (sep > 0) {
    final artist = base.substring(0, sep).trim();
    final title = base.substring(sep + 3).trim();
    if (artist.isNotEmpty && title.isNotEmpty) {
      return _NameFallback(title, artist);
    }
  }
  return _NameFallback(base.isEmpty ? p.basename(originalName) : base, null);
}

/// Trims, strips NUL padding (common in ID3), and maps empty to null.
String? _clean(String? value) {
  if (value == null) return null;
  final v = value.replaceAll('\u0000', '').trim();
  return v.isEmpty ? null : v;
}
