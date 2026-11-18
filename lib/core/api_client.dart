import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class ApiException implements Exception {
  final int status; // 0 = network error
  final String message;
  final String? code;
  ApiException(this.status, this.message, {this.code});
  bool get isNetwork => status == 0;
  bool get isAuth => status == 401;
  @override
  String toString() => message;
}

/// Thin REST client for the Unicare Express API (same contract the web app uses).
/// - Adds `Authorization: Bearer <accessToken>`.
/// - On 401 it transparently calls POST /auth/refresh once, then retries.
class ApiClient {
  String? accessToken;
  String? refreshToken;

  /// Called after a successful refresh so the AuthState can persist new tokens.
  Future<void> Function(String access, String? refresh)? onTokens;

  /// Called when the session can't be recovered (refresh failed).
  void Function()? onSessionExpired;

  Future<void>? _refreshing;

  Uri _uri(String path, [Map<String, String>? q]) {
    final base = AppConfig.apiUrl;
    final u = Uri.parse('$base$path');
    return q == null || q.isEmpty ? u : u.replace(queryParameters: {...u.queryParameters, ...q});
  }

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, Object? body) => _send('POST', path, body: body);
  Future<dynamic> put(String path, Object? body) => _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path,
      {Object? body, Map<String, String>? query, bool retry = true}) async {
    http.Response res;
    try {
      final req = http.Request(method, _uri(path, query));
      req.headers.addAll(_headers());
      if (body != null) req.body = jsonEncode(body);
      final streamed = await req.send().timeout(const Duration(seconds: 20));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(0, 'The server took too long to respond.');
    } catch (_) {
      throw ApiException(0, 'Cannot reach the server. Check your connection.');
    }

    if (res.statusCode == 401 && retry && refreshToken != null && !path.startsWith('/auth/')) {
      final ok = await _tryRefresh();
      if (ok) return _send(method, path, body: body, query: query, retry: false);
      onSessionExpired?.call();
      throw ApiException(401, 'Session expired. Please sign in again.');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _toError(res);
    }
    if (res.statusCode == 204 || res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  ApiException _toError(http.Response res) {
    var msg = 'HTTP ${res.statusCode}';
    String? code;
    try {
      final d = jsonDecode(res.body);
      if (d is Map) {
        final e = d['error'];
        if (e is Map) {
          msg = (e['message'] ?? msg).toString();
          code = e['code']?.toString();
          final r = e['resolution'];
          if (r != null && r.toString().isNotEmpty && code == 'VALIDATION_FAILED') msg = '$msg ($r)';
        } else if (e is String) {
          msg = e;
        } else if (d['message'] != null) {
          msg = d['message'].toString();
        }
      }
    } catch (_) {}
    return ApiException(res.statusCode, msg, code: code);
  }

  Future<bool> _tryRefresh() async {
    // de-duplicate concurrent refreshes
    if (_refreshing != null) {
      await _refreshing;
      return accessToken != null;
    }
    final c = Completer<void>();
    _refreshing = c.future;
    try {
      final res = await http
          .post(_uri('/auth/refresh'), headers: {'Authorization': 'Bearer $refreshToken'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        accessToken = null;
        return false;
      }
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      accessToken = d['accessToken'] as String?;
      if (d['refreshToken'] != null) refreshToken = d['refreshToken'] as String;
      if (accessToken != null) await onTokens?.call(accessToken!, refreshToken);
      return accessToken != null;
    } catch (_) {
      return false;
    } finally {
      c.complete();
      _refreshing = null;
    }
  }
}
