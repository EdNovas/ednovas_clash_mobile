import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'home_page.dart';
import 'support_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // No URL Controller needed anymore
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = ApiService();

  bool _isLoading = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _initApi();
  }

  Future<void> _initApi() async {
    setState(() => _statusMessage = 'Finding fastest server...');
    try {
      await _api.init(); // This triggers findFastestUrl if needed
      setState(() => _statusMessage = '');
    } catch (e) {
      setState(() => _statusMessage = 'Failed to connect to server');
    }
  }

  Future<void> _doLogin() async {
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Please fill all fields');
      }

      await _api.login(email, password);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Account or password error'),
            backgroundColor: Color.fromARGB(255, 231, 98, 89)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _launchAuthPage(String path) async {
    final baseUrl = _api.baseUrl ?? 'https://new.ednovas.dev';
    final url = Uri.parse('$baseUrl$path');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not launch $url')));
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.support_agent, color: Colors.white),
          onPressed: _openCrispChat,
          tooltip: '联系客服',
        ),
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
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ).animate().fadeIn().moveY(begin: -20),

              if (_statusMessage.isNotEmpty) ...[
                const Gap(10),
                Text(_statusMessage,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],

              const Gap(40),

              // No URL Field

              _buildTextField('Email', _emailController, Icons.email),
              const Gap(16),
              _buildTextField('Password', _passwordController, Icons.lock,
                  isObscure: true),

              const Gap(32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _doLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text('Login',
                          style: GoogleFonts.outfit(
                              fontSize: 18, color: Colors.white)),
                ),
              ).animate().fadeIn().moveY(begin: 20),

              const Gap(20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => _launchAuthPage('/#/register'),
                    child: Text('Register',
                        style: GoogleFonts.outfit(color: Colors.grey[500])),
                  ),
                  TextButton(
                    onPressed: () => _launchAuthPage('/#/reset-password'),
                    child: Text('Forgot Password?',
                        style: GoogleFonts.outfit(color: Colors.grey[500])),
                  ),
                ],
              ).animate().fadeIn().moveY(begin: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      String label, TextEditingController controller, IconData icon,
      {bool isObscure = false}) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(icon, color: Colors.blueAccent),
        filled: true,
        fillColor: const Color(0xFF252525),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
