import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';

const kScrollPhysics = AlwaysScrollableScrollPhysics();
const kPagePad = EdgeInsets.fromLTRB(16, 16, 16, 96);

// ---------------------------------------------------------------- cards ----
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.margin});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(C.radius),
        border: Border.all(color: C.line),
        boxShadow: C.shadowSm,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(C.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(C.radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return margin == null ? box : Padding(padding: margin!, child: box);
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.eyebrow, required this.title, this.subtitle, this.trailing});
  final String eyebrow, title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(eyebrow.toUpperCase(),
                style: const TextStyle(fontSize: 11, letterSpacing: 1.3, color: C.greenDk, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(title, style: serif(26)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: const TextStyle(fontSize: 13, color: C.ink3)),
            ],
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
        child: Row(children: [
          Text(text.toUpperCase(),
              style: const TextStyle(fontSize: 11.5, letterSpacing: 1.0, color: C.ink3, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          const Expanded(child: Divider()),
        ]),
      );
}

// ----------------------------------------------------------------- tags ----
enum Tone { green, navy, blue, red, amber, purple, grey }

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = Tone.grey, this.dot = false});
  final String text;
  final Tone tone;
  final bool dot;

  static (Color, Color) colors(Tone t) {
    switch (t) {
      case Tone.green:
        return (C.greenLt, C.greenDk);
      case Tone.navy:
        return (C.navyLt, C.navy);
      case Tone.blue:
        return (C.blueLt, C.blue);
      case Tone.red:
        return (C.redLt, C.redDk);
      case Tone.amber:
        return (C.amberLt, C.amber);
      case Tone.purple:
        return (C.purpleLt, C.purple);
      case Tone.grey:
        return (const Color(0xFFEEF1EE), C.ink2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg))),
      ]),
    );
  }
}

/// Maps the status strings used across the app to the same tag colours as the web UI.
Tone toneFor(String? status) {
  final t = (status ?? '').toLowerCase();
  if (['active', 'present', 'approved', 'paid', 'converted', 'success', 'completed', 'processed', 'signed'].contains(t)) return Tone.green;
  if (['pending', 'due', 'scheduled', 'new', 'draft', 'awaiting consent', 'visit scheduled', 'on leave'].contains(t)) return Tone.amber;
  if (['absent', 'rejected', 'overdue', 'inactive', 'failed', 'cancelled', 'closed'].contains(t)) return Tone.red;
  if (['contacted', 'half day', 'in progress'].contains(t)) return Tone.blue;
  return Tone.grey;
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 38, this.tone = Tone.navy});
  final String? name;
  final double size;
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = Tag.colors(tone);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(initials(name), style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class Kpi extends StatelessWidget {
  const Kpi({super.key, required this.label, required this.value, required this.icon, this.tone = Tone.green, this.valueColor});
  final String label, value;
  final IconData icon;
  final Tone tone;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = Tag.colors(tone);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 19, color: fg),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(fontSize: 12.5, color: C.ink3, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: serif(27, color: valueColor ?? C.ink)),
        ),
      ]),
    );
  }
}

/// Two-column grid of fixed-height cards without needing a GridView inside a ListView.
class TwoUp extends StatelessWidget {
  const TwoUp(this.children, {super.key, this.gap = 12});
  final List<Widget> children;
  final double gap;
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: children[i]),
        SizedBox(width: gap),
        Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
      ]));
      if (i + 2 < children.length) rows.add(SizedBox(height: gap));
    }
    return Column(children: rows);
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueWidget});
  final String label;
  final String value;
  final Widget? valueWidget;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: Text(label, style: const TextStyle(color: C.ink3, fontSize: 13))),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child: valueWidget ??
                  Text(value.isEmpty ? '—' : value,
                      textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
        ]),
      );
}

// ---------------------------------------------------- filters / search ----
/// Segmented filter, same look as the web `.seg` control (horizontally scrollable on phones).
class Seg extends StatelessWidget {
  const Seg({super.key, required this.options, required this.value, required this.onChanged});
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final o = options[i];
          final on = o == value;
          return GestureDetector(
            onTap: () => onChanged(o),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? C.navy : C.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: on ? C.navy : C.line),
              ),
              child: Text(o, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: on ? Colors.white : C.ink2)),
            ),
          );
        },
      ),
    );
  }
}

