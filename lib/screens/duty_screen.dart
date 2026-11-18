import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/auth.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/ui.dart';

class DutyScreen extends StatefulWidget {
  const DutyScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<DutyScreen> createState() => _DutyScreenState();
}

class _DutyScreenState extends State<DutyScreen> {
  String _type = 'All';
  String _shift = 'All';
  Future<void> Function()? _doReload;

  bool _isAttendantRole(String? role) {
    final r = (role ?? '').toLowerCase();
    return r.contains('caregiver') || r.contains('attendant');
  }

  String _staffType(Rec d, Rec? nurse) {
    final t = s(d['staff_type']);
    if (t == 'Attendant' || t == 'Nurse') return t;
    return _isAttendantRole(s(nurse?['role'])) ? 'Attendant' : 'Nurse';
  }

  String _shiftOf(Rec d) {
    final a = s(d['assigned_shift']);
    if (a.isNotEmpty) return a;
    final m = s(d['shift_mode']);
    if (m.contains('24')) return '24 Hours';
    if (m.toLowerCase().contains('night')) return 'Night Shift';
    return 'Day Shift';
  }

  Future<void> _edit(BuildContext ctx, Rec? d, List<Rec> patients, List<Rec> staff, Map<String, Rec> nurseById) async {
    final repo = ctx.read<Repo>();
    final isEdit = d != null;
    final initial = <String, dynamic>{
      'staff_type': 'Nurse',
      'assigned_shift': 'Day Shift',
      'status': 'Active',
      'start_date': today(),
      if (d != null) ...{
        ...d,
        'staff_type': _staffType(d, nurseById[s(d['nurse_id'])]),
        'assigned_shift': _shiftOf(d),
      },
    };
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Care delivery',
      title: isEdit ? 'Edit duty assignment' : 'Assign duty',
      subtitle: isEdit ? s(d!['duty_id']) : 'Map an attendant or nurse to a patient',
      fields: [
        FieldSpec('patient_id', 'Patient', type: FT.select, required: true, options: [
          for (final p in patients) Opt(s(p['patient_id']), s(p['full_name'], s(p['patient_id']))),
        ]),
        const FieldSpec('staff_type', 'Staff type', type: FT.select, required: true, options: [
          Opt('Attendant', 'Attendant (Caregiver)'),
          Opt('Nurse', 'Nurse (Staff / ICU Nurse)'),
        ]),
        FieldSpec('nurse_id', 'Assigned staff', type: FT.select, required: true, options: [
          for (final n in staff) Opt(s(n['nurse_id']), '${s(n['full_name'])} · ${s(n['role'])}'),
        ]),
        const FieldSpec('assigned_shift', 'Shift', type: FT.select, required: true, options: [
          Opt('Day Shift', 'Day Shift (08:00 – 20:00)'),
          Opt('Night Shift', 'Night Shift (20:00 – 08:00)'),
          Opt('24 Hours', '24 Hours (Full-Time / Live-in)'),
        ]),
        const FieldSpec('start_date', 'Start date', type: FT.date, required: true, halfWidth: true),
        const FieldSpec('end_date', 'End date', type: FT.date, halfWidth: true),
        FieldSpec('status', 'Status', type: FT.select, options: opts(['Active', 'Scheduled', 'Completed', 'Cancelled'])),
      ],
      initial: initial,
      saveLabel: isEdit ? 'Save changes' : 'Assign duty',
      onSave: (v) async {
        final body = <String, dynamic>{
          'patient_id': v['patient_id'],
          'nurse_id': v['nurse_id'],
          'staff_type': v['staff_type'],
          'assigned_shift': v['assigned_shift'],
          'shift_mode': '${v['staff_type']} — ${v['assigned_shift']}',
          'start_date': v['start_date'],
          'end_date': v['end_date'],
          'status': v['status'] ?? 'Active',
        };
        if (isEdit) {
          await repo.update('duty_roster', s(d!['duty_id']), body);
        } else {
          await repo.create('duty_roster', {...body, 'duty_id': Repo.newId('DTY')});
        }
      },
    );
    if (ok) await _doReload?.call();
  }

  Future<void> _delete(BuildContext ctx, Rec d) async {
    if (!await confirmDialog(ctx, text: 'This duty assignment will be removed.')) return;
    try {
      await ctx.read<Repo>().remove('duty_roster', s(d['duty_id']));
      await _doReload?.call();
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.user.isManagement;
    return DataView(
      tables: const ['duty_roster', 'patient', 'nurse_master'],
      builder: (ctx, data, reload) {
        _doReload = reload;
        var duties = data['duty_roster']!;
        if (widget.user.isNurse && widget.user.linkedId != null) {
          duties = duties.where((x) => s(x['nurse_id']) == widget.user.linkedId).toList();
        }
        final patients = data['patient']!;
        final staff = data['nurse_master']!;
        final pById = indexBy(patients, 'patient_id');
        final nById = indexBy(staff, 'nurse_id');

        final rows = duties.where((d) {
          if (_type != 'All' && _staffType(d, nById[s(d['nurse_id'])]) != _type) return false;
          if (_shift != 'All' && _shiftOf(d) != _shift) return false;
          return true;
        }).toList()
          ..sort((a, b) => s(b['start_date']).compareTo(s(a['start_date'])));

        int count(bool Function(Rec) f) => duties.where(f).length;
        final attendants = count((d) => _staffType(d, nById[s(d['nurse_id'])]) == 'Attendant');
        final nurses = count((d) => _staffType(d, nById[s(d['nurse_id'])]) == 'Nurse');
        final day = count((d) => _shiftOf(d) == 'Day Shift');
        final night = count((d) => _shiftOf(d) != 'Day Shift');

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: canEdit ? addFab('Assign duty', () => _edit(ctx, null, patients, staff, nById)) : null,
          body: ListView(physics: kScrollPhysics, padding: kPagePad, children: [
            const PageHeader(
              eyebrow: 'Care Delivery',
              title: 'Duty Roster',
              subtitle: 'Shift assignments for attendants and nurses mapped to patients.',
            ),
            TwoUp([
              Kpi(label: 'Attendants', value: '$attendants', icon: Icons.volunteer_activism_outlined, tone: Tone.blue),
              Kpi(label: 'Nurses', value: '$nurses', icon: Icons.medical_services_outlined, tone: Tone.purple),
              Kpi(label: 'Day shifts', value: '$day', icon: Icons.wb_sunny_outlined, tone: Tone.amber),
              Kpi(label: 'Night / 24h', value: '$night', icon: Icons.nights_stay_outlined, tone: Tone.navy),
            ]),
            const SizedBox(height: 16),
            Seg(options: const ['All', 'Attendant', 'Nurse'], value: _type, onChanged: (v) => setState(() => _type = v)),
            const SizedBox(height: 8),
            Seg(options: const ['All', 'Day Shift', 'Night Shift', '24 Hours'], value: _shift, onChanged: (v) => setState(() => _shift = v)),
            const SizedBox(height: 14),
            if (rows.isEmpty) const EmptyState('No duty assignments.', icon: Icons.calendar_month_outlined),
            for (final d in rows)
              Builder(builder: (_) {
                final nurse = nById[s(d['nurse_id'])];
                final type = _staffType(d, nurse);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    onTap: canEdit ? () => _edit(ctx, d, patients, staff, nById) : null,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Avatar(s(nurse?['full_name'], s(d['nurse_id'])), tone: type == 'Attendant' ? Tone.blue : Tone.purple),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s(nurse?['full_name'], s(d['nurse_id'])), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            Text('→ ${s(pById[s(d['patient_id'])]?['full_name'], s(d['patient_id'], '—'))}',
                                style: const TextStyle(fontSize: 12.5, color: C.ink2)),
                          ]),
                        ),
                        Tag(s(d['status'], 'Active'), tone: toneFor(s(d['status'])), dot: true),
                        if (canEdit) RowActions(onEdit: () => _edit(ctx, d, patients, staff, nById), onDelete: () => _delete(ctx, d)),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        Tag(type, tone: type == 'Attendant' ? Tone.blue : Tone.purple),
                        Tag(_shiftOf(d), tone: Tone.grey),
                        Tag('${prettyDate(d['start_date'])} → ${s(d['end_date']).isEmpty ? 'ongoing' : prettyDate(d['end_date'])}', tone: Tone.grey),
                      ]),
                    ]),
                  ),
                );
              }),
          ]),
        );
      },
    );
  }
}
