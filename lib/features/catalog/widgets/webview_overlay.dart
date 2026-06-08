import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tab_colors.dart';
import '../../../core/util/key_injector.dart';

class WebViewOverlay extends StatefulWidget {
  final String url;
  final String title;
  final void Function(String url, String? filename) onDownloadRequested;

  const WebViewOverlay({
    super.key,
    required this.url,
    required this.title,
    required this.onDownloadRequested,
  });

  @override
  State<WebViewOverlay> createState() => _WebViewOverlayState();

  // Shared WebView2 environment with a user-writable data folder.
  // Without this, WebView2 defaults to creating its data folder next to the
  // exe — which silently fails when the app is installed under Program Files.
  static WebViewEnvironment? _cachedEnv;
  static Future<WebViewEnvironment>? _envFuture;

  static Future<WebViewEnvironment> _environment() {
    if (_cachedEnv != null) return Future.value(_cachedEnv);
    return _envFuture ??= _createEnvironment();
  }

  static Future<WebViewEnvironment> _createEnvironment() async {
    final dir = await getApplicationSupportDirectory();
    final env = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: p.join(dir.path, 'WebView2'),
      ),
    );
    _cachedEnv = env;
    return env;
  }
}

class _WebViewOverlayState extends State<WebViewOverlay> {
  InAppWebViewController? _controller;
  String _currentUrl = '';
  bool _loading = true;
  WebViewEnvironment? _webViewEnvironment;
  bool _envReady = false;

  static const _videoExts = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v'};