class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: C.ink3, fontSize: 13.5),
          prefixIcon: const Icon(Icons.search, size: 20, color: C.ink3),
          fillColor: C.surface2,
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(children: [
          Icon(icon, size: 40, color: C.line),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.ink3)),
        ]),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: C.redLt, shape: BoxShape.circle),
              child: const Icon(Icons.cloud_off, color: C.red),
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: C.ink2)),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ]),
        ),
      );
}

// ------------------------------------------------------------ messages ----
void toast(BuildContext c, String msg) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

String errText(Object e) => e is ApiException ? e.message : e.toString();

Future<bool> confirmDialog(BuildContext c, {String title = 'Delete record?', required String text, String action = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(color: C.redLt, shape: BoxShape.circle),
        child: const Icon(Icons.delete_outline, color: C.red),
      ),
      title: Text(title, style: serif(18)),
      content: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.ink3, fontSize: 13.5)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: C.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r == true;
}

// -------------------------------------------------------- data loading ----
/// Loads one or more tables from the API, shows spinner / error / offline banner,
/// and supports pull-to-refresh. [builder] must return a scrollable (ListView).
class DataView extends StatefulWidget {
  const DataView({super.key, required this.tables, required this.builder});
  final List<String> tables;
  final Widget Function(BuildContext context, Map<String, List<Rec>> data, Future<void> Function() reload) builder;

  @override
  State<DataView> createState() => _DataViewState();
}

class _DataViewState extends State<DataView> {
  Map<String, List<Rec>>? _data;
  Object? _error;
  bool _loading = true;
  Timer? _pollTimer;
  Repo? _repo;

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-poll every 3 seconds so additions/edits from Web reflect in Mobile automatically
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = context.read<Repo>();
    if (_repo != r) {
      _repo?.removeListener(_onRepoChanged);
      _repo = r;
      _repo?.addListener(_onRepoChanged);
    }
  }

  void _onRepoChanged() {
    if (mounted) _load(silent: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _repo?.removeListener(_onRepoChanged);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final repo = context.read<Repo>();
    if (!silent && _data == null) setState(() => _loading = true);
    try {
      // A table the role may not read (HTTP 403) simply shows as empty, so one
      // forbidden lookup table never blanks a whole screen.
      final results = await Future.wait(widget.tables.map((t) async {
        try {
          return await repo.list(t);
        } on ApiException catch (e) {
          if (e.status == 403) return <Rec>[];
          rethrow;
        }
      }));
      if (!mounted) return;
      setState(() {
        _data = {for (var i = 0; i < widget.tables.length; i++) widget.tables[i]: results[i]};
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_data == null) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator(color: C.green));
    }
    if (_data == null) {
      return ErrorState(errText(_error ?? 'Failed to load'), onRetry: _load);
    }
    final repo = context.read<Repo>();
    return Column(children: [
      ValueListenableBuilder<bool>(
        valueListenable: repo.offline,
        builder: (_, off, __) => off
            ? Container(
                width: double.infinity,
                color: C.amberLt,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                child: const Row(children: [
                  Icon(Icons.cloud_off, size: 15, color: C.amber),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text('Offline — showing last saved data. Pull down to retry.',
                          style: TextStyle(fontSize: 12, color: C.amber, fontWeight: FontWeight.w600))),
                ]),
              )
            : const SizedBox.shrink(),
      ),
      Expanded(
        child: RefreshIndicator(
          color: C.green,
          onRefresh: _load,
          child: widget.builder(context, _data!, _load),
        ),
      ),
    ]);
  }
}

/// Client-side join helper: id -> row.
Map<String, Rec> indexBy(List<Rec> rows, String key) => {for (final r in rows) s(r[key]): r};

/// Edit / Delete overflow menu used on list cards (replaces the web row action icons).
class RowActions extends StatelessWidget {
  const RowActions({super.key, this.onEdit, this.onDelete});
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_vert, size: 20, color: C.ink3),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        onSelected: (v) => v == 'edit' ? onEdit?.call() : onDelete?.call(),
        itemBuilder: (_) => [
          if (onEdit != null) const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (onDelete != null) PopupMenuItem(value: 'del', child: Text('Delete', style: TextStyle(color: C.redDk))),
        ],
      );
}

/// Primary add button, matches the web "＋ New …" buttons.
FloatingActionButton addFab(String label, VoidCallback onPressed) => FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: C.green,
      foregroundColor: Colors.white,
      elevation: 2,
      icon: const Icon(Icons.add),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
