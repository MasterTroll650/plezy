import 'dart:convert';

import '../../utils/trailer_urls.dart';
import 'trailer_lookup.dart';

/// Filters and ranks fresh organic results from the public YouTube search page.
Future<List<Uri>> searchYouTubeTrailers(
  String title, {
  required String language,
  String? alternateTitle,
  bool searchWithGermanWording = false,
  int? releaseYear,
  Set<Uri> excluded = const {},
}) async {
  final query = title.trim();
  final titles = {
    _normalizeTitle(query.replaceFirst(_releaseYearSuffix, '')),
    if (alternateTitle != null) _normalizeTitle(alternateTitle.replaceFirst(_releaseYearSuffix, '')),
  }..remove('');
  if (query.isEmpty || titles.isEmpty) return const [];
  final suffix = switch (language) {
    'de' when searchWithGermanWording => 'trailer deutsch',
    'de' => 'trailer german',
    _ => 'official trailer english',
  };
  final year = _releaseYearSuffix.firstMatch(query)?.group(1) ?? releaseYear?.toString();
  final searchTitle = searchWithGermanWording ? query.replaceFirst(_releaseYearSuffix, '') : query;
  final url = Uri.https('www.youtube.com', '/results', {
    'search_query': '$searchTitle $suffix',
    'hl': language,
    'gl': 'DE',
  });
  return await requestTrailer<List<Uri>>(
        url,
        source: 'YouTube ($language)',
        timeout: const Duration(seconds: 4),
        headers: {
          // The desktop search layout includes duration labels.
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        },
        parse: (body) => _parseYouTubeResults(body, titles, year, language, excluded),
      ) ??
      const [];
}

List<Uri> _parseYouTubeResults(
  String body,
  Set<String> expectedTitles,
  String? year,
  String language,
  Set<Uri> excluded,
) {
  final payload = _initialData.firstMatch(body)?.group(1);
  if (payload == null) throw const FormatException('YouTube search response did not include results');
  final data = jsonDecode(payload);
  if (data is! Map<String, dynamic>) throw const FormatException('Invalid YouTube search response');
  final sections =
      data['contents']?['twoColumnSearchResultsRenderer']?['primaryContents']?['sectionListRenderer']?['contents'];
  if (sections is! List) throw const FormatException('Unrecognized YouTube search layout');
  final matches = <String, ({Uri uri, int rank})>{};
  for (final section in sections.whereType<Map<String, dynamic>>()) {
    final results = section['itemSectionRenderer']?['contents'];
    if (results is! List) continue;
    for (final result in results.whereType<Map<String, dynamic>>()) {
      final video = result['videoRenderer'];
      if (video is! Map<String, dynamic>) continue;
      final label = video['lengthText']?['simpleText'];
      final duration = label is String ? _durationSeconds(label) : null;
      final id = video['videoId'];
      if (duration == null || duration <= 0 || duration > 240 || id is! String) continue;
      final title = _videoTitle(video['title']);
      final candidateTitle = _normalizeTitle(title);
      if (!expectedTitles.any((title) => ' $candidateTitle '.contains(' $title ')) ||
          _hasDifferentSubtitle(title, expectedTitles) ||
          _unofficialTrailerLabel.hasMatch(candidateTitle)) {
        continue;
      }
      final hasGermanLabel = _germanTrailerLabel.hasMatch(candidateTitle);
      if ((language == 'de') != hasGermanLabel) continue;
      final mentionedYears = _explicitYear.allMatches(title).map((match) => match.group(1)).toSet();
      if (year != null && mentionedYears.isNotEmpty && !mentionedYears.contains(year)) continue;
      final watchUrl = youTubeTrailerUrl(id);
      if (youTubeVideoId(watchUrl) != id) continue;
      final uri = Uri.parse(watchUrl!);
      if (excluded.contains(uri)) continue;

      final rank = _trailerRank(
        video,
        candidateTitle,
        expectedTitles,
        language,
        year != null && mentionedYears.contains(year),
      );
      final previous = matches[id];
      if (previous == null || rank > previous.rank) matches[id] = (uri: uri, rank: rank);
    }
  }
  final ranked = matches.entries.toList()
    ..sort((a, b) {
      final byRank = b.value.rank.compareTo(a.value.rank);
      return byRank != 0 ? byRank : a.key.compareTo(b.key);
    });
  return ranked.take(3).map((match) => match.value.uri).toList();
}

