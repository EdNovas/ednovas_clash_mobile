import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/proxy_model.dart';

class NodeSelectorSheet extends StatefulWidget {
  final List<ProxyGroup> groups;
  final Function(String group, String node) onNodeSelected;

  const NodeSelectorSheet({
    super.key,
    required this.groups,
    required this.onNodeSelected,
  });

  @override
  State<NodeSelectorSheet> createState() => _NodeSelectorSheetState();
}

class _NodeSelectorSheetState extends State<NodeSelectorSheet> {
  int _selectedGroupIndex = 0;
  bool _isGridView = true; // Toggle between Grid and List

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return Container(
          height: 300,
          color: const Color(0xFF1E1E1E),
          child: const Center(
              child: Text('No Proxy Groups Found',
                  style: TextStyle(color: Colors.white))));
    }

    // Safety check for index
    if (_selectedGroupIndex >= widget.groups.length) {
      _selectedGroupIndex = 0;
    }

    final selectedGroup = widget.groups[_selectedGroupIndex];

    return Container(
      height: MediaQuery.of(context).size.height * 0.75, // Not full screen
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Proxy Nodes',
                  style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.flash_on, color: Colors.amber),
                    tooltip: 'Test Latency',
                    onPressed: _testGroupLatency,
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _isGridView = !_isGridView),
                    icon: Icon(_isGridView ? Icons.list : Icons.grid_view,
                        color: Colors.blueAccent),
                    label: Text(_isGridView ? 'List View' : 'Grid View'),
                  ),
                ],
              ),
            ],
          ),
          const Gap(16),

          // Group Selector (Horizontal Scroll)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: widget.groups.asMap().entries.map((entry) {
                final isSelected = entry.key == _selectedGroupIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ChoiceChip(
                    label: Text(entry.value.name),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _selectedGroupIndex = entry.key),
                    selectedColor: Colors.blueAccent,
                    backgroundColor: Colors.grey[800],
                    labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[400]),
                  ),
                );
              }).toList(),
            ),
          ),
          const Gap(16),

          // Nodes List/Grid
          Expanded(
            child: _isGridView
                ? GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: selectedGroup.nodes.length,
                    itemBuilder: (context, index) =>
                        _buildNodeCard(selectedGroup.nodes[index]),
                  )
                : ListView.builder(
                    itemCount: selectedGroup.nodes.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildNodeCard(selectedGroup.nodes[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(ProxyNode node) {
    final selectedGroup = widget.groups[_selectedGroupIndex];
    final isSelected = selectedGroup.now == node.name;

    return InkWell(
      onTap: () {
        if (isSelected) return; // Do nothing if already selected

        // Optimistic Local Update
        setState(() {
          selectedGroup.now = node.name;
        });
        // Notify Parent
        widget.onNodeSelected(selectedGroup.name, node.name);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blueAccent.withOpacity(0.2)
              : const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? Colors.blueAccent : Colors.white10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isSelected ? Colors.blueAccent : Colors.white,
                        fontWeight: FontWeight.w500),
                  ),
                  Text(
                    node.type,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
            if (node.delay != null)
              Row(
                children: [
                  Text(
                    '${node.delay}ms',
                    style: TextStyle(
                      color: (node.delay ?? 0) < 0
                          ? Colors.red // Error
                          : (node.delay ?? 0) < 150
                              ? Colors.green
                              : Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.bolt, size: 14, color: Colors.blue),
                ],
              ),
          ],
        ),
      ),
    );
  }

  bool _isTesting = false;

  void _testGroupLatency() async {
    if (_isTesting) return;
    print('Starting Latency Test...');
    _isTesting = true;

    // Check if API is responsive first
    try {
      await http
          .get(Uri.parse('http://127.0.0.1:9090'))
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      print('API Root Check Failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clash API Unreachable: $e')),
        );
      }
      _isTesting = false;
      return;
    }

    // AGGRESSIVE LOG DUMP
    try {
      final supportDir = await getApplicationSupportDirectory();
      final clashDir = Directory('${supportDir.path}/clash');
      print('Searching for logs in: ${clashDir.path}');

      if (await clashDir.exists()) {
        final files = clashDir.listSync();
        print('Files found (${files.length}):');
        for (var f in files) {
          print(
              ' - ${f.path.split('/').last} (${(await f.stat()).size} bytes)');
        }

        final logFile = File('${clashDir.path}/clash_core.log');
        if (await logFile.exists()) {
          print('>>> CLASH CORE LOG BLOCK START <<<');
          final content = await logFile.readAsString();
          // Print in chunks to avoid truncation
          final lines = content.split('\n');
          // Print last 100 lines
          final startIdx = lines.length > 100 ? lines.length - 100 : 0;
          for (var i = startIdx; i < lines.length; i++) {
            print(lines[i]);
          }
          print('>>> CLASH CORE LOG BLOCK END <<<');
        } else {
          print('Log file NOT FOUND in clash dir.');
        }
      } else {
        print('Clash dir does not exist (Flutter view).');
      }
    } catch (logErr) {
      print('Log dump failed: $logErr');
    }

    final group = widget.groups[_selectedGroupIndex];
    // Test in batches of 5 to avoid resource exhaustion
    for (var i = 0; i < group.nodes.length; i += 5) {
      if (!mounted) break;
      final end = (i + 5 < group.nodes.length) ? i + 5 : group.nodes.length;
      final batch = group.nodes.sublist(i, end);

      await Future.wait(batch.map((node) async {
        if (node.name.isEmpty) return;

        try {
          // Use Uri constructor with pathSegments to handle special chars (spaces, slashes) in names automatically
          final url = Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: 9090,
            pathSegments: ['proxies', node.name, 'delay'],
            queryParameters: {
              'timeout': '5000',
              'url': 'http://www.gstatic.com/generate_204'
            },
          );

          print('Testing: ${node.name} -> $url');

          final response =
              await http.get(url).timeout(const Duration(seconds: 3));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final delay = data['delay'] as int?;
            print('Success [${node.name}]: $delay ms');
            if (mounted && delay != null) {
              setState(() => node.delay = delay);
            }
          } else {
            print(
                'Latency Error [${node.name}]: Status ${response.statusCode}, Body: ${response.body}');
            if (mounted) setState(() => node.delay = -1);
          }
        } catch (e) {
          print('Latency Exception [${node.name}]: $e');
          if (mounted) setState(() => node.delay = -1);
        }
      }));
      // Small delay between batches
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _isTesting = false;
  }
}
