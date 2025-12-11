import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/proxy_model.dart';
import 'config_parser_service.dart';
import 'resource_service.dart';

class ClashService {
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // In-memory cache of groups (Simulating Core State)
  List<ProxyGroup> _cachedGroups = [];

  static const platform = MethodChannel('com.ednovas.clash/vpn');

  Future<void> start() async {
    await ResourceService.checkAndInstallMMDB();
    try {
      final prefs = await SharedPreferences.getInstance();
      String configContent = prefs.getString('cached_config_content') ?? '';

      // Helper to remove top-level keys safely (handling indentation)
      String removeKey(String content, String key) {
        return content.replaceAll(
            RegExp(r'^' + key + r':(?:[ \t].*|)\n(?:[ \t]+.*\n)*',
                multiLine: true),
            '');
      }

      // 1. Strip conflicting keys to clean the slate
      configContent = removeKey(configContent, 'external-controller');
      configContent = removeKey(configContent, 'secret');
      configContent = removeKey(configContent, 'log-level');
      configContent = removeKey(configContent, 'log-file');
      configContent = removeKey(configContent, 'ipv6');
      configContent = removeKey(configContent, 'tun');
      configContent = removeKey(configContent, 'dns');
      configContent = removeKey(configContent, 'mode');
      configContent = removeKey(configContent, 'allow-lan');
      configContent = removeKey(configContent, 'unified-delay');
      configContent = removeKey(configContent, 'global-client-fingerprint');

      // 2. Determine Log Path
      final supportDir = await getApplicationSupportDirectory();
      final logPath = '${supportDir.path}/clash/clash_core.log';

      // 3. Construct the Header (Infrastructure)
      // Note: We disable 'tun' here because it is managed by the native layer.
      final String infrastructureConfig = '''
external-controller: 127.0.0.1:9090
secret: ''
log-level: debug
log-file: '$logPath'
ipv6: false
allow-lan: false
mode: rule
unified-delay: true
global-client-fingerprint: chrome
tun:
  enable: false
  stack: gvisor
  auto-route: false
  dns-hijack:
    - 8.8.8.8:53
    - tcp://8.8.8.8:53
    - 172.19.0.2:53
    - tcp://172.19.0.2:53
    - 1.1.1.1:53
    - tcp://1.1.1.1:53

sniffer:
  enable: true
  sniff:
    TLS:
      ports: [443]
    HTTP:
      ports: [80, 8080-8880]
''';

      // 4. Construct DNS (Crucial for Mobile/Fake-IP)
      const String dnsConfig = '''
dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  default-nameserver:
    - 223.5.5.5
    - 8.8.8.8
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://8.8.4.4:853
  fallback-filter:
    geoip: true
    ipcidr:
      - 240.0.0.0/4
''';

      // 5. Merge
      configContent = '$infrastructureConfig\n$dnsConfig\n$configContent';

      // Save config
      final supportDirDir = Directory('${supportDir.path}/clash');
      if (!await supportDirDir.exists()) {
        await supportDirDir.create(recursive: true);
      }
      final configFile = File('${supportDir.path}/clash/config.yaml');
      await configFile.writeAsString(configContent);

      print('Config Path: ${configFile.path}');

      await platform.invokeMethod('start', {'config_path': configFile.path});
      _isRunning = true;
      print(
          'Core Started via MethodChannel with Config File: ${configFile.path}');

      // Start Log Tailing
      _startLogTailing(File(logPath));
    } catch (e) {
      print('Failed to start core: $e');
      _isRunning = true; // Still mock running state for UI
    }
  }

  void _startLogTailing(File logFile) {
    print('Starting Log Tailing for: ${logFile.path}');
    int lastSize = 0;
    if (logFile.existsSync()) {
      lastSize = logFile.lengthSync();
    }

    // Check every 2 seconds
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 2));
      if (!_isRunning) return false;

      if (await logFile.exists()) {
        final length = await logFile.length();
        if (length > lastSize) {
          try {
            final stream = logFile.openRead(lastSize, length);
            stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .listen((line) {
              print('[Clash Core] $line');
            });
            lastSize = length;
          } catch (e) {
            print('Log Read Error: $e');
          }
        }
      }
      return _isRunning;
    });
  }

  Future<void> stop() async {
    try {
      await platform.invokeMethod('stop');
      _isRunning = false;
    } catch (e) {
      print('Failed to stop core: $e');
      _isRunning = false;
    }
  }

  Future<bool> checkStatus() async {
    try {
      final bool isRunning = await platform.invokeMethod('status');
      _isRunning = isRunning;
      return isRunning;
    } catch (e) {
      print('Status check failed: $e');
      return false;
    }
  }

  // Parse and Save Config
  Future<void> updateConfig(String yamlContent) async {
    final result = await ConfigParserService.parseConfig(yamlContent);
    _cachedGroups = result.groups;

    // Save Order to Prefs
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('group_order', result.groupOrder);
    await prefs.setString('cached_config_content', yamlContent);
  }

  // Get Groups (Simulating API /proxies)
  Future<List<ProxyGroup>> getProxyGroups() async {
    // If we have cached groups from a recent update, return them
    if (_cachedGroups.isNotEmpty) {
      return _cachedGroups;
    }

    // Otherwise try mock data or empty
    return [
      // Keep mock data as fallback until first update
      ProxyGroup(
          name: 'Auto Select',
          type: 'url-test',
          nodes: _generateNodes('Auto', 5)),
      ProxyGroup(
          name: 'Global',
          type: 'select',
          nodes: _generateNodes('Global', 10),
          now: 'Global Node 1'),
      ProxyGroup(
          name: 'Streaming',
          type: 'select',
          nodes: _generateNodes('Stream', 8)),
    ];
  }

  List<ProxyNode> _generateNodes(String prefix, int count) {
    return List.generate(
        count,
        (index) => ProxyNode(
              name: '$prefix Node ${index + 1}',
              type: 'Shadowsocks',
              delay: index * 50 + 20,
            ));
  }

  // Update local memory cache only
  void _updateLocalCache(String groupName, String nodeName) {
    final index = _cachedGroups.indexWhere((g) => g.name == groupName);
    if (index == -1) return;

    final oldGroup = _cachedGroups[index];
    final newGroup = ProxyGroup(
        name: oldGroup.name,
        type: oldGroup.type,
        nodes: oldGroup.nodes,
        now: nodeName);
    _cachedGroups[index] = newGroup;
  }

  // Call Clash API to change proxy
  Future<void> selectProxy(String groupName, String nodeName) async {
    try {
      final encodedGroup = Uri.encodeComponent(groupName);
      final url = Uri.parse('http://127.0.0.1:9090/proxies/$encodedGroup');

      final response = await http.put(
        url,
        body: json.encode({'name': nodeName}),
      );

      if (response.statusCode != 204) {
        throw Exception('API Failed: ${response.statusCode} ${response.body}');
      }

      // Update local cache if API success
      _updateLocalCache(groupName, nodeName);
    } catch (e) {
      print('Select Proxy Failed: $e');
      rethrow;
    }
  }

  // Call Clash API to change mode
  Future<void> changeMode(String mode) async {
    try {
      final url = Uri.parse('http://127.0.0.1:9090/configs');
      final response = await http.patch(
        url,
        body: json.encode({'mode': mode}),
      );
      if (response.statusCode != 204) {
        print('Change Mode Failed: ${response.statusCode} ${response.body}');
      } else {
        print('Mode changed to $mode');
      }
    } catch (e) {
      print('Change Mode Error: $e');
    }
  }
}
