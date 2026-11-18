import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

typedef Rec = Map<String, dynamic>;

/// Generic access to the server's standard `/api/:table` contract
/// (GET list, POST, PUT /:id, DELETE /:id). One class serves every table.
///
/// Reads are cached on the device; if the network is down the last good copy
/// is returned and [offline] flips to true so the UI can show a banner.
/// Writes always go straight to the server (no local outbox in the mobile app).
class Repo extends ChangeNotifier {
  Repo(this.api);
  final ApiClient api;

  /// true when the most recent read was served from the local cache.
  final ValueNotifier<bool> offline = ValueNotifier(false);

  static const _pageSize = 200; // server MAX_LIMIT

  Future<List<Rec>> list(String table, {bool refreshOnly = false}) async {
    try {
      final out = <Rec>[];
      var offset = 0;
      while (true) {
        final d = await api.get('/$table', query: {
          'limit': '$_pageSize',
          'offset': '$offset',
        });
        final List data = d is Map ? (d['data'] as List? ?? const []) : (d as List);
        out.addAll(data.map((e) => Map<String, dynamic>.from(e as Map)));
        final total = d is Map ? ((d['pagination']?['total'] as num?)?.toInt() ?? out.length) : out.length;
        offset += _pageSize;
        if (data.isEmpty || offset >= total) break;
      }
      offline.value = false;
      _saveCache(table, out);
      return out;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        final cached = await _readCache(table);
        if (cached != null) {
          offline.value = true;
          return cached;
        }
      }
      rethrow;
    }
  }

  Future<Rec> create(String table, Rec body) async {
    final d = await api.post('/$table', body);
    notifyListeners();
    return Map<String, dynamic>.from(d as Map);
  }

  /// `updated_at` is stripped on purpose: the server rejects a PUT whose
  /// updated_at is older than the stored row (optimistic concurrency, HTTP 409).
  Future<Rec> update(String table, String id, Rec body) async {
    final b = Map<String, dynamic>.from(body)..remove('updated_at');
    final d = await api.put('/$table/${Uri.encodeComponent(id)}', b);
    notifyListeners();
    return Map<String, dynamic>.from(d as Map);
  }

  Future<void> remove(String table, String id) async {
    await api.delete('/$table/${Uri.encodeComponent(id)}');
    notifyListeners();
  }

  // ---- local cache -------------------------------------------------------
  Future<void> _saveCache(String table, List<Rec> rows) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('cache_$table', jsonEncode(rows));
    } catch (_) {}
  }

  Future<List<Rec>?> _readCache(String table) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('cache_$table');
      if (s == null) return null;
      return (jsonDecode(s) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCache() async {
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().where((k) => k.startsWith('cache_')).toList()) {
      await p.remove(k);
    }
  }

  /// Client-generated id, same "PREFIX-xxxxxx" style as the web app.
  static String newId(String prefix) {
    final t = DateTime.now().millisecondsSinceEpoch.toString();
    final r = Random().nextInt(90) + 10;
    return '$prefix-${t.substring(t.length - 6)}$r';
  }
}
