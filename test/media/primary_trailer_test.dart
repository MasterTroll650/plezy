import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/media/primary_trailer.dart';

import '../test_helpers/media_items.dart';

void main() {
  final featurette = testMediaItem(id: 'featurette', raw: const {'ExtraType': 'Featurette'});
  final trailer = testMediaItem(id: 'trailer', raw: const {'ExtraType': 'Trailer'});

  test('picks the first extra classified as a trailer', () {
    expect(primaryTrailer(testMediaItem(id: 'movie'), [featurette, trailer])?.id, 'trailer');
  });

  test("prefers Plex's own primary extra over the first trailer", () {
    final pick = testMediaItem(id: '52601', raw: const {'ExtraType': 'Featurette'});
    final movie = (testMediaItem(id: 'movie') as PlexMediaItem).copyWith(trailerKey: '/library/metadata/52601');

    expect(primaryTrailer(movie, [trailer, pick])?.id, '52601');
  });

  test('detects only German audio in a playable trailer version', () {
    final item = (trailer as PlexMediaItem).copyWith(
      mediaVersions: const [
        MediaVersion(
          id: 'unavailable',
          parts: [
            MediaPart(
              id: 'offline',
              exists: false,
              streams: [MediaStream(id: 'offline-audio', kind: MediaStreamKind.audio, languageCode: 'de')],
            ),
          ],
        ),
        MediaVersion(
          id: 'playable',
          parts: [
            MediaPart(
              id: 'file',
              streams: [
                MediaStream(id: 'subtitle', kind: MediaStreamKind.subtitle, languageCode: 'de'),
                MediaStream(id: 'english', kind: MediaStreamKind.audio, languageCode: 'eng'),
                MediaStream(id: 'german', kind: MediaStreamKind.audio, languageCode: 'ger'),
              ],
            ),
          ],
        ),
      ],
    );
    expect(trailerAudioInLanguage(item, 'de')?.version.id, 'playable');
    expect(trailerAudioInLanguage(item, 'de')?.track.id, 'german');
    expect(trailerAudioInLanguage(trailer, 'de'), isNull);
  });

  test('reads MediaBrowser extra types and returns null without a trailer', () {
    final jellyfinTrailer = testMediaItem(
      id: 'jf-trailer',
      backend: MediaBackend.jellyfin,
      raw: const {'Type': 'Trailer'},
    );

    expect(primaryTrailer(testMediaItem(id: 'movie'), [featurette, jellyfinTrailer])?.id, 'jf-trailer');
    expect(primaryTrailer(testMediaItem(id: 'movie'), [featurette]), isNull);
  });
}
