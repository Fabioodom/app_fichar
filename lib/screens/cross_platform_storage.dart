import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:html' as html;

class CrossPlatformStorage {
  static Future<void> setString(String key, String value) async {
    if (kIsWeb) {
      html.window.localStorage[key] = value;
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }
  }

  static Future<void> setBool(String key, bool value) async {
    if (kIsWeb) {
      html.window.localStorage[key] = value.toString();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    }
  }

  static Future<String?> getString(String key) async {
    if (kIsWeb) {
      return html.window.localStorage[key];
    } else {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
  }

  static Future<bool> getBool(String key) async {
    if (kIsWeb) {
      final value = html.window.localStorage[key];
      return value == 'true';
    } else {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    }
  }

  static Future<void> remove(String key) async {
    if (kIsWeb) {
      html.window.localStorage.remove(key);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    }
  }
}
