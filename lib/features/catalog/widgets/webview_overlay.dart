import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tab_colors.dart';

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
}

class _WebViewOverlayState extends State<WebViewOverlay> {
  InAppWebViewController? _controller;
  String _currentUrl = '';
  bool _loading = true;

  static const _videoExts = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v'};

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    if (_videoExts.any((ext) => lower.contains(ext))) return true;
    // Any top-level navigation to googleusercontent.com from a Photos page is a
    // file/video download (subresources like thumbnails don't fire shouldOverrideUrlLoading).
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
    Navigator.of(context).pop();
    final filename = (suggestedFilename?.isNotEmpty == true)
        ? suggestedFilename!
        : (_suggestFilename(url) ?? '${widget.title}.mp4');
    widget.onDownloadRequested(url, filename);
  }

  Future<void> _handleGoldenDownload() async {
    String url = _currentUrl;
    try {
      final result = await _controller?.evaluateJavascript(source: '''
        (function(){
          var v = document.querySelector('video');
          if (v && v.src && v.src.startsWith('http')) return v.src;
          var s = document.querySelector('video source');
          if (s && s.src && s.src.startsWith('http')) return s.src;
          return '';
        })()
      ''');
      final extracted = (result?.toString() ?? '').replaceAll('"', '').trim();
      if (extracted.isNotEmpty && extracted != 'null') url = extracted;
    } catch (_) {}
    _triggerDownload(url);
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
              onDownload: () { _handleGoldenDownload(); },
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                  initialSettings: InAppWebViewSettings(
                    useOnDownloadStart: true,
                    useShouldOverrideUrlLoading: true,
                    javaScriptEnabled: true,
                  ),
                  onWebViewCreated: (c) => _controller = c,
                  onLoadStart: (_, url) => setState(() {
                    _loading = true;
                    _currentUrl = url?.toString() ?? _currentUrl;
                  }),
                  onLoadStop: (_, url) => setState(() {
                    _loading = false;
                    _currentUrl = url?.toString() ?? _currentUrl;
                  }),
                  // Intercept navigations that are direct video/download URLs.
                  shouldOverrideUrlLoading: (_, action) async {
                    final url = action.request.url?.toString() ?? '';
                    if (_isVideoUrl(url)) {
                      _triggerDownload(url);
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  // Fallback: fires for HTTP Content-Disposition downloads.
                  onDownloadStartRequest: (_, req) {
                    _triggerDownload(
                      req.url.toString(),
                      suggestedFilename: req.suggestedFilename,
                    );
                  },
                ),
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
  final VoidCallback onDownload;

  const _BrowserBar({
    required this.title,
    required this.url,
    required this.loading,
    required this.palette,
    required this.onClose,
    required this.onBack,
    required this.onRefresh,
    required this.onDownload,
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
          const SizedBox(width: 8),
          Tooltip(
            message: 'Download via app',
            child: _BarButton(
              icon: Icons.download_rounded,
              onTap: onDownload,
              color: palette.primary,
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
  final Color? color;
  const _BarButton({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color ?? kTextMuted),
      ),
    );
  }
}
