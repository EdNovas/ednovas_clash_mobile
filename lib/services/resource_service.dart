import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

class ResourceService {
  static Future<void> checkAndInstallMMDB() async {
    // Note: getApplicationDocumentsDirectory allows persistent storage.
    // Ensure we are using the same dir logic as ClashVpnService.
    // If ClashVpnService uses `filesDir` (context.getFilesDir()), that matches `getApplicationSupportDirectory` on some versions or `getApplicationDocumentsDirectory`.
    // Let's stick to what we used before: getApplicationDocumentsDirectory() was used in config, wait.
    // In previous steps for config saving we used `getApplicationDocumentsDirectory`.
    // But for Clash home dir in Native it was `context.filesDir`.
    // Flutter `getApplicationSupportDirectory` -> `files` directory.
    // Flutter `getApplicationDocumentsDirectory` -> `app_flutter` directory (which is distinct from `files`).

    // CRITICAL: configuration injection (v3) used `getApplicationDocumentsDirectory` (/data/user/0/.../app_flutter/config.yaml).
    // The native code `ClashVpnService.kt` v3 fix received a path.
    // BUT the MMDB file needs to be in the "Home Directory" of Clash.
    // In `ClashVpnService.kt`: `val homeDir = File(context.filesDir, "clash")`.
    // So we need to put MMDB into `RunningContext.filesDir/clash/Country.mmdb`.
    // Dart `getApplicationSupportDirectory` maps to `Context.getFilesDir()` on Android.

    final supportDir = await getApplicationSupportDirectory();
    final clashDir = Directory('${supportDir.path}/clash');

    if (!await clashDir.exists()) {
      await clashDir.create(recursive: true);
    }

    // List of files to install
    final files = ['Country.mmdb', 'geoip.dat', 'geosite.dat', 'geoip.metadb'];

    for (final fileName in files) {
      final file = File('${clashDir.path}/$fileName');
      if (!await file.exists()) {
        print('Installing $fileName from assets...');
        try {
          final data = await rootBundle.load('assets/$fileName');
          final bytes = data.buffer.asUint8List();
          await file.writeAsBytes(bytes, flush: true);
          print('$fileName installed successfully');
        } catch (e) {
          print('Error installing $fileName: $e');
        }
      } else {
        print('$fileName exists');
      }
    }
  }
}
