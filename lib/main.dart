import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

import 'pages/home_page.dart';
import 'services/theme_service.dart';
import 'services/user_agent_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
    debugPrint('App will continue without Firebase analytics.');
  }

  // Initialize UserAgentService to get version for all HTTP requests
  await UserAgentService().init();

  // Set minimal system UI overlay style for splash
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final clarityConfig = ClarityConfig(
    projectId: "uq7e8kz8gp",
    logLevel: LogLevel.None,
  );

  runApp(
    ClarityWidget(
      clarityConfig: clarityConfig,
      app: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeService()),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          title: 'EdNovas Clash',
          debugShowCheckedModeBanner: false,

          // Localization
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'), // English
            Locale('zh'), // Chinese
          ],

          // Themes
          themeMode: themeService.themeMode,

          // Light Theme
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor:
                const Color(0xFFF5F5F7), // Apple-like light grey
            primarySwatch: Colors.blue,
            useMaterial3: true,
            textTheme:
                GoogleFonts.outfitTextTheme(Theme.of(context).textTheme.apply(
                      bodyColor: Colors.black87,
                      displayColor: Colors.black87,
                    )),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.black87),
            ),
          ),

          // Dark Theme
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF141414), // Existing dark
            primarySwatch: Colors.blue,
            useMaterial3: true,
            textTheme:
                GoogleFonts.outfitTextTheme(Theme.of(context).textTheme).apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.white),
            ),
          ),

          home: const HomePage(),
        );
      },
    );
  }
}
