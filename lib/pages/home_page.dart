import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/clash_service.dart';
import '../widgets/node_selector_sheet.dart';
import '../models/proxy_model.dart';
import 'login_page.dart';
import 'support_page.dart';
import '../widgets/webview_sheet.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import '../services/analytics_service.dart';
import '../l10n/app_localizations.dart';

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
    AnalyticsService.logScreenView('home_page');
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
    _statusCheckTimer?.cancel();
    _stopTrafficMonitor();
    super.dispose();
  }

  // Polling Timer
  Timer? _pollingTimer;

  // VPN Status Check Timer (to sync UI when stopped from notification)
  Timer? _statusCheckTimer;

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

    // Also start status check timer to detect external stops (from notification)
    _startStatusCheckTimer();
  }

  void _stopTrafficMonitor() {
    _trafficSubscription?.cancel();
    _trafficSubscription = null;
    _statusCheckTimer?.cancel();
    _statusCheckTimer = null;
    if (mounted) {
      setState(() {
        _upSpeed = 0;
        _downSpeed = 0;
      });
    }
  }

  void _startStatusCheckTimer() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final isRunning = await _clash.checkStatus();
      if (mounted && _isConnected != isRunning) {
        setState(() {
          _isConnected = isRunning;
        });

        if (!isRunning) {
          // VPN was stopped externally (from notification)
          _stopTrafficMonitor();
        }
      }
    });
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
      // Use retry version for better reliability with automatic URL switching
      final userData = await _api.getSubscribeWithRetry();
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

  Future<void> _launchUrl(String path, {String title = 'EdNovas'}) async {
    final fullUrl = '${_api.baseUrl ?? 'https://new.ednovas.dev'}$path';
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
        child: WebviewSheet(url: fullUrl, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : Colors.black87;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.support_agent, color: iconColor),
          onPressed: _openCrispChat,
          tooltip: '联系客服',
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: iconColor),
            onPressed: _updateSubscription,
            tooltip: 'Update Subscription',
          ),
          IconButton(
            icon: Icon(Icons.settings, color: iconColor),
            onPressed: () => _openSettings(context),
            tooltip: 'Settings',
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardColor = isDark ? const Color(0xFF252525) : Colors.white;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

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
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow:
            isDark ? [] : [BoxShadow(color: Colors.black12, blurRadius: 10)],
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
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const Gap(8),
                    GestureDetector(
                      onTap: () =>
                          _launchUrl('/#/stage/buysubs', title: '购买套餐'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.blueAccent.withOpacity(0.5)),
                        ),
                        child: Text('购买',
                            style: GoogleFonts.outfit(
                                color: Colors.blueAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(8),
              Text('到期时间: $expireDate',
                  style:
                      GoogleFonts.outfit(color: subtitleColor, fontSize: 13)),
            ],
          ),
          const Gap(10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(usedGB,
                  style: GoogleFonts.outfit(
                      color: textColor,
                      fontSize: 32,
                      fontWeight: FontWeight.bold)),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Text('/ $totalGB GB',
                    style:
                        GoogleFonts.outfit(color: subtitleColor, fontSize: 16)),
              ),
            ],
          ),
          const Gap(10),
          LinearProgressIndicator(
            value: (usedBytes / totalBytes).clamp(0.0, 1.0),
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
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

        AnalyticsService.logEvent(
          _isConnected ? 'vpn_start' : 'vpn_stop',
          {'mode': _proxyGroups.isNotEmpty ? 'proxy' : 'direct'},
        );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool canConnect = _hasValidSubscription && _proxyGroups.isNotEmpty;

    // Theme-aware colors for the button
    final List<Color> colors = _isConnected
        ? [Colors.blueAccent, Colors.purpleAccent]
        : (canConnect
            ? (isDark
                ? [const Color(0xFF333333), const Color(0xFF222222)]
                : [Colors.grey[300]!, Colors.grey[400]!])
            : (isDark
                ? [Colors.grey[800]!, Colors.grey[900]!]
                : [Colors.grey[400]!, Colors.grey[500]!]));

    final iconColor = _isConnected || _isStarting
        ? Colors.white
        : (canConnect
            ? (isDark ? Colors.grey[500] : Colors.grey[600])
            : (isDark ? Colors.grey[700] : Colors.grey[500]));

    return GestureDetector(
      onTap: _toggleConnect,
      behavior: HitTestBehavior.translucent,
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
                        : (canConnect
                            ? (isDark
                                ? Colors.black26
                                : Colors.grey.withOpacity(0.3))
                            : Colors.transparent),
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
                      width: 240,
                      height: 240,
                      child: CircularProgressIndicator(
                          color: Colors.white.withOpacity(0.3), strokeWidth: 2),
                    ),
                  Icon(
                    Icons.power_settings_new,
                    size: 100,
                    color: iconColor,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final unitColor = isDark ? Colors.grey[400] : Colors.grey[600];

    Widget buildSpeedItem(IconData icon, Color color, int bytes) {
      String number = '0';
      String unit = 'KB/s';
      if (bytes > 0) {
        const suffixes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
        var i = (log(bytes) / log(1024)).floor();
        if (i >= suffixes.length) i = suffixes.length - 1;
        number = (bytes / pow(1024, i)).toStringAsFixed(1);
        unit = suffixes[i];
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            number,
            style: GoogleFonts.outfit(
                color: textColor, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              unit,
              style: GoogleFonts.outfit(
                  color: unitColor, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(top: 40),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withOpacity(0.4)
              : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color:
                  isDark ? Colors.white.withOpacity(0.05) : Colors.grey[300]!),
          boxShadow:
              isDark ? [] : [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildSpeedItem(
                Icons.arrow_downward_rounded, Colors.greenAccent, _downSpeed),
            Container(
                height: 24,
                width: 1,
                color: isDark ? Colors.white12 : Colors.grey[300],
                margin: const EdgeInsets.symmetric(horizontal: 24)),
            buildSpeedItem(
                Icons.arrow_upward_rounded, Colors.blueAccent, _upSpeed),
          ],
        ),
      ).animate().fadeIn().slideY(begin: 0.5),
    );
  }

  String _clashMode = 'Rule'; // Rule, Global, Direct

  Widget _buildModeSwitcher() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modes = ['Rule', 'Global', 'Direct'];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[300]!),
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
                  child: Text(
                    mode,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.grey[600] : Colors.grey[700]),
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
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
      child: Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final textColor = isDark ? Colors.white : Colors.black87;
          final cardColor = isDark ? const Color(0xFF252525) : Colors.white;
          final inactiveCardColor =
              isDark ? const Color(0xFF1A1A1A) : Colors.grey[100];

          return Container(
            margin: const EdgeInsets.only(bottom: 30),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              color: _isConnected ? cardColor : inactiveCardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isConnected
                    ? (isDark ? Colors.white10 : Colors.grey[300]!)
                    : (isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.grey[200]!),
              ),
              boxShadow: _isConnected
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      )
                    ]
                  : [],
            ),
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
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.dns,
                            color: Colors.blueAccent, size: 20),
                      ),
                      const Gap(16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentNode,
                            style: GoogleFonts.outfit(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            groupName,
                            style: GoogleFonts.outfit(
                              color: isDark ? Colors.grey : Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Icon(Icons.expand_more,
                      color: isDark ? Colors.grey : Colors.grey[600]),
                ],
              ),
            ),
          );
        },
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

  void _openSettings(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          // Use theme background color
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settings,
                style: GoogleFonts.outfit(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const Gap(20),
            // Theme Switch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.theme,
                    style: GoogleFonts.outfit(
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        fontSize: 16)),
                Consumer<ThemeService>(
                  builder: (context, themeService, _) {
                    return SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                            value: ThemeMode.light,
                            icon: const Icon(Icons.light_mode),
                            label: Text(l10n.themeLight)),
                        ButtonSegment(
                            value: ThemeMode.dark,
                            icon: const Icon(Icons.dark_mode),
                            label: Text(l10n.themeDark)),
                      ],
                      selected: {
                        themeService.themeMode == ThemeMode.system
                            ? ThemeMode.dark
                            : themeService.themeMode
                      },
                      onSelectionChanged: (Set<ThemeMode> newSelection) {
                        themeService.setThemeMode(newSelection.first);
                      },
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.resolveWith<Color?>(
                          (Set<MaterialState> states) {
                            if (states.contains(MaterialState.selected)) {
                              return Colors.blueAccent;
                            }
                            return null;
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const Gap(20),
            // Check Update
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.system_update,
                  color: Theme.of(context).iconTheme.color),
              title: Text(l10n.checkForUpdates,
                  style: GoogleFonts.outfit(
                      color: Theme.of(context).textTheme.bodyMedium?.color)),
              onTap: () async {
                Navigator.pop(context);
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l10n.checkingUpdate)));
                final update = await UpdateService.checkUpdate();
                if (update != null) {
                  showDialog(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                            title: Text(l10n.updateAvailable),
                            content: Text(
                                '${l10n.updateAvailable} ${update['version']}'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: Text(l10n.cancel)),
                              TextButton(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                    if (update['url'] != null)
                                      UpdateService.launchUpdateUrl(
                                          update['url']);
                                  },
                                  child: Text(l10n.download)),
                            ],
                          ));
                } else {
                  // Show dialog when no update is available
                  showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(l10n.upToDate),
                      content: Text(l10n.currentVersion),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(l10n.logout,
                  style: GoogleFonts.outfit(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            )
          ],
        ),
      ),
    );
  }
}