  // Injected via onLoadStop/evaluateJavascript (the AT_DOCUMENT_START path
  // produces nothing on flutter_inappwebview_windows).
  //
  // Google Photos' in-page "Download" menu item produces no usable download
  // event inside WebView2 (verified: clicking it fires zero fetch/anchor/nav
  // activity). The page's own Shift+D shortcut DOES work — but only for a
  // *trusted* key event; a synthetic JS KeyboardEvent (isTrusted=false) is
  // ignored. So we just detect the click and let Dart inject a real Shift+D
  // via Win32 SendInput.
  static const _downloadInterceptScript = r'''
(function() {
  if (window.__mdInstalled) { return; }
  window.__mdInstalled = true;

  function signalDownloadClick() {
    try { window.flutter_inappwebview.callHandler('mDownloadClick'); } catch(e) {}
  }

  function isDownloadItem(el) {
    if (!el || !el.getAttribute) return false;
    var role = el.getAttribute('role') || '';
    if (role !== 'menuitem' && role !== 'option') return false;
    var txt = ((el.innerText || el.textContent || '') + ' ' +
               (el.getAttribute('aria-label') || '')).toLowerCase();
    return txt.indexOf('download') !== -1 && txt.length < 100;
  }

  // Attach a click listener directly to any Download menu item the moment
  // it appears in the DOM — more reliable than event delegation alone.
  new MutationObserver(function(muts) {
    muts.forEach(function(m) {
      m.addedNodes.forEach(function(n) {
        if (n.nodeType !== 1) return;
        var candidates = [];
        if (isDownloadItem(n)) candidates.push(n);
        try {
          n.querySelectorAll('[role="menuitem"],[role="option"]').forEach(function(e) {
            if (isDownloadItem(e)) candidates.push(e);
          });
        } catch(_) {}
        candidates.forEach(function(el) {
          el.addEventListener('click', signalDownloadClick);
        });
      });
    });
  }).observe(document.documentElement, { childList: true, subtree: true });

  // Fallback: capture-phase delegation in case MutationObserver misses it.
  document.addEventListener('click', function(e) {
    var el = e.target;
    while (el && el !== document) {
      if (isDownloadItem(el)) { signalDownloadClick(); return; }
      el = el.parentElement;
    }
  }, true);
})();
''';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    WebViewOverlay._environment().then(
      (env) {
        if (mounted) setState(() { _webViewEnvironment = env; _envReady = true; });
      },
      onError: (_) {
        if (mounted) setState(() => _envReady = true);
      },
    );
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    if (_videoExts.any((ext) => lower.contains(ext))) return true;
    if (lower.contains('googleusercontent.com')) return true;
    return false;
  }

  String? _suggestFilename(String url) {
    try {
      final uri = Uri.parse(url);
      final seg = uri.pathSegments.lastWhere(
        (s) => _videoExts.any((e) => s.toLowerCase().endsWith(e)),
        orElse: () => '',
      );
      return seg.isNotEmpty ? seg : null;
    } catch (_) {
      return null;
    }
  }

  void _triggerDownload(String url, {String? suggestedFilename}) {
    if (!mounted) return;
    Navigator.of(context).pop();
    final filename = (suggestedFilename?.isNotEmpty == true)
        ? suggestedFilename!
        : (_suggestFilename(url) ?? '${widget.title}.mp4');
    widget.onDownloadRequested(url, filename);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTab.catalog.palette;

    return Dialog(
      backgroundColor: kBgColor,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            _BrowserBar(
              title: widget.title,
              url: _currentUrl,
              loading: _loading,
              palette: palette,
              onClose: () => Navigator.of(context).pop(),
              onBack: () => _controller?.goBack(),
              onRefresh: () => _controller?.reload(),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
                child: !_envReady
                    ? Center(child: CircularProgressIndicator(color: palette.primary))
                    : Stack(children: [
                  InAppWebView(
                  webViewEnvironment: _webViewEnvironment,
                  initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                  initialSettings: InAppWebViewSettings(
                    useOnDownloadStart: true,
                    useShouldOverrideUrlLoading: true,
                    javaScriptEnabled: true,
                  ),
                  onWebViewCreated: (c) {
                    _controller = c;
                    // Google Photos' Download menu item was clicked: fire a
                    // real Shift+D so the page's own (working) shortcut runs.
                    c.addJavaScriptHandler(
                      handlerName: 'mDownloadClick',
                      callback: (args) {
                        Future.delayed(const Duration(milliseconds: 150), KeyInjector.sendShiftD);
                        return null;
                      },
                    );
                  },
                  onLoadStart: (_, url) => setState(() {
                    _loading = true;
                    _currentUrl = url?.toString() ?? _currentUrl;
                  }),
                  onLoadStop: (c, url) async {
                    setState(() {
                      _loading = false;
                      _currentUrl = url?.toString() ?? _currentUrl;
                    });
                    // Inject the Download-click detector after each page load
                    // (AT_DOCUMENT_START injection doesn't run on Windows).
                    try {
                      await c.evaluateJavascript(source: _downloadInterceptScript);
                    } catch (_) {}
                  },
                  // Catches direct video URL navigations and mdownload:// fallback signals.
                  shouldOverrideUrlLoading: (_, action) async {
                    final url = action.request.url?.toString() ?? '';
                    if (url.startsWith('mdownload://')) {
                      final uri = Uri.parse(url);
                      final downloadUrl = Uri.decodeComponent(
                          uri.queryParameters['url'] ?? '');
                      final filename = Uri.decodeComponent(
                          uri.queryParameters['n'] ?? '');
                      if (downloadUrl.isNotEmpty) {
                        _triggerDownload(downloadUrl,
                            suggestedFilename:
                                filename.isNotEmpty ? filename : null);
                      }
                      return NavigationActionPolicy.CANCEL;
                    }
                    if (_isVideoUrl(url)) {
                      _triggerDownload(url);
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  // Catches window.open() popup download attempts.
                  onCreateWindow: (_, action) async {
                    final url = action.request.url?.toString() ?? '';
                    if (url.isNotEmpty) {
                      if (_isVideoUrl(url)) {
                        _triggerDownload(url);
                      } else {
                        _controller?.loadUrl(urlRequest: action.request);
                      }
                    }
                    return true;
                  },
                  // Catches HTTP Content-Disposition downloads (Shift+D path).
                  onDownloadStartRequest: (_, req) {
                    _triggerDownload(
                      req.url.toString(),
                      suggestedFilename: req.suggestedFilename,
                    );
                  },
                ),
                  if (_loading)
                    Container(
                      color: kBgColor,
                      child: Center(child: CircularProgressIndicator(color: palette.primary)),
                    ),
                  ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _BrowserBar extends StatelessWidget {
  final String title;
  final String url;
  final bool loading;
  final TabPalette palette;
  final VoidCallback onClose;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  const _BrowserBar({
    required this.title,
    required this.url,
    required this.loading,
    required this.palette,
    required this.onClose,
    required this.onBack,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: kBorderColor)),
      ),
      child: Row(
        children: [
          _BarButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          _BarButton(
            icon: loading ? Icons.close_rounded : Icons.refresh_rounded,
            onTap: onRefresh,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: kSurface2Color,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                url.isNotEmpty ? url : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: kTextMuted),
              ),
            ),
          ),
          _BarButton(icon: Icons.close_rounded, onTap: onClose),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _BarButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: kTextMuted),
      ),
    );
  }
}
