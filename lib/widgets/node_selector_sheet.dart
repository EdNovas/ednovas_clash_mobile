import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gap/gap.dart';
import '../models/proxy_model.dart';
import '../services/latency_service.dart';

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
  bool _isGridView = true;
  final LatencyService _latencyService = LatencyService();
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Listen to latency updates
    _latencyService.addListener(_onLatencyUpdate);
    // Start cooldown timer if needed
    _startCooldownTimer();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _latencyService.removeListener(_onLatencyUpdate);
    super.dispose();
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
        // Stop timer when cooldown is done
        if (_latencyService.canTest && !_latencyService.isTesting) {
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _onLatencyUpdate() {
    if (mounted) {
      setState(() {});
      // Restart cooldown timer when testing completes
      if (!_latencyService.isTesting && _latencyService.cooldownRemaining > 0) {
        _startCooldownTimer();
      }
    }
  }

  /// Check if group type allows manual selection
  bool _isManualSelectAllowed(ProxyGroup group) {
    final type = group.type.toLowerCase();
    // Only 'select' type allows manual node selection
    // url-test, fallback, load-balance auto-select nodes
    return type == 'select';
  }

  /// Check if a node is a special/rule node that should not be sorted
  bool _isSpecialNode(String nodeName) {
    final lowerName = nodeName.toLowerCase();
    // Common rule node names that should keep their position
    return lowerName == 'direct' ||
        lowerName == 'reject' ||
        lowerName.contains('reject') ||
        lowerName.contains('direct') ||
        lowerName.contains('自动选择') ||
        lowerName.contains('故障转移') ||
        lowerName.contains('负载均衡') ||
        lowerName.contains('auto') ||
        lowerName.contains('fallback') ||
        lowerName.contains('load') ||
        nodeName.startsWith('套餐') ||
        nodeName.startsWith('剩余') ||
        nodeName.startsWith('距离');
  }

  /// Get nodes sorted by latency (special nodes stay in original position)
  List<ProxyNode> _getSortedNodes(List<ProxyNode> nodes) {
    // Separate special nodes and regular nodes
    final List<ProxyNode> specialNodes = [];
    final List<ProxyNode> regularNodes = [];
    final Map<int, ProxyNode> specialNodePositions = {};

    for (int i = 0; i < nodes.length; i++) {
      if (_isSpecialNode(nodes[i].name)) {
        specialNodes.add(nodes[i]);
        specialNodePositions[i] = nodes[i];
      } else {
        regularNodes.add(nodes[i]);
      }
    }

    // Sort regular nodes by latency
    regularNodes.sort((a, b) {
      final aDelay = _latencyService.getLatency(a.name) ?? a.delay;
      final bDelay = _latencyService.getLatency(b.name) ?? b.delay;

      // No latency data goes to the end
      if (aDelay == null && bDelay == null) return 0;
      if (aDelay == null) return 1;
      if (bDelay == null) return -1;

      // Timeout (-1) goes after valid delays but before no data
      if (aDelay < 0 && bDelay < 0) return 0;
      if (aDelay < 0) return 1;
      if (bDelay < 0) return -1;

      // Sort by latency (lowest first)
      return aDelay.compareTo(bDelay);
    });

    // Merge back: put special nodes in their original positions
    final List<ProxyNode> result = [];
    int regularIndex = 0;

    for (int i = 0; i < nodes.length; i++) {
      if (specialNodePositions.containsKey(i)) {
        result.add(specialNodePositions[i]!);
      } else if (regularIndex < regularNodes.length) {
        result.add(regularNodes[regularIndex]);
        regularIndex++;
      }
    }

    // Add any remaining regular nodes
    while (regularIndex < regularNodes.length) {
      result.add(regularNodes[regularIndex]);
      regularIndex++;
    }

    return result;
  }

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

    if (_selectedGroupIndex >= widget.groups.length) {
      _selectedGroupIndex = 0;
    }

    final selectedGroup = widget.groups[_selectedGroupIndex];
    final canManualSelect = _isManualSelectAllowed(selectedGroup);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Proxy Nodes',
                      style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  if (!canManualSelect)
                    Text(
                      '${selectedGroup.type.toUpperCase()} - 自动选择',
                      style: TextStyle(
                        color: Colors.orange[300],
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  // Latency test button with loading indicator and cooldown
                  _latencyService.isTesting
                      ? const SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        )
                      : _latencyService.canTest
                          ? IconButton(
                              icon:
                                  const Icon(Icons.speed, color: Colors.amber),
                              tooltip: 'Test Latency',
                              onPressed: _testGroupLatency,
                            )
                          : Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '${_latencyService.cooldownRemaining}s',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                  TextButton.icon(
                    onPressed: () => setState(() => _isGridView = !_isGridView),
                    icon: Icon(_isGridView ? Icons.list : Icons.grid_view,
                        color: Colors.blueAccent),
                    label: Text(_isGridView ? 'List' : 'Grid'),
                  ),
                ],
              ),
            ],
          ),
          const Gap(16),

          // Group Selector
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: widget.groups.asMap().entries.map((entry) {
                final isSelected = entry.key == _selectedGroupIndex;
                final group = entry.value;
                final isAutoType = !_isManualSelectAllowed(group);

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isAutoType)
                          Icon(Icons.auto_awesome,
                              size: 14,
                              color: isSelected ? Colors.white : Colors.amber),
                        if (isAutoType) const SizedBox(width: 4),
                        Text(group.name),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _selectedGroupIndex = entry.key),
                    selectedColor: Colors.blueAccent,
                    backgroundColor: Colors.grey[800],
                    labelStyle: TextStyle(
                        fontSize: 14, // Increased
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.grey[400]),
                  ),
                );
              }).toList(),
            ),
          ),
          const Gap(16),

          // Nodes List/Grid - Sorted by latency
          Expanded(
            child: Builder(
              builder: (context) {
                // Get sorted nodes (special nodes keep their position)
                final sortedNodes = _getSortedNodes(selectedGroup.nodes);

                return _isGridView
                    ? GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 2.2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: sortedNodes.length,
                        itemBuilder: (context, index) =>
                            _buildNodeCard(sortedNodes[index], canManualSelect),
                      )
                    : ListView.builder(
                        itemCount: sortedNodes.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildNodeCard(
                              sortedNodes[index], canManualSelect),
                        ),
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(ProxyNode node, bool canManualSelect) {
    final selectedGroup = widget.groups[_selectedGroupIndex];
    final isSelected = selectedGroup.now == node.name;
    final cachedDelay = _latencyService.getLatency(node.name);
    final displayDelay = cachedDelay ?? node.delay;

    return InkWell(
      onTap: canManualSelect
          ? () {
              if (isSelected) return;
              setState(() {
                selectedGroup.now = node.name;
              });
              widget.onNodeSelected(selectedGroup.name, node.name);
            }
          : null, // Disable tap for auto-select groups
      borderRadius: BorderRadius.circular(16),
      child: Opacity(
        opacity: canManualSelect ? 1.0 : 0.8,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blueAccent.withOpacity(0.2)
                : const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isSelected ? Colors.blueAccent : Colors.white10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.1),
                        blurRadius: 8,
                        spreadRadius: 1)
                  ]
                : [],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      style: GoogleFonts.outfit(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 16, // Increased
                          fontWeight: FontWeight.bold),
                    ),
                    // Only show latency row if we have data or are testing
                    if (displayDelay != null || _latencyService.isTesting)
                      Row(
                        children: [
                          // Latency Dot - only show if we have actual data
                          if (displayDelay != null)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: displayDelay >= 0
                                    ? (displayDelay < 150
                                        ? Colors.greenAccent
                                        : Colors.orangeAccent)
                                    : Colors.redAccent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (displayDelay >= 0
                                            ? (displayDelay < 150
                                                ? Colors.greenAccent
                                                : Colors.orangeAccent)
                                            : Colors.redAccent)
                                        .withOpacity(0.5),
                                    blurRadius: 4,
                                  )
                                ],
                              ),
                            ),
                          if (displayDelay != null) const Gap(8),
                          Text(
                            displayDelay != null
                                ? (displayDelay < 0
                                    ? 'Timeout'
                                    : '${displayDelay}ms')
                                : (_latencyService.isTesting
                                    ? 'Testing...'
                                    : ''),
                            style: GoogleFonts.outfit(
                                color: Colors.grey[400],
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded,
                    color: Colors.blueAccent, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  void _testGroupLatency() {
    final group = widget.groups[_selectedGroupIndex];
    final nodeNames = group.nodes.map((n) => n.name).toList();

    // Start background test - will continue even if sheet is closed
    _latencyService.testNodesLatency(nodeNames);

    // Force UI update to show loading indicator
    setState(() {});
  }
}
