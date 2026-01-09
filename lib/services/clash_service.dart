import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/proxy_model.dart';
import 'config_parser_service.dart';
import 'resource_service.dart';
import 'latency_service.dart';
import 'user_agent_service.dart';

import 'dart:async'; // Add this

class ClashService {
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  StreamSubscription? _trafficSubscription;

  // Current proxy mode (rule, global, direct)
  String _currentMode = 'rule';
  String get currentMode => _currentMode;

  // In-memory cache of groups (Simulating Core State)
  List<ProxyGroup> _cachedGroups = [];

  static const platform = MethodChannel('com.ednovas.clash/vpn');

  Future<void> start() async {
    await ResourceService.checkAndInstallMMDB();
    try {
      final prefs = await SharedPreferences.getInstance();
      String configContent = prefs.getString('cached_config_content') ?? '';

      if (configContent.isEmpty) {
        throw Exception(
          'No configuration found. Please update subscription first.',
        );
      }

      // Helper to remove top-level keys safely (handling indentation and CRLF)
      String removeKey(String content, String key) {
        // Matches "key: ..." followed by any number of indented lines or empty lines
        return content.replaceAll(
          RegExp(
            r'^' + key + r':[^\n\r]*(\r?\n|\r)((?:[ \t]+.*|)(\r?\n|\r))*',
            multiLine: true,
          ),
          '',
        );
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

      // Load saved mode
      _currentMode = prefs.getString('proxy_mode') ?? 'rule';

      // 3. Construct the Header (Infrastructure)
      final String infrastructureConfig = '''
external-controller: 127.0.0.1:9090
secret: ''
log-level: info
log-file: '$logPath'
ipv6: false
allow-lan: false
mode: $_currentMode
unified-delay: true
global-client-fingerprint: chrome

tun:
  enable: true
  stack: gvisor
  auto-route: false
  auto-redirect: false
  auto-detect-interface: false

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

      // 5. Merge (Put overrides FIRST to ensure they take precedence if parser uses First-Wins)
      configContent = '$infrastructureConfig\n$dnsConfig\n$configContent';

      // DEBUG: Print final config
      print(
        'GENERATED CONFIG HEAD: \n${configContent.substring(0, configContent.length > 500 ? 500 : configContent.length)}',
      );
      try {
        print(
          'GENERATED CONFIG TAIL: \n${configContent.substring(configContent.length > 500 ? configContent.length - 500 : 0)}',
        );
      } catch (e) {
        print('Error printing tail: $e');
      }

      // Save config
      final supportDirDir = Directory('${supportDir.path}/clash');
      if (!await supportDirDir.exists()) {
        await supportDirDir.create(recursive: true);
      }
      final configFile = File('${supportDir.path}/clash/config.yaml');
      await configFile.writeAsString(configContent);

      print('Config Path: ${configFile.path}');
      print('Starting Clash Core...');

      try {
        await platform.invokeMethod('start', {'config_path': configFile.path});
        _isRunning = true;
        print(
          'Core Started via MethodChannel with Config File: ${configFile.path}',
        );

        // Start Log Tailing
        _startLogTailing(File(logPath));

        // Wait for core to become ready (Polling)
        int retry = 0;
        while (retry < 20) {
          if (await testClashApi()) break;
          await Future.delayed(const Duration(milliseconds: 500));
          retry++;
        }

        // Set default nodes for all select groups via API
        _setDefaultNodesViaAPI();

        // Auto-test latency for all nodes after startup
        _autoTestLatency();
        _startTrafficMonitoringForNotification();
      } on PlatformException catch (e) {
        print('Platform Exception: ${e.code} - ${e.message}');
        if (e.code == 'PERMISSION_DENIED') {
          _isRunning = false;
          rethrow;
        } else if (e.code == 'PERMISSION_REQUIRED') {
          print('VPN Permission requested, waiting for user...');
          // The service will start after permission is granted
          // Check status after a delay
          await Future.delayed(const Duration(seconds: 3));
          _isRunning = await checkStatus();
          if (_isRunning) {
            await _setDefaultNodesViaAPI();
          }
        } else {
          _isRunning = true;
        }
      }
    } catch (e) {
      print('Failed to start core: $e');
      _isRunning = false;
      rethrow;
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
      _trafficSubscription?.cancel();
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

    // Ensure each select group has a default node selected
    for (var group in _cachedGroups) {
      if (group.type == 'select' && group.nodes.isNotEmpty) {
        if (group.now == null || group.now!.isEmpty) {
          // Set first node as default
          group.now = group.nodes.first.name;
          print('Auto-selected default node for ${group.name}: ${group.now}');
        }
      }
    }

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
        nodes: _generateNodes('Auto', 5),
      ),
      ProxyGroup(
        name: 'Global',
        type: 'select',
        nodes: _generateNodes('Global', 10),
        now: 'Global Node 1',
      ),
      ProxyGroup(
        name: 'Streaming',
        type: 'select',
        nodes: _generateNodes('Stream', 8),
      ),
    ];
  }

  List<ProxyNode> _generateNodes(String prefix, int count) {
    return List.generate(
      count,
      (index) => ProxyNode(
        name: '$prefix Node ${index + 1}',
        type: 'Shadowsocks',
        delay: index * 50 + 20,
      ),
    );
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
      now: nodeName,
    );
    _cachedGroups[index] = newGroup;
  }

  // Call Clash API to change proxy
  Future<void> selectProxy(String groupName, String nodeName) async {
    try {
      final encodedGroup = Uri.encodeComponent(groupName);
      final url = Uri.parse('http://127.0.0.1:9090/proxies/$encodedGroup');

      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          ...UserAgentService().headers,
        },
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

  // Change proxy mode using native Go core SetMode (instant, no restart needed)
  Future<void> changeMode(String mode) async {
    final normalizedMode = mode.toLowerCase();
    if (normalizedMode != 'rule' &&
        normalizedMode != 'global' &&
        normalizedMode != 'direct') {
      print('Invalid mode: $mode. Must be rule, global, or direct.');
      return;
    }

    print('Changing mode to: $normalizedMode');

    // Save the mode for future starts
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('proxy_mode', normalizedMode);
    _currentMode = normalizedMode;

    // If VPN is running, use native SetMode for instant switch
    if (_isRunning) {
      try {
        await platform.invokeMethod('setMode', {'mode': normalizedMode});
        print('Mode changed to $normalizedMode via native core');
      } on PlatformException catch (e) {
        print('Native SetMode failed: ${e.message}');
        // Fallback: restart VPN
        print('Falling back to VPN restart...');
        await stop();
        await Future.delayed(const Duration(milliseconds: 500));
        await start();
        print('VPN restarted with mode: $normalizedMode');
      }
    } else {
      print('Mode saved. Will apply on next start.');
    }
  }

  // Get current mode from native core
  Future<String> getMode() async {
    if (!_isRunning) return _currentMode;
    try {
      final mode = await platform.invokeMethod('getMode');
      return mode?.toString().toLowerCase() ?? _currentMode;
    } catch (e) {
      print('GetMode failed: $e');
      return _currentMode;
    }
  }

  // Get Clash logs for diagnostics
  Future<String> getClashLogs() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final logFile = File('${supportDir.path}/clash/clash_core.log');

      if (await logFile.exists()) {
        final lines = await logFile.readAsLines();
        // Get last 100 lines
        final lastLines =
            lines.length > 100 ? lines.sublist(lines.length - 100) : lines;
        return lastLines.join('\n');
      }
      return 'Log file not found';
    } catch (e) {
      return 'Error reading logs: $e';
    }
  }

  // Test Clash API connection
  Future<bool> testClashApi() async {
    try {
      final url = Uri.parse('http://127.0.0.1:9090/version');
      final response = await http
          .get(
            url,
            headers: UserAgentService().headers,
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Clash API Connected: Version ${data['version']}');
        return true;
      }
      return false;
    } catch (e) {
      print('Clash API Test Failed: $e');
      return false;
    }
  }

  // Get connection stats
  Future<Map<String, dynamic>> getTrafficStats() async {
    try {
      final url = Uri.parse('http://127.0.0.1:9090/traffic');
      final response = await http
          .get(
            url,
            headers: UserAgentService().headers,
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {};
    } catch (e) {
      print('Get Traffic Stats Failed: $e');
      return {};
    }
  }

  // Set default nodes via API after core starts
  Future<void> _setDefaultNodesViaAPI() async {
    print('Setting default nodes via API...');
    for (var group in _cachedGroups) {
      if (group.type == 'select' &&
          group.now != null &&
          group.now!.isNotEmpty) {
        try {
          await selectProxy(group.name, group.now!);
          print('Set default node for ${group.name}: ${group.now}');
        } catch (e) {
          print('Failed to set default node for ${group.name}: $e');
        }
        // Add delay between API calls
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  // Auto-test latency for all proxy nodes after startup
  void _autoTestLatency() {
    // Collect all unique node names from all groups
    final Set<String> allNodeNames = {};
    for (var group in _cachedGroups) {
      for (var node in group.nodes) {
        // Skip non-proxy nodes (info nodes, groups, etc.)
        if (node.type != 'group/other' &&
            !node.name.contains('剩余流量') &&
            !node.name.contains('套餐到期') &&
            !node.name.contains('距离下次重置') &&
            !node.name.contains('https://')) {
          allNodeNames.add(node.name);
        }
      }
    }

    print('Registering ${allNodeNames.length} nodes for auto latency test...');

    // Register and test
    final latencyService = LatencyService();
    latencyService.registerAllNodes(allNodeNames.toList());
    latencyService.testAllNodes();
  }

  // --- Traffic Monitoring ---

  // --- Traffic Monitoring ---

  Stream<Map<String, dynamic>> getTrafficStream() {
    try {
      final uri = Uri.parse('ws://127.0.0.1:9090/traffic');
      final channel = WebSocketChannel.connect(uri);

      return channel.stream.map((event) {
        try {
          final data = json.decode(event);
          return {'up': data['up'] ?? 0, 'down': data['down'] ?? 0};
        } catch (e) {
          return {'up': 0, 'down': 0};
        }
      }).handleError((e) {
        // Return zeros on error
        return {'up': 0, 'down': 0};
      });
    } catch (e) {
      print('Failed to init traffic stream: $e');
      return Stream.value({'up': 0, 'down': 0});
    }
  }

  void _startTrafficMonitoringForNotification() {
    print('[Notification] Starting traffic monitoring for notification bar');
    _trafficSubscription?.cancel();
    _trafficSubscription = getTrafficStream().listen(
      (stats) {
        _updateNotification(stats);
      },
      onError: (error) {
        print('[Notification] Traffic stream error: $error');
      },
      onDone: () {
        print('[Notification] Traffic stream closed');
      },
    );
  }

  void _updateNotification(Map<String, dynamic> stats) {
    if (!_isRunning) return;

    try {
      final int down = stats['down'] ?? 0;
      final int up = stats['up'] ?? 0;
      final downStr = _formatBytes(down) + '/s';
      final upStr = _formatBytes(up) + '/s';
      final speedStr = '↓$downStr ↑$upStr';
      final nodeName = _getCurrentNodeName();

      print('[Notification] Updating: node=$nodeName, speed=$speedStr');

      platform.invokeMethod('updateNotification', {
        'node': nodeName,
        'speed': speedStr,
      });
    } catch (e) {
      print('[Notification] Error updating notification: $e');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _getCurrentNodeName() {
    if (_currentMode.toLowerCase() == 'global') {
      try {
        final globalGroup = _cachedGroups.firstWhere((g) => g.name == 'Global');
        return globalGroup.now ?? 'Global';
      } catch (e) {
        return 'Global';
      }
    }

    for (var group in _cachedGroups) {
      if (group.type == 'select' &&
          group.name != 'Global' &&
          group.name != 'Streaming') {
        return group.now ?? group.name;
      }
    }

    for (var group in _cachedGroups) {
      if (group.name == 'Global') return group.now ?? 'Global';
    }

    if (_cachedGroups.isNotEmpty) {
      return _cachedGroups.first.now ?? _cachedGroups.first.name;
    }

    return 'Connecting...';
  }
}
