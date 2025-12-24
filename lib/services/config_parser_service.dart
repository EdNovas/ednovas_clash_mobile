import 'package:yaml/yaml.dart';
import '../models/proxy_model.dart';

class ConfigParserService {
  /// Parses the YAML content and returns a list of ProxyGroups in the correct order.
  /// Also returns the list of group names for sorting persistence if needed.
  static Future<ParseResult> parseConfig(String yamlContent) async {
    try {
      final doc = loadYaml(yamlContent);

      if (doc is! Map) throw Exception('Invalid YAML format');

      // 1. Parse Individual Proxies (Nodes)
      List<ProxyNode> allNodesList = [];
      Map<String, ProxyNode> nodeMap = {};

      final proxiesList = doc['proxies'];
      if (proxiesList is List) {
        for (var proxy in proxiesList) {
          if (proxy is Map) {
            final name = proxy['name']?.toString() ?? 'Unknown';
            final type = proxy['type']?.toString() ?? 'unknown';
            final server = proxy['server']?.toString(); // Server Host
            final port = int.tryParse(proxy['port']?.toString() ?? '');

            final node =
                ProxyNode(name: name, type: type, server: server, port: port);

            allNodesList.add(node);
            nodeMap[name] = node;
          }
        }
      }

      // 2. Parse Groups
      final proxyGroups = doc['proxy-groups'];
      if (proxyGroups is! List && allNodesList.isEmpty)
        return ParseResult([], []);

      List<ProxyGroup> groups = [];
      List<String> order = [];

      // Add Groups
      if (proxyGroups is List) {
        for (var group in proxyGroups) {
          if (group is Map) {
            final name = group['name']?.toString() ?? 'Unknown';
            final type = group['type']?.toString() ?? 'select';
            final proxies = (group['proxies'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            order.add(name);

            // Resolve nodes using the map
            final resolvedNodes = proxies.map((n) {
              if (nodeMap.containsKey(n)) {
                return nodeMap[n]!;
              } else {
                // It's likely another Group or special keyword (DIRECT/REJECT)
                return ProxyNode(name: n, type: 'group/other');
              }
            }).toList();

            // Find a real proxy node as default (skip info nodes for GLOBAL group)
            String defaultNode = proxies.isNotEmpty ? proxies.first : '';
            if (name == 'GLOBAL' || name.toUpperCase() == 'GLOBAL') {
              // For GLOBAL, skip info nodes and find a real proxy
              for (var nodeName in proxies) {
                // Skip info-like nodes
                if (!nodeName.contains('剩余流量') &&
                    !nodeName.contains('套餐到期') &&
                    !nodeName.contains('距离下次重置') &&
                    !nodeName.contains('https://') &&
                    !nodeName.contains('Traffic') &&
                    !nodeName.contains('Expire') &&
                    nodeMap.containsKey(nodeName)) {
                  defaultNode = nodeName;
                  break;
                }
              }
            }

            groups.add(ProxyGroup(
              name: name,
              type: type,
              nodes: resolvedNodes,
              now: defaultNode,
            ));
          }
        }
      }

      // 3. Create Synthetic "Global" Group
      if (allNodesList.isNotEmpty) {
        final globalGroup = ProxyGroup(
            name: 'GLOBAL',
            type: 'select',
            nodes: allNodesList,
            now: allNodesList.first.name);
        groups.add(globalGroup);
      }

      return ParseResult(groups, order);
    } catch (e) {
      print('Parse Error: $e');
      return ParseResult([], []);
    }
  }
}

class ParseResult {
  final List<ProxyGroup> groups;
  final List<String> groupOrder;

  ParseResult(this.groups, this.groupOrder);
}
