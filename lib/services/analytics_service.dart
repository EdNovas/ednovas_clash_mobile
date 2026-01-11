import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  static FirebaseAnalytics? _analytics;

  static FirebaseAnalytics? get _instance {
    if (_analytics == null) {
      try {
        // Check if Firebase is initialized
        Firebase.app();
        _analytics = FirebaseAnalytics.instance;
      } catch (e) {
        // Firebase not initialized, return null
        debugPrint('Analytics unavailable: Firebase not initialized');
        return null;
      }
    }
    return _analytics;
  }

  // Log a screen view (Automatically tracked by route observers usually, but manual is fine too)
  static Future<void> logScreenView(String screenName) async {
    try {
      await _instance?.logScreenView(screenName: screenName);
    } catch (e) {
      debugPrint('Analytics logScreenView failed: $e');
    }
  }

  // Log a custom event (e.g., user clicked a button)
  static Future<void> logEvent(
      String name, Map<String, Object>? parameters) async {
    try {
      await _instance?.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint('Analytics logEvent failed: $e');
    }
  }

  // Log login event
  static Future<void> logLogin(String method) async {
    try {
      await _instance?.logLogin(loginMethod: method);
    } catch (e) {
      debugPrint('Analytics logLogin failed: $e');
    }
  }

  // Log search event
  static Future<void> logSearch(String searchTerm) async {
    try {
      await _instance?.logSearch(searchTerm: searchTerm);
    } catch (e) {
      debugPrint('Analytics logSearch failed: $e');
    }
  }

  // Log content selection
  static Future<void> logSelectContent(
      String contentType, String itemId) async {
    try {
      await _instance?.logSelectContent(contentType: contentType, itemId: itemId);
    } catch (e) {
      debugPrint('Analytics logSelectContent failed: $e');
    }
  }
}
