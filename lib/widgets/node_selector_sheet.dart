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

  @override
  void initState() {
    super.initState();
    // Listen to latency updates
    _latencyService.addListener(_onLatencyUpdate);
  }

  @override
  void dispose() {
    _latencyService.removeListener(_onLatencyUpdate);
    super.dispose();
  }

  void _onLatencyUpdate() {
    if (mounted) setState(() {});
  }

  /// Check if group type allows manual selection
  bool _isManualSelectAllowed(ProxyGroup group) {
    final type = group.type.toLowerCase();
    // Only 'select' type allows manual node selection
    // url-test, fallback, load-balance auto-select nodes
    return type == 'select';
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
                    itemBuilder: (context, index) => _buildNodeCard(
                        selectedGroup.nodes[index], canManualSelect),
                  )
                : ListView.builder(
                    itemCount: selectedGroup.nodes.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildNodeCard(
                          selectedGroup.nodes[index], canManualSelect),
                    ),
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
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: canManualSelect ? 1.0 : 0.8,
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
                    Row(
                      children: [
                        Text(
                          node.type,
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                        if (!canManualSelect && isSelected) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.check_circle,
                              size: 12, color: Colors.green[400]),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (displayDelay != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: displayDelay < 0
                        ? Colors.red.withOpacity(0.2)
                        : displayDelay < 150
                            ? Colors.green.withOpacity(0.2)
                            : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    displayDelay < 0 ? 'fail' : '${displayDelay}ms',
                    style: TextStyle(
                      color: displayDelay < 0
                          ? Colors.red
                          : displayDelay < 150
                              ? Colors.green
                              : Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
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
