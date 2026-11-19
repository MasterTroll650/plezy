import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../i18n/strings.g.dart';
import '../services/catalog/youtube_trailer_page.dart';
import '../utils/app_logger.dart';
import '../utils/trailer_urls.dart';

/// Keeps the trailer route open while individual candidates are replaced.
class ExploreTrailerScreen extends StatefulWidget {
  const ExploreTrailerScreen({super.key, required this.title, required this.url, this.nextTrailer});

  final String title;
  final Uri url;
  final Future<Uri?> Function()? nextTrailer;

  @override
  State<ExploreTrailerScreen> createState() => _ExploreTrailerScreenState();
}

class _ExploreTrailerScreenState extends State<ExploreTrailerScreen> {
  late Uri _url = widget.url;
  bool _switching = false;
  bool _exhausted = false;

  Future<void> _advance() async {
    if (!mounted || _switching || _exhausted) return;
    setState(() => _switching = true);
    Uri? next;
    try {
      next = await widget.nextTrailer?.call();
    } catch (error) {
      appLogger.d('Could not resolve the next trailer', error: error);
    }
    if (!mounted) return;
    if (next != null) {
      setState(() {
        _url = next!;
        _switching = false;
      });
      return;
    }
    setState(() {
      _switching = false;
      _exhausted = true;
    });
    if (ModalRoute.of(context)?.isCurrent == true && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _switching
          ? const ColoredBox(
              color: Colors.black,
              child: Center(child: CircularProgressIndicator()),
            )
          : _exhausted
          ? Center(child: Text(t.explore.detail.noTrailerAvailable))
          : ExploreTrailerPlayer(key: ValueKey(_url), url: _url, onFailure: () => unawaited(_advance())),
    );
  }
}

/// One WebView and one video attempt within the trailer route.
class ExploreTrailerPlayer extends StatefulWidget {
  const ExploreTrailerPlayer({super.key, required this.url, required this.onFailure});

  final Uri url;
  final VoidCallback onFailure;

  @override
  State<ExploreTrailerPlayer> createState() => _ExploreTrailerPlayerState();
}

class _ExploreTrailerPlayerState extends State<ExploreTrailerPlayer> {
  static Future<void>? _webViewEnvironment;

