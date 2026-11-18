import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==============================================================================
//  ENVIRONMENT CONFIGURATION
//  Change this value directly in code:
//    - 'DEV' -> Uses Localhost backend (http://localhost:8080/api)
//    - 'SIT' -> Uses Cloud SIT backend (https://dev.3ii.co.in/goldenyears-api/api)
// ==============================================================================
// ignore: constant_identifier_names
const String ENV = 'SIT'; // <-- CHANGE TO 'DEV' OR 'SIT' HERE
// ==============================================================================

class AppConfig {
  /// 1. DEV Environment (Localhost for web/desktop, 10.0.2.2 for Android emulator)
  static String get devUrl => kIsWeb ? 'http://localhost:8080/api' : 'http://10.0.2.2:8080/api';

  /// 2. SIT Environment (Cloud)
  static const String sitUrl = 'https://dev.3ii.co.in/goldenyears-api/api';

  /// Active environment name: 'DEV' or 'SIT'
  static String get currentEnv => ENV.toUpperCase() == 'SIT' ? 'SIT' : 'DEV';

  /// Active API URL based on the ENV constant above
  static String apiUrl = (ENV.toUpperCase() == 'SIT') ? sitUrl : devUrl;

  static bool get isDev => currentEnv == 'DEV';
  static bool get isSit => currentEnv == 'SIT';

  static Future<void> load() async {
    // Automatically selects the URL corresponding to ENV
    apiUrl = (ENV.toUpperCase() == 'SIT') ? sitUrl : devUrl;
  }

  static Future<void> setApiUrl(String url) async {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    apiUrl = u;
    final p = await SharedPreferences.getInstance();
    await p.setString('api_url_override', u);
  }
}
