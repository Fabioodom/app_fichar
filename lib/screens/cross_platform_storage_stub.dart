class CrossPlatformStorage {
  static Future<void> setString(String key, String value) async {}
  static Future<void> setBool(String key, bool value) async {}
  static Future<String?> getString(String key) async => null;
  static Future<bool> getBool(String key) async => false;
  static Future<void> remove(String key) async {}
}
