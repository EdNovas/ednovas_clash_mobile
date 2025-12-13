import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/clash_service.dart';
import '../widgets/node_selector_sheet.dart';
import '../models/proxy_model.dart';
import 'login_page.dart';
import 'support_page.dart';

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
    _stopTrafficMonitor();
    super.dispose();
  }

  // Polling Timer
  Timer? _pollingTimer;

  // Traffic Monitor
  StreamSubscription? _trafficSubscription;
  int _upSpeed = 0;
  int _downSpeed = 0;

  void _startTrafficMonitor() {
    _stopTrafficMonitor();
    _trafficSubscription = _clash.getTrafficStream().listen((data) {
      if (mounted) {
        setState(() {
          _upSpeed = data['up'] ?? 0;
          _downSpeed = data['down'] ?? 0;
        });
      }
    });
  }

  void _stopTrafficMonitor() {
    _trafficSubscription?.cancel();
    _trafficSubscription = null;
    if (mounted) {
      setState(() {
        _upSpeed = 0;
        _downSpeed = 0;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B/s';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB/s';
  }

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
      // Also fetch detailed info for plan name
      final detailedInfo = await _api.getUserInfo();
      if (detailedInfo.isNotEmpty) {
        userData.addAll(detailedInfo);
      }

      final groups = await _clash.getProxyGroups();

      if (mounted) {
        setState(() {
          _userInfo = userData;
          _proxyGroups = groups;
          _isLoading = false;

          // Validate subscription status
          final validationResult = _validateSubscription(userData);
          _hasValidSubscription = validationResult.isValid;

          if (!_hasValidSubscription && mounted && !isPolling) {
            Future.delayed(Duration.zero,
                () => _showSubscriptionIssueDialog(validationResult.reason));
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

  // Subscription validation result
  ({bool isValid, String reason}) _validateSubscription(
      Map<String, dynamic>? userData) {
    if (userData == null) {
      return (isValid: false, reason: 'no_data');
    }

    // Check if plan exists
    if (userData['plan_id'] == null) {
      return (isValid: false, reason: 'no_plan');
    }

    // Check if expired
    final expireTimestamp = userData['expired_at'];
    if (expireTimestamp != null) {
      final expireDate =
          DateTime.fromMillisecondsSinceEpoch(expireTimestamp * 1000);
      if (expireDate.isBefore(DateTime.now())) {
        return (isValid: false, reason: 'expired');
      }
    }

    // Check if traffic is used up
    final usedBytes = (userData['u'] ?? 0) + (userData['d'] ?? 0);
    final totalBytes = userData['transfer_enable'] ?? 0;
    if (totalBytes > 0 && usedBytes >= totalBytes) {
      return (isValid: false, reason: 'traffic_exhausted');
    }

    return (isValid: true, reason: 'valid');
  }

  void _showSubscriptionIssueDialog(String reason) {
    String title;
    String message;

    switch (reason) {
      case 'no_plan':
        title = '尚未订阅';
        message = '您还没有购买订阅服务。请先购买套餐以使用VPN服务。';
        break;
      case 'expired':
        title = '订阅已过期';
        message = '您的订阅已过期，请续费以继续使用服务。';
        break;
      case 'traffic_exhausted':
        title = '流量已用尽';
        message = '您的订阅流量已用完，请购买更多流量或升级套餐。';
        break;
      default:
        title = '无法使用';
        message = '无法验证您的订阅状态，请重新登录或联系客服。';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              reason == 'traffic_exhausted'
                  ? Icons.data_usage
                  : reason == 'expired'
                      ? Icons.timer_off
                      : Icons.shopping_cart,
              color: Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _launchUrl('/#/stage/buysubs');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('立即购买',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('稍后再说', style: TextStyle(color: Colors.grey))),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _logout();
              },
              child: const Text('退出登录', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
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

  Future<void> _launchUrl(String path) async {
    final url = Uri.parse('${_api.baseUrl ?? 'https://new.ednovas.dev'}$path');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not launch $url')));
      }
    }
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
        leading: IconButton(
          icon: const Icon(Icons.support_agent, color: Colors.white),
          onPressed: _openCrispChat,
          tooltip: '联系客服',
        ),
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

  // Crisp Customer Support - Open embedded popup
  void _openCrispChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF141414),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: const SupportPage(),
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
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _userInfo!['plan'] != null
                            ? (_userInfo!['plan']['name'] ??
                                _userInfo!['plan_name'] ??
                                'My Plan')
                            : (_userInfo!['plan_name'] ?? 'My Plan'),
                        style: GoogleFonts.outfit(
                            color: Colors.grey,
                            fontSize: 13), // Slightly smaller font
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const Gap(8),
                    GestureDetector(
                      onTap: () => _launchUrl('/#/stage/buysubs'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.blueAccent.withOpacity(0.5)),
                        ),
                        child: Text('Renew',
                            style: GoogleFonts.outfit(
                                color: Colors.blueAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(8),
              Text('Expire: $expireDate',
                  style: GoogleFonts.outfit(color: Colors.grey, fontSize: 12)),
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
    print(
        'Toggle Connect Clicked. isStarting: $_isStarting, isConnected: $_isConnected'); // LOG
    if (_isStarting) {
      print('Ignored due to isStarting=true');
      return;
    }

    // Check for valid subscription and groups before starting
    if (!_isConnected && (!_hasValidSubscription || _proxyGroups.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wait for subscription to load...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() => _isStarting = true);
    print('State set to Starting...');

    try {
      // Wait a bit to simulate "startup" or wait for actual method channel
      await Future.delayed(
          const Duration(milliseconds: 500)); // UI feedback buffer

      if (_isConnected) {
        print('Calling Stop...');
        await _clash.stop();
        _stopTrafficMonitor();
        print('Stop called.');
      } else {
        print('Calling Start...');
        await _clash.start();
        _startTrafficMonitor();
        print('Start called.');
      }

      if (mounted) {
        setState(() {
          _isConnected = !_isConnected;
        });
        print('State toggled to: $_isConnected');
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
        print('isStarting reset to false');
      }
    }
  }

  Widget _buildConnectButton() {
    final bool canConnect = _hasValidSubscription && _proxyGroups.isNotEmpty;
    // If not connected and cannot connect, show disabled grey.
    // If connected, show gradient.
    // If not connected but can connect, show dark grey gradient.
    final List<Color> colors = _isConnected
        ? [Colors.blueAccent, Colors.purpleAccent]
        : (canConnect
            ? [const Color(0xFF333333), const Color(0xFF222222)]
            : [Colors.grey[800]!, Colors.grey[900]!]);

    return GestureDetector(
      onTap: _toggleConnect,
      behavior: HitTestBehavior.translucent, // Ensure taps are caught
      child: Animate(
        target: _isStarting ? 1 : 0,
        effects: [
          ScaleEffect(
              begin: const Offset(1, 1),
              end: const Offset(1.05, 1.05),
              duration: 800.ms,
              curve: Curves.easeInOut)
        ],
        onPlay: (controller) => controller.repeat(reverse: true),
        child: Column(
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isConnected || _isStarting
                        ? Colors.blueAccent.withOpacity(0.4)
                        : (canConnect ? Colors.black26 : Colors.transparent),
                    blurRadius: _isStarting ? 50 : 30,
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
                        : (canConnect ? Colors.grey[700] : Colors.grey[800]),
                  ),
                ],
              ),
            ),
            if (_isConnected) _buildTrafficStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficStatus() {
    // Wrap with GestureDetector to absorb taps and prevent them from toggling VPN
    return GestureDetector(
      onTap: () {}, // Absorb tap, do nothing
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(top: 30),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_downward_rounded,
                size: 16, color: Colors.greenAccent),
            const SizedBox(width: 4),
            Text(
              _formatBytes(_downSpeed),
              style: GoogleFonts.outfit(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            Container(
                height: 16,
                width: 1,
                color: Colors.white24,
                margin: const EdgeInsets.symmetric(horizontal: 16)),
            const Icon(Icons.arrow_upward_rounded,
                size: 16, color: Colors.blueAccent),
            const SizedBox(width: 4),
            Text(
              _formatBytes(_upSpeed),
              style: GoogleFonts.outfit(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ).animate().fadeIn().slideY(begin: 0.5),
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
      child: Opacity(
        opacity: _isConnected ? 1.0 : 0.5,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: modes.map((mode) {
            final isSelected = _clashMode == mode;
            return Expanded(
              child: GestureDetector(
                onTap: _isConnected
                    ? () {
                        setState(() => _clashMode = mode);
                        _clash.changeMode(mode);
                      }
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Start VPN to change mode'),
                                duration: Duration(seconds: 1)));
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
      ),
    ).animate().fadeIn();
  }

  Widget _buildNodeSelectorBar() {
    // ... code for bar ...
    ProxyGroup? mainGroup;
    if (_proxyGroups.isNotEmpty) {
      if (_clashMode == 'Global') {
        try {
          mainGroup =
              _proxyGroups.firstWhere((g) => g.name.toLowerCase() == 'global');
        } catch (_) {
          mainGroup = _proxyGroups.first;
        }
      } else {
        try {
          mainGroup = _proxyGroups.firstWhere(
              (g) => g.type == 'select' || g.name.contains('EdNovas'));
        } catch (_) {
          mainGroup = _proxyGroups.first;
        }
      }
    }

    final groupName = mainGroup?.name ?? 'Delegate';
    final currentNode = mainGroup?.now ?? 'Select Node';

    return GestureDetector(
      onTap: _isConnected
          ? () {
              if (mainGroup != null) _showNodeSelector(mainGroup);
            }
          : () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Please start VPN to select nodes'),
                duration: Duration(seconds: 1),
              ));
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 30),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
            color: _isConnected
                ? const Color(0xFF252525)
                : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: _isConnected
                    ? Colors.white10
                    : Colors.white.withOpacity(0.05)),
            boxShadow: _isConnected
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5))
                  ]
                : []),
        child: Opacity(
          opacity: _isConnected ? 1.0 : 0.4,
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
      ),
    ).animate().fadeIn().slideY(begin: 0.2);
  }

  void _showNodeSelector(ProxyGroup group) {
    var groupsToShow = _proxyGroups;
    if (_clashMode == 'Global') {
      // Show only EdNovas (main) or groups explicitly named Global
      groupsToShow =
          _proxyGroups.where((g) => g.name.toLowerCase() == 'global').toList();
      // Safety fallback
      if (groupsToShow.isEmpty && _proxyGroups.isNotEmpty) {
        groupsToShow = [
          _proxyGroups.firstWhere((g) => g.type == 'select',
              orElse: () => _proxyGroups.first)
        ];
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NodeSelectorSheet(
        groups: groupsToShow,
        onNodeSelected: (groupName, nodeName) async {
          Navigator.pop(context);
          try {
            await _clash.selectProxy(groupName, nodeName);
            // Optimistic update
            setState(() {
              final g = _proxyGroups.firstWhere((g) => g.name == groupName);
              g.now = nodeName;
            });
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to select node: $e')));
          }
        },
      ),
    );
  }
}
