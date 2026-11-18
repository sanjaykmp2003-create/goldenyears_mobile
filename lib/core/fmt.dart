import 'package:intl/intl.dart';

String s(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final t = v.toString();
  return t.isEmpty ? fallback : t;
}

/// Postgres NUMERIC arrives as a String ("1200.00"); ints/doubles as num.
double n(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

num? numOrNull(String t) {
  final x = t.trim();
  if (x.isEmpty) return null;
  return num.tryParse(x);
}

bool b(dynamic v) => v == true || v == 'true' || v == 't' || v == 1;

/// yyyy-mm-dd from a DATE / timestamp value (same approach as web toDateInputString).
String dateOnly(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  final t = v.toString().trim();
  if (t.isEmpty) return fallback;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t)) return t.substring(0, 10);
  final p = DateTime.tryParse(t);
  return p == null ? fallback : DateFormat('yyyy-MM-dd').format(p);
}

String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

String prettyDate(dynamic v) {
  final d = dateOnly(v);
  if (d.isEmpty) return '—';
  final p = DateTime.tryParse(d);
  return p == null ? d : DateFormat('d MMM y').format(p);
}

String prettyTime(dynamic v) {
  if (v == null || v.toString().isEmpty) return '—';
  final p = DateTime.tryParse(v.toString());
  return p == null ? v.toString() : DateFormat('hh:mm a').format(p.toLocal());
}

String prettyDateTime(dynamic v) {
  if (v == null || v.toString().isEmpty) return '—';
  final p = DateTime.tryParse(v.toString());
  return p == null ? v.toString() : DateFormat('d MMM, hh:mm a').format(p.toLocal());
}

final _inr = NumberFormat.decimalPattern('en_IN');
String inr(dynamic v) => '₹${_inr.format(n(v).round())}';

String initials(String? name, {String fallback = 'NA'}) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return fallback;
  return parts.take(2).map((e) => e[0].toUpperCase()).join();
}

/// Inclusive list of yyyy-mm-dd between two dates.
Iterable<String> datesBetween(String from, String to) sync* {
  var d = DateTime.tryParse(from);
  final e = DateTime.tryParse(to);
  if (d == null || e == null) return;
  while (!d!.isAfter(e)) {
    yield DateFormat('yyyy-MM-dd').format(d);
    d = d.add(const Duration(days: 1));
  }
}
