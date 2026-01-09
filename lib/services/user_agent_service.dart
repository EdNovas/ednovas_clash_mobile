import 'package:package_info_plus/package_info_plus.dart';

/// Unified User-Agent service for all HTTP requests
/// Format: EdNovasClashMobile/x.x.x
class UserAgentService {
  static final UserAgentService _instance = UserAgentService._internal();
  factory UserAgentService() => _instance;
  UserAgentService._internal();

  String? _userAgent;
  String? _version;

  /// Get the User-Agent string (EdNovasClashMobile/version)
  /// Must call init() first, or will return default value
  String get userAgent => _userAgent ?? 'EdNovasClashMobile';

  /// Get just the version string
  String get version => _version ?? 'unknown';

  /// Initialize the service (call once at app startup)
  Future<void> init() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _version = packageInfo.version;
      _userAgent = 'EdNovasClashMobile/${packageInfo.version}';
      print('✅ UserAgent initialized: $_userAgent');
    } catch (e) {
      print('⚠️ Failed to get package info: $e');
      _version = 'unknown';
      _userAgent = 'EdNovasClashMobile';
    }
  }

  /// Get User-Agent as a Map for headers
  Map<String, String> get headers => {'User-Agent': userAgent};
}
