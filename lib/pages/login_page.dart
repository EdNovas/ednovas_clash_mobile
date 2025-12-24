import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import '../l10n/app_localizations.dart';
import 'home_page.dart';
import 'support_page.dart';
import '../widgets/webview_sheet.dart';
import '../services/analytics_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = ApiService();

  bool _isLoading = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('login_page');
    _initApi();
  }

  Future<void> _initApi() async {
    setState(
        () => _statusMessage = 'findingServer'); // Use key for later lookup
    try {
      await _api.init();
      setState(() => _statusMessage = '');
    } catch (e) {
      setState(() => _statusMessage = 'connectionFailed');
    }
  }

  void _showCustomUrlDialog() {
    final controller = TextEditingController(text: _api.baseUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF252525) : Colors.white,
        title: Text('自定义 API 地址',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            labelText: 'API URL',
            hintText: 'https://api.example.com',
            labelStyle:
                TextStyle(color: isDark ? Colors.grey : Colors.grey[600]),
            hintStyle:
                TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400]),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                    color: isDark ? Colors.grey : Colors.grey[300]!)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                // Ensure URL starts with http
                final validUrl = url.startsWith('http') ? url : 'https://$url';
                await _api.setBaseUrl(validUrl);
                setState(() {});
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _doLogin() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        throw Exception(l10n.fillAllFields);
      }

      await _api.login(email, password);

      AnalyticsService.logLogin('email');

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } on CredentialException {
      // Wrong email or password
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.accountOrPasswordError),
              backgroundColor: const Color.fromARGB(255, 231, 98, 89)),
        );
      }
    } on NetworkException {
      // Network error after all retries
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.connectionFailed),
              backgroundColor: const Color.fromARGB(255, 231, 152, 89)),
        );
      }
    } catch (e) {
      // Other errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: const Color.fromARGB(255, 231, 98, 89)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _launchAuthPage(String path, {String title = 'Auth'}) async {
    final baseUrl = _api.baseUrl ?? 'https://new.ednovas.dev';
    final fullUrl = '$baseUrl$path';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: WebviewSheet(url: fullUrl, title: title),
      ),
    );
  }

  void _openCrispChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: const SupportPage(),
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardColor = isDark ? const Color(0xFF252525) : Colors.white;

    // Translate status message
    String displayStatus = '';
    if (_statusMessage == 'findingServer') {
      displayStatus = l10n.findingServer;
    } else if (_statusMessage == 'connectionFailed') {
      displayStatus = l10n.connectionFailed;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.support_agent,
              color: isDark ? Colors.white : Colors.black87),
          onPressed: _openCrispChat,
          tooltip: l10n.contactSupport,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings,
                color: isDark ? Colors.white : Colors.black87),
            onPressed: () => _openSettings(context),
            tooltip: l10n.settings,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'EdNovas Clash',
                style: GoogleFonts.outfit(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ).animate().fadeIn().moveY(begin: -20),
              if (displayStatus.isNotEmpty) ...[
                const Gap(10),
                Text(displayStatus,
                    style: TextStyle(
                        color: isDark ? Colors.grey : Colors.grey[600],
                        fontSize: 12)),
              ],
              const Gap(10),
              InkWell(
                onTap: _showCustomUrlDialog,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.dns_outlined,
                          size: 16,
                          color: isDark ? Colors.grey : Colors.grey[600]),
                      const Gap(8),
                      Flexible(
                        child: Text(
                          _api.baseUrl ?? 'Checking...',
                          style: TextStyle(
                              color: isDark ? Colors.grey : Colors.grey[600],
                              fontSize: 12,
                              decoration: TextDecoration.underline),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Gap(30),
              _buildTextField(
                  l10n.email, _emailController, Icons.email, isDark, cardColor),
              const Gap(16),
              _buildTextField(l10n.password, _passwordController, Icons.lock,
                  isDark, cardColor,
                  isObscure: true),
              const Gap(32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _doLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(l10n.login,
                          style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                ),
              ).animate().fadeIn().moveY(begin: 20),
              const Gap(20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () =>
                        _launchAuthPage('/#/register', title: l10n.register),
                    child: Text(l10n.register,
                        style: GoogleFonts.outfit(
                            color: isDark ? Colors.grey[500] : Colors.grey[700],
                            fontSize: 16)),
                  ),
                  TextButton(
                    onPressed: () => _launchAuthPage('/#/reset-password',
                        title: l10n.forgotPassword),
                    child: Text(l10n.forgotPassword,
                        style: GoogleFonts.outfit(
                            color: isDark ? Colors.grey[500] : Colors.grey[700],
                            fontSize: 16)),
                  ),
                ],
              ).animate().fadeIn().moveY(begin: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      IconData icon, bool isDark, Color cardColor,
      {bool isObscure = false}) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      style: TextStyle(
          color: isDark ? Colors.white : Colors.black87, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 16),
        prefixIcon: Icon(icon, color: Colors.blueAccent, size: 22),
        filled: true,
        fillColor: cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
