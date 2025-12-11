import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/clash_service.dart';
import '../widgets/node_selector_sheet.dart';
import '../models/proxy_model.dart';
import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _api = ApiService();
  final ClashService _clash = ClashService();

  bool _isConnected = false;
  Map<String, dynamic>? _userInfo;
  List<ProxyGroup> _proxyGroups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  Future<void> _initValues() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('api_url');
    if (url != null) {
      _api.setBaseUrl(url);
    }
    _loadData();
  }

  bool _hasValidSubscription = false;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  // Polling Timer
  Timer? _pollingTimer;

  Future<void> _loadData() async {
    // 1. Check for Cached Config & Expiry (3 days strategy)
    final prefs = await SharedPreferences.getInstance();
    final lastTime = prefs.getInt('last_sub_time') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cachedConfig = prefs.getString('cached_config');
    final hasCache = cachedConfig != null && cachedConfig.isNotEmpty;

    // Auto-update if: No Cache OR Expired (3 days)
    final isExpired = (now - lastTime) > const Duration(days: 3).inMilliseconds;

    // Load User Info first (needed for Token/URL)
    await _fetchUserInfo();

    // Logic:
    // If we have cache and NOT expired -> Use Cache (Fast Start)
    // If expired or no cache -> Try fetch
    if (hasCache && !isExpired) {
      await _clash.updateConfig(cachedConfig);
      // Silently check for update in background? Or just stick to cache as per guide?
      // Guide says: "If cache exists and not expired -> Use cache directly."
      print(
          'Loaded config from cache (Valid for ${(3 - ((now - lastTime) / 86400000)).toStringAsFixed(1)} more days)');
    } else {
      // Try to fetch if we have info
      if (_userInfo != null && _userInfo!['subscribe_url'] != null) {
        print('Cache missing or expired. Fetching fresh config...');
        _updateSubscription(); // This fetches, caches, and updates
      }
    }

    // Refresh Groups from ClashService (Memory)
    final groups = await _clash.getProxyGroups();
    final isRunning = await _clash.checkStatus();

    if (mounted) {
      setState(() {
        _proxyGroups = groups;
        _isConnected = isRunning;
        _isLoading = false;
      });
    }

    // Start polling status if needed
    if (!_hasValidSubscription) _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_hasValidSubscription) {
        timer.cancel();
        return;
      }
      await _fetchUserInfo(isPolling: true);
    });
  }

  Future<void> _fetchUserInfo({bool isPolling = false}) async {
    if (!isPolling) setState(() => _isLoading = true);

    try {
      final userData = await _api.getSubscribe();
      final groups = await _clash.getProxyGroups();

      if (mounted) {
        setState(() {
          _userInfo = userData;
          _proxyGroups = groups;
          _isLoading = false;

          // Check if valid subscription (plan_id exists)
          if (userData['plan_id'] != null) {
            _hasValidSubscription = true;
          }
        });
      }
    } catch (e) {
      if (!isPolling && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  // New: Update Subscription/Rules
  Future<void> _updateSubscription() async {
    if (_userInfo == null || _userInfo!['subscribe_url'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No subscription URL found')));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updating Subscription...')));

    try {
      final configContent =
          await _api.fetchConfigContent(_userInfo!['subscribe_url']);

      // Parse, Save to Memory
      await _clash.updateConfig(configContent);

      // Save to Cache for Startup (Guide 1.1)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_config', configContent);
      await prefs.setInt(
          'last_sub_time', DateTime.now().millisecondsSinceEpoch);

      // Refresh UI with new groups (isPolling: true avoids full page loading flash)
      await _fetchUserInfo(isPolling: true);

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription Updated & Parsed!')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  void _showNodeSelector() {
    // Filter groups based on mode
    List<ProxyGroup> currentGroups = _proxyGroups;
    if (_clashMode == 'Global') {
      currentGroups =
          _proxyGroups.where((g) => g.name.toLowerCase() == 'global').toList();
    }

    // If empty (e.g. no GLOBAL found), fallback to all or show empty
    if (currentGroups.isEmpty && _clashMode == 'Global') {
      // Fallback just in case standard GLOBAL isn't named exactly 'Global'
      // Maybe user configuration uses different name. We'll show all but user should know.
    }

    showMaterialModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => NodeSelectorSheet(
        groups: currentGroups,
        onNodeSelected: (groupName, nodeName) async {
          // 1. Call Data Service to update state (Optimistic)
          await _clash.changeProxy(groupName, nodeName);

          // 2. User feedback (Top SnackBar)
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                'Switched to $nodeName',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(
                  bottom: MediaQuery.of(context).size.height - 150,
                  left: 20,
                  right: 20),
              duration: const Duration(seconds: 1),
              backgroundColor: Colors.black87,
            ));
          }
        },
      ),
    ).then((_) {
      // When sheet closes, refresh main page to sync any other visuals
      // _fetchUserInfo(); // Optional, enabled if needed
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF141414),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF141414), // Deep dark background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _updateSubscription,
            tooltip: 'Update Subscription',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 0),
          child: Column(
            children: [
              // 1. User Info Header
              _buildHeader(),

              const Spacer(),

              // 2. Big Connect Button
              _buildConnectButton(),

              const Spacer(),

              // 3. Mode Switcher
              _buildModeSwitcher(),

              const Gap(10),

              // 4. Compact Node Selector
              _buildNodeSelectorBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_userInfo == null) return const SizedBox();

    // V2Board fields: u (upload), d (download), transfer_enable (total), expired_at (timestamp)
    final usedBytes = (_userInfo!['u'] ?? 0) + (_userInfo!['d'] ?? 0);
    final totalBytes = _userInfo!['transfer_enable'] ?? 1;
    final usedGB = (usedBytes / 1073741824).toStringAsFixed(2);
    final totalGB = (totalBytes / 1073741824).toStringAsFixed(2);

    // Expire date
    final expireTimestamp = _userInfo!['expired_at'];
    final expireDate = expireTimestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(expireTimestamp * 1000)
            .toIso8601String()
            .substring(0, 10)
        : 'Never';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('My Plan',
                  style: GoogleFonts.outfit(color: Colors.grey, fontSize: 14)),
              Text('Expire: $expireDate',
                  style: GoogleFonts.outfit(color: Colors.grey, fontSize: 14)),
            ],
          ),
          const Gap(10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(usedGB,
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold)),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Text('/ $totalGB GB',
                    style: GoogleFonts.outfit(
                        color: Colors.grey[600], fontSize: 16)),
              ),
            ],
          ),
          const Gap(10),
          LinearProgressIndicator(
            value: (usedBytes / totalBytes).clamp(0.0, 1.0),
            backgroundColor: Colors.grey[800],
            color: Colors.blueAccent,
            borderRadius: BorderRadius.circular(10),
            minHeight: 8,
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.2);
  }

  bool _isStarting = false;

  void _toggleConnect() async {
    if (_isStarting) return; // Prevent double tap

    // Check for valid subscription before starting
    if (!_isConnected && !_hasValidSubscription) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please update subscription first!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isStarting = true);

    try {
      // Wait a bit to simulate "startup" or wait for actual method channel
      await Future.delayed(
          const Duration(milliseconds: 500)); // UI feedback buffer

      if (_isConnected) {
        await _clash.stop();
      } else {
        await _clash.start();
      }

      if (mounted) {
        setState(() {
          _isConnected = !_isConnected;
        });
      }
    } catch (e) {
      print('Toggle connect error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  Widget _buildConnectButton() {
    return GestureDetector(
      onTap: _toggleConnect,
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: _isConnected
                ? [Colors.blueAccent, Colors.purpleAccent]
                : [const Color(0xFF333333), const Color(0xFF222222)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _isConnected || _isStarting
                  ? Colors.blueAccent.withOpacity(0.4)
                  : Colors.black26,
              blurRadius: _isStarting ? 50 : 30, // Larger glow when starting
              spreadRadius: _isStarting ? 10 : 5,
            )
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isStarting)
              SizedBox(
                width: 200,
                height: 200,
                child: CircularProgressIndicator(
                    color: Colors.white.withOpacity(0.3), strokeWidth: 2),
              ),
            Icon(
              Icons.power_settings_new,
              size: 80,
              color: (_isConnected || _isStarting)
                  ? Colors.white
                  : Colors.grey[700],
            )
                .animate(target: _isStarting ? 1 : 0)
                .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.1, 1.1),
                    duration: 1000.ms,
                    curve: Curves.easeInOut)
                .callback(
                    callback:
                        (_) {}) // placeholder to keep it loop-friendly if we wanted
          ],
        ),
      ),
    )
        .animate(
            target: _isStarting ? 1 : 0,
            onPlay: (controller) => controller.repeat(reverse: true))
        .scaleXY(
            end: 1.05,
            duration: 800.ms,
            curve: Curves.easeInOut) // Breathing effect on entire button
        .then() // Chaining for other effects if needed
        .animate(target: _isConnected ? 1 : 0)
        .custom(
      builder: (context, value, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            child!,
            if (_isConnected && !_isStarting)
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.blueAccent
                          .withOpacity((1 - value).clamp(0.0, 1.0)),
                      width: 2),
                ),
              )
                  .animate(onPlay: (controller) => controller.repeat())
                  .scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1.3, 1.3),
                      duration: 2000.ms)
                  .fadeOut(duration: 2000.ms),
          ],
        );
      },
    );
  }

  String _clashMode = 'Rule'; // Rule, Global, Direct

  Widget _buildModeSwitcher() {
    final modes = ['Rule', 'Global', 'Direct'];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: modes.map((mode) {
          final isSelected = _clashMode == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _clashMode = mode);
                // TODO: Call API to set mode
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blueAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    mode,
                    style: GoogleFonts.outfit(
                      color: isSelected ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ).animate().fadeIn();
  }

  Widget _buildNodeSelectorBar() {
    // Find the main group to display
    // Logic: First Selector usually. Or name contains "EdNovas"
    ProxyGroup? mainGroup;
    if (_proxyGroups.isNotEmpty) {
      try {
        mainGroup = _proxyGroups.firstWhere(
            (g) => g.type == 'select' || g.name.contains('EdNovas'));
      } catch (_) {
        mainGroup = _proxyGroups.first;
      }
    }

    final groupName = mainGroup?.name ?? 'Delegate';
    final currentNode = mainGroup?.now ?? 'Select Node';

    return GestureDetector(
      onTap: _showNodeSelector,
      child: Container(
        margin: const EdgeInsets.only(bottom: 30), // Increased margin
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5))
            ]),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.2),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.dns,
                        color: Colors.blueAccent, size: 20)),
                const Gap(16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(currentNode,
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text(groupName,
                        style: GoogleFonts.outfit(
                            color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ],
            ),
            const Icon(Icons.expand_more, color: Colors.grey),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.2);
  }
}
