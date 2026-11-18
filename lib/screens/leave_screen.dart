import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/auth.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/rules.dart';
import '../core/theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/ui.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  String _filter = 'All';
  Future<void> Function()? _doReload;

  bool get _isNurse => widget.user.isNurse && widget.user.linkedId != null;

  Future<void> _edit(BuildContext ctx, Rec? l, List<Rec> nurses, List<Rec> allLeaves) async {
    final repo = ctx.read<Repo>();
    final isEdit = l != null;
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Care delivery',
      title: isEdit ? 'Edit leave request' : 'New leave request',
      subtitle: isEdit ? s(l!['leave_id']) : null,
      fields: [
        if (!_isNurse)
          FieldSpec('nurse_id', 'Nurse / attendant', type: FT.select, required: true, options: [
            for (final x in nurses) Opt(s(x['nurse_id']), '${s(x['full_name'])} · ${s(x['role'])}'),
          ]),
        FieldSpec('leave_type', 'Leave type', type: FT.select, required: true, options: opts(['Casual Leave', 'Sick Leave', 'Earned Leave', 'Emergency', 'Loss of Pay'])),
        const FieldSpec('from_date', 'From', type: FT.date, required: true, halfWidth: true),
        const FieldSpec('to_date', 'To', type: FT.date, required: true, halfWidth: true),
        const FieldSpec('reason', 'Reason', type: FT.multiline),
      ],
      initial: l ?? {'leave_type': 'Casual Leave', 'from_date': today(), 'to_date': today(), if (_isNurse) 'nurse_id': widget.user.linkedId},
      saveLabel: isEdit ? 'Save changes' : 'Submit request',
      onSave: (v) async {
        final nurseId = _isNurse ? widget.user.linkedId! : s(v['nurse_id']);
        // R4.2 overlap check against this nurse's other leave (ignores rejected ones)
        final existing = allLeaves
            .where((x) => s(x['nurse_id']) == nurseId && s(x['status']) != 'Rejected' && (!isEdit || s(x['leave_id']) != s(l!['leave_id'])))
            .map((x) => [dateOnly(x['from_date']), dateOnly(x['to_date'])])
            .toList();
        final r = canApplyLeave(s(v['from_date']), s(v['to_date']), existing);
        if (!r.allowed) throw ApiException(422, r.message);
        final body = <String, dynamic>{...v, 'nurse_id': nurseId};
        if (isEdit) {
          await repo.update('leave_request', s(l!['leave_id']), body);
        } else {
          await repo.create('leave_request', {
            ...body,
            'leave_id': Repo.newId('LEV'),
            'status': 'Pending',
            'requested_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      },
    );
    if (ok) await _doReload?.call();
  }

  Future<void> _review(BuildContext ctx, Rec l, String status) async {
    try {
      await ctx.read<Repo>().update('leave_request', s(l['leave_id']), {'status': status, 'approver_id': widget.user.userId});
      await _doReload?.call();
      if (ctx.mounted) toast(ctx, 'Leave $status');
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }

  Future<void> _delete(BuildContext ctx, Rec l) async {
    if (!await confirmDialog(ctx, text: 'This leave request will be removed.')) return;
    try {
      await ctx.read<Repo>().remove('leave_request', s(l['leave_id']));
      await _doReload?.call();
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DataView(
      tables: const ['leave_request', 'nurse_master'],
      builder: (ctx, d, reload) {
        _doReload = reload;
        var rows = d['leave_request']!;
        final nurses = d['nurse_master']!;
        final nById = indexBy(nurses, 'nurse_id');
        if (_isNurse) rows = rows.where((x) => s(x['nurse_id']) == widget.user.linkedId).toList();
        final allLeaves = d['leave_request']!;
        final filtered = rows.where((x) => _filter == 'All' || s(x['status']) == _filter).toList()
          ..sort((a, b) => dateOnly(b['from_date']).compareTo(dateOnly(a['from_date'])));
        final pending = rows.where((x) => s(x['status']) == 'Pending').length;
        final approved = rows.where((x) => s(x['status']) == 'Approved').length;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: addFab('New leave', () => _edit(ctx, null, nurses, allLeaves)),
          body: ListView(physics: kScrollPhysics, padding: kPagePad, children: [
            const PageHeader(eyebrow: 'Care Delivery', title: 'Leave Requests', subtitle: 'Apply for leave and review requests.'),
            TwoUp([
              Kpi(label: 'Pending review', value: '$pending', icon: Icons.hourglass_empty, tone: Tone.amber),
              Kpi(label: 'Approved', value: '$approved', icon: Icons.check_circle_outline, tone: Tone.green),
            ]),
            const SizedBox(height: 16),
            Seg(options: const ['All', 'Pending', 'Approved', 'Rejected'], value: _filter, onChanged: (v) => setState(() => _filter = v)),
            const SizedBox(height: 14),
            if (filtered.isEmpty) const EmptyState('No leave requests.', icon: Icons.event_available_outlined),
            for (final l in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Avatar(s(nById[s(l['nurse_id'])]?['full_name'], s(l['nurse_id'])), tone: Tone.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s(nById[s(l['nurse_id'])]?['full_name'], s(l['nurse_id'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${s(l['leave_type'], 'Leave')} · ${prettyDate(l['from_date'])} → ${prettyDate(l['to_date'])}',
                              style: const TextStyle(fontSize: 12.5, color: C.ink3)),
                        ]),
                      ),
                      Tag(s(l['status'], 'Pending'), tone: toneFor(s(l['status'])), dot: true),
                      if (s(l['status']) == 'Pending' || widget.user.isManagement)
                        RowActions(onEdit: () => _edit(ctx, l, nurses, allLeaves), onDelete: () => _delete(ctx, l)),
                    ]),
                    if (s(l['reason']).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(s(l['reason']), style: const TextStyle(fontSize: 13, color: C.ink2)),
                    ],
                    if (widget.user.isManagement && s(l['status']) == 'Pending') ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: () => _review(ctx, l, 'Rejected'), child: const Text('Reject'))),
                        const SizedBox(width: 10),
                        Expanded(child: FilledButton(onPressed: () => _review(ctx, l, 'Approved'), child: const Text('Approve'))),
                      ]),
                    ],
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}
