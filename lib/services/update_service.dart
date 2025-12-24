import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // Replace with actual API endpoint
  static const String UPDATE_URL = "https://api.ednovas.com/client/update";

  static Future<Map<String, dynamic>?> checkUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Mock response for now if URL fails or for testing
      // Remove this when API is ready
      // return {
      //   'hasUpdate': true,
      //   'version': '1.0.1',
      //   'url': 'https://example.com',
      //   'note': 'Fix bugs'
      // };

      final response = await http.get(Uri.parse(UPDATE_URL));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final remoteVersion = data['version'];
        if (_compareVersions(remoteVersion, currentVersion) > 0) {
          return data;
        }
      }
    } catch (e) {
      print("Update check failed: $e");
    }
    return null;
  }

  static int _compareVersions(String v1, String v2) {
    try {
      List<int> v1Parts = v1.split('.').map(int.parse).toList();
      List<int> v2Parts = v2.split('.').map(int.parse).toList();

      for (int i = 0; i < v1Parts.length && i < v2Parts.length; i++) {
        if (v1Parts[i] > v2Parts[i]) return 1;
        if (v1Parts[i] < v2Parts[i]) return -1;
      }
      if (v1Parts.length > v2Parts.length) return 1;
      if (v1Parts.length < v2Parts.length) return -1;
      return 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<void> launchUpdateUrl(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
