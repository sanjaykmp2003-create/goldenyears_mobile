import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/ui.dart';

/// /api/admin/users — create / edit / deactivate app users (management only).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Rec>? _users;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<ApiClient>().get('/admin/users') as List;
      if (!mounted) return;
      setState(() {
        _users = d.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    }
  }

  Future<void> _edit(BuildContext ctx, Rec? u) async {
    final api = ctx.read<ApiClient>();
    final isEdit = u != null;
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Configuration',
      title: isEdit ? 'Edit user' : 'New user',
      subtitle: isEdit ? s(u!['username']) : null,
      fields: [
        if (!isEdit) const FieldSpec('username', 'Username', required: true),
        FieldSpec('user_type', 'Role', type: FT.select, required: true, options: const [
          Opt('management', 'Management'),
          Opt('assessor', 'Assessor'),
          Opt('nurse', 'Nurse / Attendant'),
          Opt('family', 'Family'),
        ]),
        const FieldSpec('linked_id', 'Linked ID', hint: 'nurse_id for nurses, client_id for family'),
        FieldSpec('password', isEdit ? 'New password (leave blank to keep)' : 'Password', type: FT.password, required: !isEdit),
        if (isEdit) const FieldSpec('is_active', 'Account active', type: FT.toggle),
      ],
      initial: u ?? const {'user_type': 'nurse'},
      saveLabel: isEdit ? 'Save changes' : 'Create user',
      onSave: (v) async {
        final body = <String, dynamic>{
          ...v,
          if (v['password'] == null) 'password': null,
        }..removeWhere((k, val) => val == null && k != 'linked_id');
        if (isEdit) {
          await api.put('/admin/users/${Uri.encodeComponent(s(u!['user_id']))}', body);
        } else {
          await api.post('/admin/users', body);
        }
      },
    );
    if (ok) await _load();
  }

  Future<void> _delete(BuildContext ctx, Rec u) async {
    if (!await confirmDialog(ctx, title: 'Deactivate user?', text: '${s(u['username'])} will no longer be able to sign in.', action: 'Deactivate')) return;
    try {
      await ctx.read<ApiClient>().delete('/admin/users/${Uri.encodeComponent(s(u['user_id']))}');
      await _load();
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorState(_error!, onRetry: _load);
    if (_users == null) return const Center(child: CircularProgressIndicator(color: C.green));
    final rows = _users!.where((u) => _q.isEmpty || s(u['username']).toLowerCase().contains(_q.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: addFab('New user', () => _edit(context, null)),
      body: RefreshIndicator(
        color: C.green,
        onRefresh: _load,
        child: ListView(physics: kScrollPhysics, padding: kPagePad, children: [
          PageHeader(eyebrow: 'Configuration', title: 'User Management', subtitle: '${_users!.length} accounts'),
          SearchBox(hint: 'Search username', onChanged: (v) => setState(() => _q = v)),
          const SizedBox(height: 14),
          if (rows.isEmpty) const EmptyState('No users.', icon: Icons.manage_accounts_outlined),
          for (final u in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => _edit(context, u),
                child: Row(children: [
                  Avatar(s(u['username']), tone: Tone.purple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s(u['username']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${s(u['user_type'])}${s(u['linked_id']).isEmpty ? '' : ' · ${s(u['linked_id'])}'}',
                          style: const TextStyle(fontSize: 12.5, color: C.ink3)),
                      if (u['last_login_at'] != null)
                        Text('Last login ${prettyDateTime(u['last_login_at'])}', style: const TextStyle(fontSize: 11.5, color: C.ink3)),
                    ]),
                  ),
                  Tag(b(u['is_active']) ? 'Active' : 'Inactive', tone: b(u['is_active']) ? Tone.green : Tone.red, dot: true),
                  RowActions(onEdit: () => _edit(context, u), onDelete: () => _delete(context, u)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
