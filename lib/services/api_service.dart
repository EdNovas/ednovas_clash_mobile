import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  Dio _dio = Dio();
  String? baseUrl;

  // Migration Guide 1.1: Candidate URLs
  static const List<String> _candidateUrls = [
    'https://new.ednovas.dev', // Default
    'https://new.ednovas.org',
    'https://cdn.ednovas.world',
  ];

  ApiService() {
    // Migration Guide 1.2: Timeout settings
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
  }

  Future<void> init() async {
    // Guide 1.1: Dynamic Node Selection on Startup
    await findFastestUrl();
  }

  // Guide 1.1: Polling / Node Selection Logic
  Future<String> findFastestUrl() async {
    try {
      final results =
          await Future.wait(_candidateUrls.map((url) => _checkLatency(url)));
      final successful = results.where((e) => e != null).toList();

      if (successful.isEmpty) {
        final fallback = 'https://new.ednovas.dev';
        await setBaseUrl(fallback);
        return fallback;
      }

      successful.sort((a, b) => a!.duration.compareTo(b!.duration));

      final bestUrl = successful.first!.url;
      await setBaseUrl(bestUrl);
      return bestUrl;
    } catch (e) {
      // Fallback
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

  // Guide 2.3: Get Subscribe Info
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
