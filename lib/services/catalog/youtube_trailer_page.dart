import 'dart:async';
import 'dart:io';

/// Serves the player from a loopback origin so WebView2 sends a real Referer.
class YouTubeTrailerPage {
  YouTubeTrailerPage._(this._server);

  final HttpServer _server;

  Uri get url => Uri.http('127.0.0.1:${_server.port}', '/trailer');

  static Future<YouTubeTrailerPage> start(String videoId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      throw ArgumentError.value(videoId, 'videoId', 'Invalid YouTube video ID');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final page = YouTubeTrailerPage._(server);
    final origin = page.url.origin;
    final playerUrl = Uri.https('www.youtube.com', '/embed/$videoId', {
      'autoplay': '1',
      'playsinline': '1',
      'enablejsapi': '1',
      'cc_load_policy': '0',
      'origin': origin,
    });
    server.listen((request) {
      final response = request.response;
      if (request.method != 'GET' ||
          request.uri.path != '/trailer' ||
          request.headers.value(HttpHeaders.hostHeader) != page.url.authority) {
        response.statusCode = HttpStatus.notFound;
      } else {
        response.headers.contentType = ContentType.html;
        response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
        response.headers.set('Cache-Control', 'no-store');
        response.headers.set(
          'Content-Security-Policy',
          "default-src 'none'; style-src 'unsafe-inline'; "
              "script-src 'unsafe-inline' https://www.youtube.com https://s.ytimg.com; "
              'frame-src https://www.youtube.com; frame-ancestors \'none\'',
        );
        response.write('''
<!doctype html>
<meta charset="utf-8">
<title>Trailer</title>
<style>
  html, body { width: 100%; height: 100%; margin: 0; background: black; }
  iframe { display: block; width: 100%; height: 100%; border: 0; }
</style>
<iframe id="player" title="YouTube Trailer"
  src="${playerUrl.toString().replaceAll('&', '&amp;')}"
  referrerpolicy="strict-origin-when-cross-origin"
  allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
<script>
  window.trailerPlaybackStatus = () => {
    const player = window.trailerPlayer;
    return {
      error: window.trailerError ?? null,
      ready: window.trailerReady === true ||
        player?.getPlayerState?.() === 1 || (player?.getCurrentTime?.() ?? 0) > 0.25,
    };
  };
  function reportPlayerError(code) {
    window.trailerError = code;
    window.chrome?.webview?.postMessage({type: 'trailerError', code});
  }
  function reportPlayerReady() {
    window.trailerReady = true;
    window.chrome?.webview?.postMessage({type: 'trailerReady'});
  }
  function onYouTubeIframeAPIReady() {
    window.trailerPlayer = new YT.Player('player', {
      events: {
        onReady: event => event.target.playVideo(),
        onStateChange: event => {
          if (event.data === YT.PlayerState.PLAYING) reportPlayerReady();
        },
        onAutoplayBlocked: reportPlayerReady,
        onError: event => reportPlayerError(event.data)
      }
    });
  }
</script>
<script src="https://www.youtube.com/iframe_api" onerror="reportPlayerError(-1)"></script>
''');
      }
      unawaited(response.close());
    });
    return page;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }
}
