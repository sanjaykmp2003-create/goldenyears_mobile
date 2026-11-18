import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/auth.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/rules.dart';
import '../core/theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/ui.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String _filter = 'All';
  bool _busy = false;
  Future<void> Function()? _doReload;

  bool get _isNurse => widget.user.isNurse && widget.user.linkedId != null;

  // ---------------------------------------------------------- nurse actions
  Future<void> _checkIn(BuildContext ctx, List<Rec> mine, List<Rec> leaves, List<Rec> duties) async {
    final nurseId = widget.user.linkedId!;
    final day = today();
    final approved = <String>{};
    for (final l in leaves.where((l) => s(l['nurse_id']) == nurseId && s(l['status']) == 'Approved')) {
      approved.addAll(datesBetween(dateOnly(l['from_date']), dateOnly(l['to_date'])));
    }
    var hours = 0.0;
    for (final a in mine.where((a) => dateOnly(a['shift_date']) == day)) {
      final i = DateTime.tryParse(s(a['check_in_at']));
      final o = DateTime.tryParse(s(a['check_out_at']));
      if (i != null && o != null) hours += o.difference(i).inMinutes / 60.0;
    }
    final r = canCheckIn(shiftDate: day, approvedLeaveDates: approved, hoursLoggedToday: hours);
    if (!r.allowed) {
      toast(ctx, r.message);
      return;
    }
    final duty = duties.where((d) => s(d['nurse_id']) == nurseId && s(d['status']) == 'Active').toList();
    await _run(ctx, () async {
      await ctx.read<Repo>().create('attendance', {
        'attendance_id': Repo.newId('ATT'),
        'nurse_id': nurseId,
        'duty_id': duty.isEmpty ? null : s(duty.first['duty_id']),
        'shift_date': day,
        'check_in_at': DateTime.now().toUtc().toIso8601String(),
        'status': 'Present',
        'shift_mode': duty.isEmpty ? null : s(duty.first['shift_mode']),
      });
      if (ctx.mounted) toast(ctx, 'Checked in');
    });
  }

  Future<void> _checkOut(BuildContext ctx, Rec open) async {
    final r = canEditAttendance(dateOnly(open['shift_date']));
    if (!r.allowed) {
      toast(ctx, r.message);
      return;
    }
    final i = DateTime.tryParse(s(open['check_in_at']));
    final now = DateTime.now();
    await _run(ctx, () async {
      await ctx.read<Repo>().update('attendance', s(open['attendance_id']), {
        'check_out_at': now.toUtc().toIso8601String(),
        if (i != null) 'hours_worked': double.parse((now.difference(i).inMinutes / 60.0).toStringAsFixed(2)),
      });
      if (ctx.mounted) toast(ctx, 'Checked out');
    });
  }

  Future<void> _run(BuildContext ctx, Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
      await _doReload?.call();
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------ management actions
  Future<void> _edit(BuildContext ctx, Rec? a, List<Rec> nurses) async {
    final repo = ctx.read<Repo>();
    final isEdit = a != null;
    if (isEdit && !widget.user.isManagement) {
      final r = canEditAttendance(dateOnly(a['shift_date']));
      if (!r.allowed) {
        toast(ctx, r.message);
        return;
      }
    }
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Care delivery',
      title: isEdit ? 'Edit attendance' : 'Mark attendance',
      subtitle: isEdit ? s(a!['attendance_id']) : null,
      fields: [
        FieldSpec('nurse_id', 'Nurse / attendant', type: FT.select, required: true, options: [
          for (final x in nurses) Opt(s(x['nurse_id']), '${s(x['full_name'])} · ${s(x['role'])}'),
        ]),
        const FieldSpec('shift_date', 'Shift date', type: FT.date, required: true),
        FieldSpec('status', 'Status', type: FT.select, required: true, options: opts(['Present', 'Absent', 'On Leave'])),
      ],
      initial: a ?? {'shift_date': today(), 'status': 'Present'},
      saveLabel: isEdit ? 'Save changes' : 'Mark',
      onSave: (v) async {
        if (isEdit) {
          await repo.update('attendance', s(a!['attendance_id']), v);
        } else {
          await repo.create('attendance', {
            ...v,
            'attendance_id': Repo.newId('ATT'),
            'check_in_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      },
    );
    if (ok) await _doReload?.call();
  }

  Future<void> _delete(BuildContext ctx, Rec a) async {
    if (!widget.user.isManagement) {
      final r = canEditAttendance(dateOnly(a['shift_date']));
      if (!r.allowed) {
        toast(ctx, r.message);
        return;
      }
    }
    if (!await confirmDialog(ctx, text: 'This attendance record will be removed.')) return;
    try {
      await ctx.read<Repo>().remove('attendance', s(a['attendance_id']));
      await _doReload?.call();
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canMark = widget.user.isManagement;
    return DataView(
      tables: const ['attendance', 'nurse_master', 'leave_request', 'duty_roster'],
      builder: (ctx, d, reload) {
        _doReload = reload;
        var rows = d['attendance']!;
        final nurses = d['nurse_master']!;
        final nById = indexBy(nurses, 'nurse_id');
        if (_isNurse) rows = rows.where((a) => s(a['nurse_id']) == widget.user.linkedId).toList();
        rows = [...rows]..sort((a, b) {
            final c = dateOnly(b['shift_date']).compareTo(dateOnly(a['shift_date']));
            return c != 0 ? c : s(b['check_in_at']).compareTo(s(a['check_in_at']));
          });

        final filtered = rows.where((r) => _filter == 'All' || s(r['status']) == _filter).toList();
        final todayRows = rows.where((r) => dateOnly(r['shift_date']) == today()).toList();
        final present = todayRows.where((r) => s(r['status']) == 'Present').length;
        final absent = todayRows.where((r) => s(r['status']) == 'Absent').length;
        final openRec = todayRows.where((r) => s(r['check_in_at']).isNotEmpty && s(r['check_out_at']).isEmpty && s(r['status']) == 'Present').toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: canMark ? addFab('Mark attendance', () => _edit(ctx, null, nurses)) : null,
          body: ListView(physics: kScrollPhysics, padding: kPagePad, children: [
            PageHeader(
              eyebrow: 'Care Delivery',
              title: 'Attendance',
              subtitle: _isNurse ? 'Check in when your shift starts, check out when it ends.' : 'Daily attendance for nurses and attendants.',
            ),
            if (_isNurse)
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: openRec.isNotEmpty ? C.greenLt : C.navyLt, borderRadius: BorderRadius.circular(12)),
                      child: Icon(openRec.isNotEmpty ? Icons.timer_outlined : Icons.login, color: openRec.isNotEmpty ? C.greenDk : C.navy),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(openRec.isNotEmpty ? 'On shift' : 'Not checked in', style: serif(18)),
                        Text(
                          openRec.isNotEmpty ? 'Since ${prettyTime(openRec.first['check_in_at'])}' : prettyDate(today()),
                          style: const TextStyle(fontSize: 12.5, color: C.ink3),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => openRec.isNotEmpty ? _checkOut(ctx, openRec.first) : _checkIn(ctx, rows, d['leave_request']!, d['duty_roster']!),
                    style: openRec.isNotEmpty ? FilledButton.styleFrom(backgroundColor: C.navy) : null,
                    icon: Icon(openRec.isNotEmpty ? Icons.logout : Icons.login, size: 18),
                    label: Text(openRec.isNotEmpty ? 'Check out' : 'Check in now'),
                  ),
                ]),
              )
            else
              TwoUp([
                Kpi(label: 'Present today', value: '$present', icon: Icons.check_circle_outline, tone: Tone.green),
                Kpi(label: 'Absent today', value: '$absent', icon: Icons.cancel_outlined, tone: Tone.red),
              ]),
            const SizedBox(height: 16),
            Seg(options: const ['All', 'Present', 'Absent', 'On Leave'], value: _filter, onChanged: (v) => setState(() => _filter = v)),
            const SizedBox(height: 14),
            if (filtered.isEmpty) const EmptyState('No attendance records.', icon: Icons.access_time),
            for (final a in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: canMark ? () => _edit(ctx, a, nurses) : null,
                  child: Row(children: [
                    Avatar(s(nById[s(a['nurse_id'])]?['full_name'], s(a['nurse_id'])), tone: Tone.navy),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s(nById[s(a['nurse_id'])]?['full_name'], s(a['nurse_id'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${prettyDate(a['shift_date'])} · ${prettyTime(a['check_in_at'])} – ${prettyTime(a['check_out_at'])}',
                          style: const TextStyle(fontSize: 12.5, color: C.ink3),
                        ),
                      ]),
                    ),
                    Tag(s(a['status'], '—'), tone: toneFor(s(a['status'])), dot: true),
                    if (canMark) RowActions(onEdit: () => _edit(ctx, a, nurses), onDelete: () => _delete(ctx, a)),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}
