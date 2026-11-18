import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/theme.dart';

enum FT { text, multiline, number, date, select, toggle, phone, email, password }

class Opt {
  final String value;
  final String label;
  const Opt(this.value, this.label);
}

List<Opt> opts(List<String> v) => v.map((e) => Opt(e, e)).toList();

class FieldSpec {
  final String key;
  final String label;
  final FT type;
  final List<Opt> options;
  final bool required;
  final String? hint;
  final String? section; // renders a "fieldset title" above this field
  final bool halfWidth;
  final bool Function(Map<String, dynamic> values)? visibleIf;
  const FieldSpec(
    this.key,
    this.label, {
    this.type = FT.text,
    this.options = const [],
    this.required = false,
    this.hint,
    this.section,
    this.halfWidth = false,
    this.visibleIf,
  });
}

/// Opens a bottom-sheet form (the mobile equivalent of the web "drawer").
/// [onSave] receives typed values: text -> String?, number -> num?, date -> 'yyyy-MM-dd'?,
/// select -> String?, toggle -> bool. Throw to show an error inside the sheet.
/// Returns true if saved.
Future<bool> showFormSheet(
  BuildContext context, {
  required String eyebrow,
  required String title,
  String? subtitle,
  required List<FieldSpec> fields,
  Map<String, dynamic> initial = const {},
  String saveLabel = 'Save',
  required Future<void> Function(Map<String, dynamic> values) onSave,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _FormSheet(
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      fields: fields,
      initial: initial,
      saveLabel: saveLabel,
      onSave: onSave,
    ),
  );
  return r == true;
}

