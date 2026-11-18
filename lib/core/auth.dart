import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'config.dart';

/// All screen keys, identical to the web app's DEFAULT_ALL_SCREENS.
const kAllScreens = [
  'dashboard', 'enquiry', 'clients', 'assessment', 'duty', 'attendance', 'leave',
  'nurseapp', 'billing', 'payroll', 'masters', 'roles', 'users',
];

class UserContext {
  final String userId;
  final String userType; // management | assessor | nurse | family
  final String? linkedId; // nurse_id / client_id ...
  final List<String> screens;
  UserContext({required this.userId, required this.userType, this.linkedId, required this.screens});

  bool can(String screen) => screens.isEmpty || screens.contains(screen);
  bool get isManagement => userType == 'management';
  bool get isNurse => userType == 'nurse';

  Map<String, dynamic> toJson() =>
      {'userId': userId, 'userType': userType, 'linkedId': linkedId, 'screens': screens};

  factory UserContext.fromJson(Map<String, dynamic> j) => UserContext(
        userId: (j['userId'] ?? '').toString(),
        userType: (j['userType'] ?? 'management').toString(),
        linkedId: j['linkedId']?.toString(),
        screens: ((j['screens'] ?? const []) as List).map((e) => e.toString()).toList(),
      );
}

class AuthState extends ChangeNotifier {
  AuthState(this.api) {
    api.onTokens = (a, r) async {
      await _store.write(key: _kAccess, value: a);
      if (r != null) await _store.write(key: _kRefresh, value: r);
    };
    api.onSessionExpired = () => logout();
  }

  final ApiClient api;
  final _store = const FlutterSecureStorage();
  static const _kAccess = 'unicare_access_token';
  static const _kRefresh = 'unicare_refresh_token';
  static const _kUser = 'unicare_user_ctx';

  UserContext? user;
  bool ready = false;

  /// Restore a previous session on app start.
  Future<void> restore() async {
    try {
      final a = await _store.read(key: _kAccess);
      final r = await _store.read(key: _kRefresh);
      final u = await _store.read(key: _kUser);
      if (a != null && u != null) {
        api.accessToken = a;
        api.refreshToken = r;
        user = UserContext.fromJson(jsonDecode(u) as Map<String, dynamic>);
      }
    } catch (_) {
      user = null;
    }
    ready = true;
    notifyListeners();
  }

  /// POST /api/auth/login - same endpoint and payload as the web app.
  Future<void> login(String username, String password) async {
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${AppConfig.apiUrl}/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ApiException(0, 'Cannot reach the server at ${AppConfig.apiUrl}.');
    }
    if (res.statusCode != 200) {
      var msg = 'Login failed (HTTP ${res.statusCode})';
      try {
        final d = jsonDecode(res.body);
        final m = d['error']?['message'];
        if (m != null) msg = m.toString();
      } catch (_) {}
      throw ApiException(res.statusCode, msg);
    }
    final d = jsonDecode(res.body) as Map<String, dynamic>;
    if (d['accessToken'] == null || d['user'] == null) {
      throw ApiException(500, 'Invalid response from server');
    }
    api.accessToken = d['accessToken'] as String;
    api.refreshToken = d['refreshToken'] as String?;
    user = UserContext.fromJson(Map<String, dynamic>.from(d['user'] as Map));
    await _store.write(key: _kAccess, value: api.accessToken);
    if (api.refreshToken != null) await _store.write(key: _kRefresh, value: api.refreshToken);
    await _store.write(key: _kUser, value: jsonEncode(user!.toJson()));
    notifyListeners();
  }

  Future<void> logout() async {
    api.accessToken = null;
    api.refreshToken = null;
    user = null;
    try {
      await _store.deleteAll();
    } catch (_) {}
    notifyListeners();
  }
}
