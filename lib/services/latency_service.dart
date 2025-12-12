import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Global latency cache and background testing service
class LatencyService {
  static final LatencyService _instance = LatencyService._internal();
  factory LatencyService() => _instance;
  LatencyService._internal();

  // Cache: nodeName -> delay (ms), -1 for error
  final Map<String, int> _latencyCache = {};

  // Listeners for UI updates
  final List<void Function()> _listeners = [];

  // Track ongoing test
  bool _isTesting = false;
  bool get isTesting => _isTesting;

  // Cooldown: minimum 10 seconds between tests
  DateTime? _lastTestTime;
  static const Duration _testCooldown = Duration(seconds: 10);

  // Store all node names for auto-test at startup
  List<String> _allNodeNames = [];

  // Track if auto-test has been done (only once per login session)
  bool _hasAutoTested = false;
  bool get hasAutoTested => _hasAutoTested;

  /// Check if test is allowed (cooldown passed)
  bool get canTest {
    if (_isTesting) return false;
    if (_lastTestTime == null) return true;
    return DateTime.now().difference(_lastTestTime!) >= _testCooldown;
  }

  /// Get remaining cooldown seconds
  int get cooldownRemaining {
    if (_lastTestTime == null) return 0;
    final elapsed = DateTime.now().difference(_lastTestTime!);
    final remaining = _testCooldown - elapsed;
    return remaining.isNegative ? 0 : remaining.inSeconds;
  }

  /// Get cached latency for a node
  int? getLatency(String nodeName) => _latencyCache[nodeName];

  /// Set latency for a node
  void setLatency(String nodeName, int delay) {
    _latencyCache[nodeName] = delay;
    _notifyListeners();
  }

  /// Add a listener for cache updates
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  /// Register all node names (called when config is loaded)
  void registerAllNodes(List<String> nodeNames) {
    _allNodeNames = nodeNames;
  }

  /// Auto-test all registered nodes (only once per login session)
  Future<void> testAllNodes() async {
    // Only auto-test once per login session
    if (_hasAutoTested) {
      print('Auto latency test already done this session, skipping...');
      return;
    }

    if (_allNodeNames.isEmpty) {
      print('No nodes registered for latency test');
      return;
    }

    _hasAutoTested = true;
    await testNodesLatency(_allNodeNames, forceTest: true);
  }

  /// Reset auto-test flag (call when user logs out)
  void resetAutoTest() {
    _hasAutoTested = false;
    _latencyCache.clear();
  }

  /// Test latency for a list of nodes in the background
  Future<void> testNodesLatency(List<String> nodeNames,
      {bool forceTest = false}) async {
    if (_isTesting) {
      print('Latency test already in progress, skipping...');
      return;
    }

    // Check cooldown (unless forced)
    if (!forceTest && !canTest) {
      print('Cooldown active. ${cooldownRemaining}s remaining.');
      return;
    }

    _isTesting = true;
    _notifyListeners(); // Notify UI that testing started
    print('Starting background latency test for ${nodeNames.length} nodes...');

    // Check if API is responsive first
    try {
      await http
          .get(Uri.parse('http://127.0.0.1:9090'))
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      print('API Root Check Failed: $e');
      _isTesting = false;
      _notifyListeners(); // Notify UI that testing stopped
      return;
    }

    // Test in batches of 5
    for (var i = 0; i < nodeNames.length; i += 5) {
      final end = (i + 5 < nodeNames.length) ? i + 5 : nodeNames.length;
      final batch = nodeNames.sublist(i, end);

      await Future.wait(batch.map((nodeName) async {
        if (nodeName.isEmpty) return;
        if (_latencyCache.containsKey(nodeName))
          return; // Skip if already cached

        try {
          final url = Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: 9090,
            pathSegments: ['proxies', nodeName, 'delay'],
            queryParameters: {
              'timeout': '5000',
              'url': 'http://www.gstatic.com/generate_204'
            },
          );

          final response =
              await http.get(url).timeout(const Duration(seconds: 3));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final delay = data['delay'] as int?;
            if (delay != null) {
              setLatency(nodeName, delay);
            }
          } else {
            setLatency(nodeName, -1);
          }
        } catch (e) {
          setLatency(nodeName, -1);
        }
      }));

      // Small delay between batches
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _isTesting = false;
    _lastTestTime = DateTime.now(); // Record time for cooldown
    _notifyListeners(); // Notify UI that testing completed
    print('Background latency test completed.');
  }

  /// Clear all cached latencies
  void clearCache() {
    _latencyCache.clear();
    _notifyListeners();
  }
}