class _FormSheet extends StatefulWidget {
  const _FormSheet({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.initial,
    required this.saveLabel,
    required this.onSave,
  });
  final String eyebrow, title, saveLabel;
  final String? subtitle;
  final List<FieldSpec> fields;
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  final Map<String, dynamic> _v = {};
  final Map<String, TextEditingController> _c = {};
  bool _saving = false;
  String? _error;
  final Set<String> _missing = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final raw = widget.initial[f.key];
      switch (f.type) {
        case FT.toggle:
          _v[f.key] = b(raw);
          break;
        case FT.date:
          _v[f.key] = dateOnly(raw);
          break;
        case FT.select:
          _v[f.key] = s(raw);
          break;
        case FT.number:
          _c[f.key] = TextEditingController(text: raw == null ? '' : _trimNum(raw));
          break;
        default:
          _c[f.key] = TextEditingController(text: s(raw));
      }
    }
  }

  String _trimNum(dynamic raw) {
    final d = n(raw);
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _snapshot() {
    final out = <String, dynamic>{};
    for (final f in widget.fields) {
      switch (f.type) {
        case FT.toggle:
          out[f.key] = _v[f.key] == true;
          break;
        case FT.date:
        case FT.select:
          final t = s(_v[f.key]);
          out[f.key] = t.isEmpty ? null : t;
          break;
        case FT.number:
          out[f.key] = numOrNull(_c[f.key]!.text);
          break;
        default:
          final t = _c[f.key]!.text.trim();
          out[f.key] = t.isEmpty ? null : t;
      }
    }
    return out;
  }

  Future<void> _submit() async {
    final vals = _snapshot();
    final missing = <String>{};
    for (final f in widget.fields) {
      if (f.visibleIf != null && !f.visibleIf!(vals)) continue;
      if (f.required) {
        final x = vals[f.key];
        if (x == null || (x is String && x.isEmpty)) missing.add(f.key);
      }
    }
    if (missing.isNotEmpty) {
      setState(() {
        _missing
          ..clear()
          ..addAll(missing);
        _error = 'Please fill the highlighted required fields.';
      });
      return;
    }
    // drop values of hidden fields
    for (final f in widget.fields) {
      if (f.visibleIf != null && !f.visibleIf!(vals)) vals.remove(f.key);
    }
    setState(() {
      _saving = true;
      _error = null;
      _missing.clear();
    });
    try {
      await widget.onSave(vals);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ApiException ? e.message : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot(); // for conditional visibility
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final children = <Widget>[];
    var i = 0;
    final visible = widget.fields.where((f) => f.visibleIf == null || f.visibleIf!(snap)).toList();
    while (i < visible.length) {
      final f = visible[i];
      if (f.section != null) {
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 22, bottom: 12),
          child: Row(children: [
            Text(f.section!.toUpperCase(),
                style: const TextStyle(fontSize: 11, letterSpacing: .9, color: C.ink3, fontWeight: FontWeight.w700)),
            const SizedBox(width: 9),
            const Expanded(child: Divider()),
          ]),
        ));
      }
      // pair two consecutive half-width fields on one row
      if (f.halfWidth && i + 1 < visible.length && visible[i + 1].halfWidth && visible[i + 1].section == null) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _field(f)),
            const SizedBox(width: 10),
            Expanded(child: _field(visible[i + 1])),
          ]),
        ));
        i += 2;
      } else {
        children.add(Padding(padding: const EdgeInsets.only(bottom: 14), child: _field(f)));
        i += 1;
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(mainAxisSize: MainAxisSize.max, children: [
        // header (mirrors .drawer-head)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.eyebrow.toUpperCase(),
                    style: const TextStyle(fontSize: 11, letterSpacing: 1.2, color: C.greenDk, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(widget.title, style: serif(21)),
                if (widget.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(widget.subtitle!, style: const TextStyle(fontSize: 12.5, color: C.ink3)),
                  ),
              ]),
            ),
            IconButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              icon: const Icon(Icons.close, size: 20),
              style: IconButton.styleFrom(side: const BorderSide(color: C.line)),
            ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: C.redLt,
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(left: BorderSide(color: C.red, width: 4)),
                  ),
                  child: Text(_error!, style: const TextStyle(color: C.redDk, fontSize: 13)),
                ),
              ...children,
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          decoration: const BoxDecoration(color: C.surface2, border: Border(top: BorderSide(color: C.line))),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.saveLabel),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _field(FieldSpec f) {
    final err = _missing.contains(f.key);
    final label = f.required ? '${f.label} *' : f.label;
    InputDecoration deco([Widget? suffix]) => InputDecoration(
          labelText: label,
          hintText: f.hint,
          suffixIcon: suffix,
          errorText: err ? 'Required' : null,
          floatingLabelBehavior: FloatingLabelBehavior.always,
        );
    switch (f.type) {
      case FT.toggle:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(9)),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(f.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            value: _v[f.key] == true,
            activeColor: C.green,
            onChanged: (x) => setState(() => _v[f.key] = x),
          ),
        );
      case FT.select:
        final cur = s(_v[f.key]);
        final list = [...f.options];
        if (cur.isNotEmpty && !list.any((o) => o.value == cur)) list.add(Opt(cur, cur));
        return DropdownButtonFormField<String>(
          value: cur.isEmpty ? null : cur,
          isExpanded: true,
          decoration: deco(),
          hint: Text(f.hint ?? 'Select', style: const TextStyle(color: C.ink3, fontSize: 13.5)),
          items: list
              .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (x) => setState(() => _v[f.key] = x ?? ''),
        );
      case FT.date:
        final cur = s(_v[f.key]);
        return InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () async {
            final init = DateTime.tryParse(cur) ?? DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: init,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _v[f.key] = dateOnly(picked.toIso8601String()));
          },
          child: InputDecorator(
            decoration: deco(const Icon(Icons.calendar_today_outlined, size: 18, color: C.ink3)),
            child: Text(cur.isEmpty ? (f.hint ?? 'Select date') : prettyDate(cur),
                style: TextStyle(fontSize: 14, color: cur.isEmpty ? C.ink3 : C.ink)),
          ),
        );
      default:
        return TextField(
          controller: _c[f.key],
          decoration: deco(),
          obscureText: f.type == FT.password,
          minLines: f.type == FT.multiline ? 3 : 1,
          maxLines: f.type == FT.multiline ? 6 : 1,
          keyboardType: switch (f.type) {
            FT.number => const TextInputType.numberWithOptions(decimal: true),
            FT.phone => TextInputType.phone,
            FT.email => TextInputType.emailAddress,
            FT.multiline => TextInputType.multiline,
            _ => TextInputType.text,
          },
          textCapitalization: f.type == FT.text ? TextCapitalization.sentences : TextCapitalization.none,
          onChanged: (_) {
            if (_missing.contains(f.key)) setState(() => _missing.remove(f.key));
            // conditional fields depend on text values: rebuild lightly
            if (widget.fields.any((x) => x.visibleIf != null)) setState(() {});
          },
        );
    }
  }
}
