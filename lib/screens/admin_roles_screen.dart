import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/auth.dart';
import '../core/theme.dart';
import '../widgets/ui.dart';

const _roleLabels = {
  'management': 'Management',
  'assessor': 'Assessor',
  'nurse': 'Nurse / Attendant',
  'family': 'Family',
};

const _screenLabels = {
  'dashboard': 'Dashboard',
  'enquiry': 'Enquiries',
  'clients': 'Clients & Patients',
  'assessment': 'Patient Assessment',
  'duty': 'Duty Roster',
  'attendance': 'Attendance',
  'leave': 'Leave Requests',
  'nurseapp': 'Patient Summary & Charts',
  'billing': 'Client Billing',
  'payroll': 'Nurse Payroll',
  'masters': 'Masters',
  'roles': 'Role Management',
  'users': 'User Management',
};

/// GET/PUT /api/admin/roles — which screens each role can see (shared by web + mobile).
class AdminRolesScreen extends StatefulWidget {
  const AdminRolesScreen({super.key});
  @override
  State<AdminRolesScreen> createState() => _AdminRolesScreenState();
}

class _AdminRolesScreenState extends State<AdminRolesScreen> {
  Map<String, Set<String>>? _map;
  String _role = 'management';
  String? _error;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<ApiClient>().get('/admin/roles') as Map;
      if (!mounted) return;
      setState(() {
        _map = {for (final e in d.entries) e.key.toString(): ((e.value as List).map((x) => x.toString()).toSet())};
        _error = null;
        _dirty = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<ApiClient>().put('/admin/roles/$_role', {'screens': (_map![_role] ?? {}).toList()});
      if (mounted) {
        setState(() => _dirty = false);
        toast(context, 'Saved access for ${_roleLabels[_role] ?? _role}');
      }
    } catch (e) {
      if (mounted) toast(context, errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorState(_error!, onRetry: _load);
    if (_map == null) return const Center(child: CircularProgressIndicator(color: C.green));
    final sel = _map!.putIfAbsent(_role, () => <String>{});
    return ListView(physics: kScrollPhysics, padding: kPagePad, children: [
      const PageHeader(eyebrow: 'Configuration', title: 'Role Management', subtitle: 'Choose which screens each role can open.'),
      Seg(
        options: _roleLabels.values.toList(),
        value: _roleLabels[_role]!,
        onChanged: (v) => setState(() => _role = _roleLabels.entries.firstWhere((e) => e.value == v).key),
      ),
      const SizedBox(height: 14),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(children: [
          for (final k in kAllScreens)
            SwitchListTile(
              dense: true,
              activeColor: C.green,
              title: Text(_screenLabels[k] ?? k, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              value: sel.contains(k),
              onChanged: (v) => setState(() {
                v ? sel.add(k) : sel.remove(k);
                _dirty = true;
              }),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: (_saving || !_dirty) ? null : _save,
        child: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Save access'),
      ),
      const SizedBox(height: 8),
      const Text('Changes apply the next time that role signs in.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.ink3)),
    ]);
  }
}
