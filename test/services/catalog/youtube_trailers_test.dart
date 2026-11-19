import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/services/catalog/youtube_trailers.dart';

Map<String, Object> _video(String id, String title, {bool verified = false, String duration = '2:00'}) => {
  'videoRenderer': {
    'videoId': id,
    'title': {'simpleText': title},
    'lengthText': {'simpleText': duration},
    if (verified)
      'ownerBadges': [
        {
          'metadataBadgeRenderer': {'style': 'BADGE_STYLE_TYPE_VERIFIED'},
        },
      ],
  },
};

Future<List<String?>> _search(List<Map<String, Object>> results) async {
  final data = {
    'contents': {
      'twoColumnSearchResultsRenderer': {
        'primaryContents': {
          'sectionListRenderer': {
            'contents': [
              {
                'itemSectionRenderer': {'contents': results},
              },
            ],
          },
        },
      },
    },
  };
  final videos = await http.runWithClient(
    () => searchYouTubeTrailers('Example Movie (2026)', language: 'de'),
    () => MockClient((_) async => http.Response('<script>var ytInitialData = ${jsonEncode(data)};</script>', 200)),
  );
  return videos.map((video) => video.queryParameters['v']).toList();
}

void main() {
  test('ranks the full result set independently of YouTube response order', () async {
    final results = [
      _video('ZZZZZZZZZZZ', 'Example Movie Trailer Deutsch'),
      _video('11111111111', 'Example Movie (2026) Offizieller Trailer', verified: true),
      _video('BBBBBBBBBBB', 'Example Movie (2026) Trailer Deutsch'),
      _video('AAAAAAAAAAA', 'Example Movie (2026) Trailer Deutsch'),
      _video('OOOOOOOOOOO', 'Example Movie (2026) Offizieller Trailer Deutsch', verified: true),
      _video('LLLLLLLLLLL', 'Example Movie (2026) Offizieller Trailer Deutsch', verified: true, duration: '4:01'),
      _video('WWWWWWWWWWW', 'Wrong Example Moviehouse (2026) Offizieller Trailer Deutsch', verified: true),
    ];
    const expected = ['OOOOOOOOOOO', 'AAAAAAAAAAA', 'BBBBBBBBBBB'];
    expect(await _search(results), expected);
    expect(await _search(results.reversed.toList()), expected);
  });
}
