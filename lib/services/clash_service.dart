import 'dart:io';
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

      // Force External Controller Config
      // Remove existing conflicting keys to avoid ambiguity
      configContent = configContent.replaceAll(
          RegExp(r'^external-controller:.*$', multiLine: true), '');
      configContent =
          configContent.replaceAll(RegExp(r'^secret:.*$', multiLine: true), '');
      configContent = configContent.replaceAll(
          RegExp(r'^log-level:.*$', multiLine: true), '');
      configContent = configContent.replaceAll(
          RegExp(r'^log-file:.*$', multiLine: true), '');
      // Use Support Directory (files/clash) for logs to match HomeDir
      final supportDir = await getApplicationSupportDirectory();
      final logPath = '${supportDir.path}/clash/clash_core.log';
      print('Calculated Log Path: $logPath');

      // Prepend our forced config (0.0.0.0 for binding, debug logs)
      configContent = '''
external-controller: 0.0.0.0:9090
secret: ''
log-level: debug
log-file: '$logPath'
$configContent
''';

      // Save config in the same directory as resources (files/clash)
      final clashDir = Directory('${supportDir.path}/clash');
      if (!await clashDir.exists()) {
        await clashDir.create(recursive: true);
      }
      final configFile = File('${clashDir.path}/config.yaml');
      await configFile.writeAsString(configContent);

      print('Config Path: ${configFile.path}');

      await platform.invokeMethod('start', {'config_path': configFile.path});
      _isRunning = true;
      print(
          'Core Started via MethodChannel with Config File: ${configFile.path}');
    } catch (e) {
      print('Failed to start core: $e');
      _isRunning = true; // Still mock running state for UI
    }
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

  // Simulate changing proxy node for a group
  Future<void> changeProxy(String groupName, String nodeName) async {
    // 1. Find group index
    final index = _cachedGroups.indexWhere((g) => g.name == groupName);
    if (index == -1) return;

    // 2. Update the 'now' field.
    // Since ProxyGroup might be immutable, we create a copy with new selection
    final oldGroup = _cachedGroups[index];
    final newGroup = ProxyGroup(
        name: oldGroup.name,
        type: oldGroup.type,
        nodes: oldGroup.nodes,
        now: nodeName // Update selection
        );

    // 3. Update cache
    _cachedGroups[index] = newGroup;
  }
}
