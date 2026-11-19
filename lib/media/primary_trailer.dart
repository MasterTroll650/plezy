import 'package:collection/collection.dart';

import '../utils/language_codes.dart';
import 'media_item.dart';
import 'media_stream.dart';
import 'media_version.dart';

/// The trailer among the [extras] of [parent]: Plex's own pick
/// (`primaryExtraKey`) when it is among them, otherwise the first extra
/// classified as a trailer. Null when none is.
MediaItem? primaryTrailer(MediaItem parent, List<MediaItem> extras) {
  if (parent case PlexMediaItem(:final trailerKey?)) {
    // "/library/metadata/52601" -> "52601"
    final primaryKey = trailerKey.split('/').last;
    if (extras.firstWhereOrNull((extra) => extra.id == primaryKey) case final trailer?) return trailer;
  }
  return extras.firstWhereOrNull(_isTrailerExtra);
}

bool _isTrailerExtra(MediaItem extra) {
  if (extra case PlexMediaItem(:final subtype?)) {
    return subtype.toLowerCase() == 'trailer';
  }
  final raw = extra.raw;
  final extraType = raw?['ExtraType'] as String?;
  final type = raw?['Type'] as String?;
  return extraType?.toLowerCase() == 'trailer' || type?.toLowerCase() == 'trailer';
}

/// The requested audio language in the first playable version that has it.
({MediaVersion version, MediaStream track})? trailerAudioInLanguage(MediaItem? trailer, String languageCode) {
  if (trailer == null) return null;
  for (final version in trailer.mediaVersions ?? const <MediaVersion>[]) {
    for (final part in version.parts.where((part) => part.isPlayable)) {
      for (final stream in part.streams.where((stream) => stream.kind == MediaStreamKind.audio)) {
        final code = LanguageCodes.getIso6391Code(stream.languageCode ?? '');
        final language = stream.language?.trim().toLowerCase();
        final languageByName = switch (language) {
          'german' || 'deutsch' => 'de',
          'english' || 'englisch' => 'en',
          _ => null,
        };
        if ((code ?? languageByName) == languageCode) {
          return (version: version, track: stream);
        }
      }
    }
  }
  return null;
}
