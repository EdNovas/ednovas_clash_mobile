import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  Dio _dio = Dio();
  String? baseUrl;

  // Remote config URLs (try to fetch candidate URLs from these)
  static const List<String> _remoteConfigUrls = [
    'https://raw.githubusercontent.com/EdNovas/config/refs/heads/main/domains.json',
    'https://aaa.ednovas.xyz/domains.json',
  ];

  // Hardcoded backup list (used if remote fetch fails)
  static const List<String> _defaultBackups = [
    'https://new.ednovas.dev',
    'https://new.ednovas.org',
    'https://cdn.ednovas.world',
  ];

  // Dynamic candidate URLs (populated from remote + defaults)
  List<String> _candidateUrls = [];

  // Expose candidate URLs for external access
  List<String> get candidateUrls =>
      _candidateUrls.isEmpty ? _defaultBackups : _candidateUrls;

  // Track failed URLs for intelligent retry
  final Set<String> _failedUrls = {};

  // Store URLs that passed latency test (sorted by speed)
  List<String> _workingUrls = [];

  // Track current URL index for round-robin rotation
  int _currentUrlIndex = 0;

  ApiService() {
    // Migration Guide 1.2: Increased timeout settings (10s -> 30s)
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);

    // Initialize with defaults
    _candidateUrls = List.from(_defaultBackups);
  }

  Future<void> init() async {
    // Try to fetch remote config first
    await _fetchRemoteConfig();

    // Guide 1.1: Dynamic Node Selection on Startup
    await findFastestUrl();
  }

  // Fetch candidate URLs from remote JSON config
  Future<void> _fetchRemoteConfig() async {
    print('🔍 尝试从远程获取节点配置...');

    final tempDio = Dio()
      ..options.connectTimeout = const Duration(seconds: 5)
      ..options.receiveTimeout = const Duration(seconds: 5);

    for (final configUrl in _remoteConfigUrls) {
      try {
        print('  尝试: $configUrl');
        final response = await tempDio.get(configUrl);

        if (response.statusCode == 200) {
          dynamic data = response.data;

          // Handle if response is string (needs parsing)
          if (data is String) {
            data = json.decode(data);
          }

          // Support both array format and object with 'domains' key
          List<String> urls = [];
          if (data is List) {
            urls = data.map((e) => e.toString()).toList();
          } else if (data is Map && data['domains'] != null) {
            urls = (data['domains'] as List).map((e) => e.toString()).toList();
          }

          if (urls.isNotEmpty) {
            // Merge with defaults, removing duplicates
            final allUrls = <String>{..._defaultBackups, ...urls};
            _candidateUrls = allUrls.toList();
            print('✅ 远程配置加载成功，共 ${_candidateUrls.length} 个节点');
            return;
          }
        }
      } catch (e) {
        print('  ⚠️ 获取失败: $e');
      }
    }

    print('ℹ️ 使用默认节点配置 (${_defaultBackups.length} 个)');
    _candidateUrls = List.from(_defaultBackups);
  }

  // Switch to a different API URL (for retry logic)
  // Prioritizes URLs that passed the latency test
  Future<bool> switchToNextUrl() async {
    // Use working URLs if available, otherwise fall back to all candidates
    final urls = _workingUrls.isNotEmpty ? _workingUrls : candidateUrls;

    // Try round-robin through working URLs
    for (int i = 0; i < urls.length; i++) {
      _currentUrlIndex = (_currentUrlIndex + 1) % urls.length;
      final nextUrl = urls[_currentUrlIndex];

      if (!_failedUrls.contains(nextUrl) && nextUrl != baseUrl) {
        print('🔄 切换到节点 [${_currentUrlIndex + 1}/${urls.length}]: $nextUrl');
        await setBaseUrl(nextUrl);
        return true;
      }
    }

    // All working URLs have been tried
    print('⚠️ 所有可用节点都已尝试，重置');
    _failedUrls.clear();
    _currentUrlIndex = 0;

    return false;
  }

  // Mark current URL as failed
  void markCurrentUrlFailed() {
    if (baseUrl != null) {
      _failedUrls.add(baseUrl!);
      print(
          '❌ 标记节点失败: $baseUrl (已失败 ${_failedUrls.length}/${candidateUrls.length})');
    }
  }

  // Guide 1.1: Polling / Node Selection Logic
  // Tests all candidate URLs and stores working ones sorted by speed
  Future<String> findFastestUrl() async {
    try {
      print('🔍 测试所有节点延迟...');
      final results =
          await Future.wait(candidateUrls.map((url) => _checkLatency(url)));
      final successful = results.where((e) => e != null).toList();

      if (successful.isEmpty) {
        print('⚠️ 所有节点延迟测试失败，使用默认节点');
        _workingUrls = [];
        final fallback = 'https://new.ednovas.dev';
        await setBaseUrl(fallback);
        return fallback;
      }

      // Sort by latency (fastest first)
      successful.sort((a, b) => a!.duration.compareTo(b!.duration));

      // Store all working URLs for retry priority
      _workingUrls = successful.map((e) => e!.url).toList();
      _currentUrlIndex = 0;

      print('✅ 延迟测试完成，${_workingUrls.length}/${candidateUrls.length} 个节点可用');
      for (int i = 0; i < _workingUrls.length && i < 3; i++) {
        print('   ${i + 1}. ${_workingUrls[i]} (${successful[i]!.duration}ms)');
      }

      final bestUrl = _workingUrls.first;
      await setBaseUrl(bestUrl);
      return bestUrl;
    } catch (e) {
      // Fallback
      print('⚠️ 延迟测试异常: $e');
      return 'https://new.ednovas.dev';
    }
  }

  // Guide 1.1: Latency Test
  Future<_LatencyResult?> _checkLatency(String url) async {
    final start = DateTime.now();
    try {
      await _dio.get('$url/api/v1/guest/comm/config',
          options: Options(
              responseType: ResponseType.json,
              sendTimeout: const Duration(milliseconds: 3000),
              receiveTimeout: const Duration(milliseconds: 3000)));
      final duration = DateTime.now().difference(start).inMilliseconds;
      return _LatencyResult(url, duration);
    } catch (e) {
      return null;
    }
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url;
    _dio.options.baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_url', url);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  // Guide 2.1: Login
  Future<Map<String, dynamic>> login(String email, String password) async {
    if (baseUrl == null) await findFastestUrl();

    try {
      final response = await _dio.post(
        '/api/v1/passport/auth/login',
        data: {'email': email, 'password': password},
        options: Options(
            validateStatus: (status) => status! < 500,
            responseType: ResponseType.json),
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception(
            'Invalid server response (Status ${response.statusCode}). Expected JSON.');
      }

      if (response.statusCode == 200 && data['data'] != null) {
        final token = data['data']['auth_data'];
        await saveToken(token);
        return data['data'];
      } else {
        throw Exception(
            data['message'] ?? 'Login failed (${response.statusCode})');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Guide 2.3: Get Subscribe Info (basic version)
  Future<Map<String, dynamic>> getSubscribe() async {
    final token = await getToken();
    if (token == null) throw Exception('Not logged in');

    try {
      // Guide 2.3: Add 'auth_data' to query param AND header
      final response = await _dio.get(
        '/api/v1/user/getSubscribe',
        queryParameters: {'auth_data': token},
        options: Options(
          headers: {'Authorization': token},
        ),
      );

      if (response.statusCode == 200) {
        return response.data['data'];
      } else {
        throw Exception('Failed to get subscription info');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Guide 2.3+: Get Subscribe Info with automatic retry and URL switching
  // Max 3 retries, prioritizing nodes that passed latency test
  Future<Map<String, dynamic>> getSubscribeWithRetry(
      {int maxRetries = 3}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not logged in');

    Exception? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🚀 获取订阅... (尝试 $attempt/$maxRetries, 节点: $baseUrl)');

        final response = await _dio.get(
          '/api/v1/user/getSubscribe',
          queryParameters: {'auth_data': token},
          options: Options(
            headers: {'Authorization': token},
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

        if (response.statusCode == 200) {
          print('✅ 订阅获取成功');
          return response.data['data'];
        } else {
          throw Exception('Failed with status ${response.statusCode}');
        }
      } catch (e) {
        lastError = Exception('$e');
        print('⚠️ 获取订阅失败: $e');

        // Mark current URL as failed and try switching
        markCurrentUrlFailed();

        if (attempt < maxRetries) {
          final switched = await switchToNextUrl();
          if (switched) {
            print('🔄 切换到备用节点: $baseUrl');
          } else {
            print('⏳ 等待 2 秒后重试...');
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
    }

    throw lastError ?? Exception('获取订阅失败');
  }

  // Get User General Info (includes plan name)
  Future<Map<String, dynamic>> getUserInfo() async {
    final token = await getToken();
    if (token == null) throw Exception('Not logged in');

    try {
      final response = await _dio.get(
        '/api/v1/user/info',
        options: Options(
          headers: {'Authorization': token},
        ),
      );

      if (response.statusCode == 200) {
        return response.data['data'];
      } else {
        throw Exception('Failed to get user info');
      }
    } catch (e) {
      print('Get user info error: $e');
      return {}; // Return empty map on failure to not break flow
    }
  }

  // Guide 3.1 & 3.2: Construct and Download Config
  Future<String> fetchConfigContent(String input) async {
    if (baseUrl == null) await findFastestUrl();

    String finalUrl;
    // If input looks like a full URL, use it directly (but maybe add flag)
    if (input.startsWith('http')) {
      finalUrl = input;
      if (!finalUrl.contains('flag=clash')) {
        finalUrl += (finalUrl.contains('?') ? '&' : '?') + 'flag=clash';
      }
    } else {
      // Construct from token
      final cleanApiUrl = baseUrl!.replaceAll(RegExp(r'/$'), '');
      finalUrl = '$cleanApiUrl/2cvme3wa8i/$input?flag=clash';
    }

    try {
      final Dio downloadDio = Dio();
      final response = await downloadDio.get(finalUrl,
          options: Options(
              headers: {'User-Agent': 'ClashforWindows/0.19.0'},
              responseType: ResponseType.plain));
      return response.data.toString();
    } catch (e) {
      throw Exception('Failed to download config ($finalUrl): $e');
    }
  }
}

class _LatencyResult {
  final String url;
  final int duration;
  _LatencyResult(this.url, this.duration);
}