int _trailerRank(
  Map<String, dynamic> video,
  String title,
  Set<String> expectedTitles,
  String language,
  bool yearMatches,
) {
  final languageLabel = language == 'de' ? _explicitGerman : _explicitEnglish;
  final regularTrailer = _trailerWord.hasMatch(title) && !_teaserOrPromo.hasMatch(title);
  final verifiedChannel = _hasVerifiedChannelBadge(video['ownerBadges']);
  final officialTrailer = verifiedChannel && regularTrailer && _officialWord.hasMatch(title);

  // Higher-priority criteria outweigh all criteria below them combined.
  return (languageLabel.hasMatch(title) ? 32 : 0) +
      (officialTrailer ? 16 : 0) +
      (yearMatches ? 8 : 0) +
      (regularTrailer ? 4 : 0) +
      (verifiedChannel ? 2 : 0) +
      (expectedTitles.any((name) => title == name || title.startsWith('$name ')) ? 1 : 0);
}

bool _hasVerifiedChannelBadge(Object? badges) {
  if (badges is! List) return false;
  return badges.whereType<Map<String, dynamic>>().any((badge) {
    final renderer = badge['metadataBadgeRenderer'];
    return renderer is Map &&
        (renderer['style'] == 'BADGE_STYLE_TYPE_VERIFIED' || renderer['style'] == 'BADGE_STYLE_TYPE_VERIFIED_ARTIST');
  });
}

final _explicitGerman = RegExp(r'\b(?:german|deutsch(?:e[rsnm]?)?)\b');
final _explicitEnglish = RegExp(r'\b(?:english|englisch(?:e[rsnm]?)?)\b');
final _officialWord = RegExp(r'\b(?:official|offiziell\w*)\b');
final _trailerWord = RegExp(r'\btrailer\b');
final _teaserOrPromo = RegExp(r'\b(?:teaser|promo|preview|clip|vorschau)\b');

final _initialData = RegExp(r'var ytInitialData\s*=\s*(\{.*?\})\s*;\s*</script>', dotAll: true);
final _germanTrailerLabel = RegExp(r'\b(?:german|deutsch\w*|offiziell\w*)\b');
final _unofficialTrailerLabel = RegExp(r'\b(?:concept trailer|fan trailer|fan made|fanmade|ai trailer)\b');
final _trailerDescriptor = RegExp(
  r'^(?:trailer|teaser|official|offiziell\w*|season|staffel|s\d+|german|deutsch\w*|\d{4})\b',
);

bool _hasDifferentSubtitle(String title, Set<String> expectedTitles) {
  final colon = title.indexOf(':');
  if (colon < 0 || !expectedTitles.contains(_normalizeTitle(title.substring(0, colon)))) return false;
  return !_trailerDescriptor.hasMatch(_normalizeTitle(title.substring(colon + 1)));
}

final _duration = RegExp(r'^(\d{1,2}):([0-5]\d)$');

final _releaseYearSuffix = RegExp(r'\s*\(((?:19|20)\d{2})\)\s*$');
final _explicitYear = RegExp(r'\(((?:19|20)\d{2})\)');
final _titleWords = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

String _normalizeTitle(String value) =>
    _titleWords.allMatches(value.toLowerCase()).map((word) => word.group(0)!).join(' ');

String _videoTitle(Object? value) {
  if (value is! Map<String, dynamic>) return '';
  if (value['simpleText'] case final String text) return text;
  final runs = value['runs'];
  if (runs is! List) return '';
  return runs.whereType<Map<String, dynamic>>().map((run) => run['text']).whereType<String>().join();
}

int? _durationSeconds(String value) {
  final match = _duration.firstMatch(value.trim());
  if (match == null) return null;
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}
