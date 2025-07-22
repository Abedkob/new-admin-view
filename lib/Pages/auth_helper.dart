import 'package:shared_preferences/shared_preferences.dart';

class AuthHelper {
  static Future<int?> getRandAccess() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('rand_access');
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  static Future<void> saveAuthData(int randAccess, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('rand_access', randAccess);
    print("random acces is now : $randAccess");
    await prefs.setString('username', username);
  }

  static Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('rand_access');
    await prefs.remove('username');
  }
}