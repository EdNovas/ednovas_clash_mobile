import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A modal WebView sheet that persists login sessions and cookies.
///
/// The webview_flutter package on Android/iOS automatically persists
/// cookies and localStorage across app restarts (uses system WebView).
class WebviewSheet extends StatefulWidget {
  final String url;
  final String title;

  const WebviewSheet({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<WebviewSheet> createState() => _WebviewSheetState();
}

class _WebviewSheetState extends State<WebviewSheet> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadingProgress = 0;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      // Enable JavaScript for full functionality
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Set dark background to match app theme
      ..setBackgroundColor(const Color(0xFF141414))
      // Set User Agent to ensure proper site rendering
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      // Configure navigation delegate for loading states
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress / 100;
                if (progress == 100) {
                  _isLoading = false;
                }
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _loadingProgress = 0;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (error) {
            print('WebView Error: ${error.description}');
          },
        ),
      )
      // Load the requested URL
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() => _isLoading = true);
              _controller.reload();
            },
          ),
        ],
        // Show loading progress bar under AppBar
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0 ? _loadingProgress : null,
                  backgroundColor: Colors.transparent,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          // Show loading overlay only during initial load
          if (_isLoading && _loadingProgress == 0)
            Container(
              color: const Color(0xFF141414),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.blueAccent),
              ),
            ),
        ],
      ),
    );
  }
}
