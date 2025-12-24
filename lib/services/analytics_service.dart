import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // Log a screen view (Automatically tracked by route observers usually, but manual is fine too)
  static Future<void> logScreenView(String screenName) async {
    await _analytics.logScreenView(screenName: screenName);
  }

  // Log a custom event (e.g., user clicked a button)
  static Future<void> logEvent(
      String name, Map<String, Object>? parameters) async {
    await _analytics.logEvent(name: name, parameters: parameters);
  }

  // Log login event
  static Future<void> logLogin(String method) async {
    await _analytics.logLogin(loginMethod: method);
  }

  // Log search event
  static Future<void> logSearch(String searchTerm) async {
    await _analytics.logSearch(searchTerm: searchTerm);
  }

  // Log content selection
  static Future<void> logSelectContent(
      String contentType, String itemId) async {
    await _analytics.logSelectContent(contentType: contentType, itemId: itemId);
  }
}
