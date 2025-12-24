class ProxyGroup {
  final String name;
  final String type; // connect, select, url-test, etc.
  final List<ProxyNode> nodes;
  String? now; // Current selected node name

  ProxyGroup({
    required this.name,
    required this.type,
    required this.nodes,
    this.now,
  });
}

class ProxyNode {
  final String name;
  final String type; // shadowsocks, vmess, etc.
  final String? server;
  final int? port;
  int? delay; // Latency in ms (Mutable for UI updates)

  ProxyNode({
    required this.name,
    required this.type,
    this.server,
    this.port,
    this.delay,
  });
}