  final _controller = WebviewController();
  late final _ready = _preparePlayer().timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      _failPreparation('Trailer WebView initialization timed out');
      return false;
    },
  );
  YouTubeTrailerPage? _playerPage;
  bool _loadFailed = false;
  bool _retriedPlayerLoad = false;
  bool _playerVisible = false;
  Timer? _playerStartTimer;
  Timer? _playerRevealTimer;
  Timer? _playerStatusTimer;
  int _startupGeneration = 0;

  static Future<void> _initializeWebViewEnvironment() async {
    final cache = await getApplicationCacheDirectory();
    await WebviewController.initializeEnvironment(
      userDataPath: p.join(cache.path, 'trailer-webview'),
      additionalArguments: '--autoplay-policy=no-user-gesture-required',
    );
  }

  Future<bool> _preparePlayer() async {
    try {
      if (await WebviewController.getWebViewVersion() == null || !mounted) return false;
      try {
        await (_webViewEnvironment ??= _initializeWebViewEnvironment().timeout(const Duration(seconds: 8)));
      } catch (_) {
        _webViewEnvironment = null;
        rethrow;
      }
      if (!mounted) return false;
      await _controller.initialize();
      if (!mounted) return false;
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      if (!mounted) return false;

      final videoId = youTubeVideoId(widget.url.toString());
      final page = videoId == null ? null : await YouTubeTrailerPage.start(videoId);
      if (!mounted) {
        await page?.close();
        return false;
      }
      _playerPage = page;
      final playerUrl = page?.url ?? widget.url;
      _controller.onLoadError.listen((error) {
        if (error == WebErrorStatus.operationCanceled) return;
        final retry = switch (error) {
          WebErrorStatus.timeout ||
          WebErrorStatus.errorHttpInvalidServerResponse ||
          WebErrorStatus.serverUnreachable ||
          WebErrorStatus.connectionAborted ||
          WebErrorStatus.connectionReset ||
          WebErrorStatus.cannotConnect ||
          WebErrorStatus.disconnected ||
          WebErrorStatus.hostNameNotResolved => true,
          _ => false,
        };
        unawaited(_handleLoadError(error, retry: retry));
      });
      if (page != null) {
        _controller.url.listen((url) {
          if (url.isNotEmpty && url != 'about:blank' && Uri.tryParse(url) != playerUrl) {
            unawaited(_handleLoadError('Unexpected trailer navigation'));
          }
        });
        _controller.webMessage.listen((message) {
          if (message is! Map) return;
          if (message['type'] == 'trailerReady') {
            _revealPlayer();
          } else if (message['type'] == 'trailerError' && message['code'] is int) {
            final code = message['code'];
            unawaited(_handleLoadError('YouTube player error $code', retry: code == -1 || code == 5));
          }
        });
        await _controller.addScriptToExecuteOnDocumentCreated(_disableInitialCaptionScript);
      }
      if (!mounted) return false;
      if (page != null) _waitForPlayerStart();
      await _controller.loadUrl(playerUrl.toString());
      return true;
    } catch (error) {
      _failPreparation(error);
      return false;
    }
  }

  void _failPreparation(Object error) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_handleLoadError(error)));
  }

  void _cancelPlayerStartup() {
    _startupGeneration++;
    _playerStartTimer?.cancel();
    _playerStatusTimer?.cancel();
  }

  void _waitForPlayerStart() {
    _cancelPlayerStartup();
    final generation = _startupGeneration;
    _playerStartTimer = Timer(const Duration(seconds: 12), () {
      unawaited(_handleLoadError('YouTube trailer start timed out', retry: true));
    });
    _schedulePlayerStatusCheck(generation);
  }

  void _schedulePlayerStatusCheck(int generation) {
    _playerStatusTimer = Timer(const Duration(milliseconds: 400), () => unawaited(_checkPlayerStatus(generation)));
  }

  Future<void> _checkPlayerStatus(int generation) async {
    try {
      final status = await _controller
          .executeScript('window.trailerPlaybackStatus?.() ?? null')
          .timeout(const Duration(seconds: 1));
      if (!mounted || generation != _startupGeneration) return;
      if (status is Map) {
        if (status['error'] case final int code) {
          await _handleLoadError('YouTube player error $code', retry: code == -1 || code == 5);
          return;
        }
        if (status['ready'] == true) {
          _revealPlayer();
          return;
        }
      }
    } catch (_) {
      // The document may still be loading. The startup deadline bounds probing.
    }
    if (mounted && generation == _startupGeneration) _schedulePlayerStatusCheck(generation);
  }

  void _revealPlayer() {
    if (!mounted || _loadFailed || _playerVisible || _playerRevealTimer?.isActive == true) return;
    _cancelPlayerStartup();
    // An autoplay notification can arrive just before an unavailable-video error.
    _playerRevealTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && !_loadFailed) setState(() => _playerVisible = true);
    });
  }

  Future<void> _handleLoadError(Object error, {bool retry = false}) async {
    if (!mounted || _loadFailed) return;
    _cancelPlayerStartup();
    _playerRevealTimer?.cancel();
    if (_playerVisible) setState(() => _playerVisible = false);
    appLogger.d('Explore trailer playback failed', error: error);
    if (retry && !_retriedPlayerLoad) {
      _retriedPlayerLoad = true;
      try {
        if (_playerPage != null) _waitForPlayerStart();
        await _controller.reload();
        return;
      } catch (reloadError) {
        appLogger.d('Explore trailer reload failed', error: reloadError);
        if (!mounted || _loadFailed) return;
      }
    }
    if (!mounted || _loadFailed) return;
    setState(() => _loadFailed = true);
    widget.onFailure();
  }

  @override
  void dispose() {
    _cancelPlayerStartup();
    _playerRevealTimer?.cancel();
    unawaited(_controller.dispose());
    unawaited(_playerPage?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data != true || _loadFailed) {
          return Center(child: Text(t.explore.detail.trailerUnavailable));
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Webview(_controller),
            if (_playerPage != null && !_playerVisible)
              const ColoredBox(
                color: Colors.black,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      },
    );
  }
}

const _disableInitialCaptionScript = r"""
(() => {
  if (location.origin !== 'https://www.youtube.com' || !location.pathname.startsWith('/embed/')) return;

  const enabledCaptionButton = '.ytp-subtitles-button[aria-pressed="true"], ' +
    '.ytmClosedCaptioningButtonButton[aria-pressed="true"]';
  const observer = new MutationObserver(disableInitialCaptions);
  function disableInitialCaptions() {
    const active = document.querySelector(enabledCaptionButton);
    if (!active) return;
    observer.disconnect();
    active.click();
  }
  observer.observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ['aria-pressed'] });
  disableInitialCaptions();
  setTimeout(() => observer.disconnect(), 8000);
})();
""";
