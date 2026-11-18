import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/auth.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/ui.dart';

/// Nurse-facing patient summary + charting. Every entry is an `activity_log` row
/// (activity_type: vitals | med | io | proc | care) with the type-specific fields in
/// `payload`, plus a matching row in the activity_* detail table, exactly the
/// structure the server schema defines.
class NurseAppScreen extends StatefulWidget {
  const NurseAppScreen({super.key, required this.user});
  final UserContext user;
  @override
  State<NurseAppScreen> createState() => _NurseAppScreenState();
}

class _NurseAppScreenState extends State<NurseAppScreen> {
  static const _tabs = ['Summary', 'Vitals', 'Medication', 'Intake / Output', 'Procedure', 'General care', 'Report'];
  String _tab = 'Summary';
  String? _patientId;
  String _date = today();
  Future<void> Function()? _doReload;

  Map<String, dynamic> _payload(Rec a) {
    try {
      final p = a['payload'];
      if (p is String && p.isNotEmpty) return Map<String, dynamic>.from(jsonDecode(p) as Map);
      if (p is Map) return Map<String, dynamic>.from(p);
    } catch (_) {}
    return {};
  }

  void _shiftDate(int days) {
    final d = DateTime.tryParse(_date) ?? DateTime.now();
    setState(() => _date = dateOnly(d.add(Duration(days: days)).toIso8601String()));
  }

  // ------------------------------------------------------------- logging --
  Future<void> _log(
    BuildContext ctx, {
    required String type,
    required String title,
    required List<FieldSpec> fields,
    required String Function(Map<String, dynamic> v) summary,
    String? detailTable,
    Map<String, dynamic> Function(Map<String, dynamic> v)? detailBody,
    Map<String, dynamic> initial = const {},
  }) async {
    final repo = ctx.read<Repo>();
    final pid = _patientId;
    if (pid == null) {
      toast(ctx, 'Select a patient first.');
      return;
    }
    final now = DateTime.now();
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Nurse chart',
      title: title,
      subtitle: '$_date · ${TimeOfDay.fromDateTime(now).format(ctx)}',
      fields: fields,
      initial: initial,
      saveLabel: 'Save entry',
      onSave: (v) async {
        final id = Repo.newId('ACT');
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        await repo.create('activity_log', {
          'activity_id': id,
          'patient_id': pid,
          'nurse_id': widget.user.linkedId ?? widget.user.userId,
          'activity_type': type,
          'logged_date': _date,
          'logged_time': '$hh:$mm',
          'title': title,
          'detail': summary(v),
          'payload': jsonEncode(v..removeWhere((k, val) => val == null)),
          'created_at': now.toUtc().toIso8601String(),
        });
        if (detailTable != null && detailBody != null) {
          await repo.create(detailTable, {...detailBody(v), 'activity_id': id});
        }
      },
    );
    if (ok) await _doReload?.call();
  }

  Future<void> _submitReport(BuildContext ctx, List<Rec> todays) async {
    final repo = ctx.read<Repo>();
    final pid = _patientId;
    if (pid == null) return;
    int c(String t) => todays.where((a) => s(a['activity_type']) == t).length;
    final summary = 'Vitals ${c('vitals')}, medication ${c('med')}, intake/output ${c('io')}, '
        'procedures ${c('proc')}, general care ${c('care')} entries logged on $_date.';
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Nurse chart',
      title: 'Submit shift report',
      subtitle: _date,
      fields: [
        FieldSpec('shift_type', 'Shift', type: FT.select, required: true, options: opts(['Day Shift', 'Night Shift', '24 Hours'])),
        const FieldSpec('auto_summary', 'Summary', type: FT.multiline, required: true),
      ],
      initial: {'shift_type': 'Day Shift', 'auto_summary': summary},
      saveLabel: 'Submit report',
      onSave: (v) async {
        await repo.create('shift_report', {
          ...v,
          'shift_report_id': Repo.newId('SR'),
          'nurse_id': widget.user.linkedId,
          'patient_id': pid,
          'shift_date': _date,
          'activity_count': todays.length,
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
        });
      },
    );
    if (ok) {
      await _doReload?.call();
      if (ctx.mounted) toast(ctx, 'Shift report submitted');
    }
  }

  // ---------------------------------------------------------------- build --
  @override
  Widget build(BuildContext context) {
    return DataView(
      tables: const ['patient', 'activity_log', 'shift_report', 'medicine_master', 'procedure_master', 'frequency_master'],
      builder: (ctx, d, reload) {
        _doReload = reload;
        final patients = d['patient']!;
        if (patients.isEmpty) {
          return ListView(physics: kScrollPhysics, padding: kPagePad, children: const [
            PageHeader(eyebrow: 'Nurses App', title: 'Patient Summary & Charts'),
            EmptyState('No patients available to chart.', icon: Icons.personal_injury_outlined),
          ]);
        }
        _patientId ??= patients.first['patient_id']?.toString();
        final p = patients.firstWhere((x) => s(x['patient_id']) == _patientId, orElse: () => patients.first);
        final acts = d['activity_log']!
            .where((a) => s(a['patient_id']) == s(p['patient_id']) && dateOnly(a['logged_date']) == _date)
            .toList()
          ..sort((a, b) => s(b['logged_time']).compareTo(s(a['logged_time'])));
        List<Rec> ofType(String t) => acts.where((a) => s(a['activity_type']) == t).toList();

        final meds = d['medicine_master']!;
        final procs = d['procedure_master']!;
        final freqs = d['frequency_master']!;

        return ListView(physics: kScrollPhysics, padding: kPagePad, children: [
          PageHeader(eyebrow: 'Nurses App', title: 'Patient Summary & Charts', subtitle: 'Charting for ${s(p['full_name'])}'),
          // patient + date selectors
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Column(children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: s(p['patient_id']),
                  items: [
                    for (final x in patients)
                      DropdownMenuItem(value: s(x['patient_id']), child: Text('${s(x['full_name'])} · ${s(x['patient_id'])}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _patientId = v),
                ),
              ),
              const Divider(),
              Row(children: [
                IconButton(onPressed: () => _shiftDate(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(child: Center(child: Text(_date == today() ? 'Today · ${prettyDate(_date)}' : prettyDate(_date), style: const TextStyle(fontWeight: FontWeight.w600)))),
                IconButton(onPressed: _date == today() ? null : () => _shiftDate(1), icon: const Icon(Icons.chevron_right)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          Seg(options: _tabs, value: _tab, onChanged: (v) => setState(() => _tab = v)),
          const SizedBox(height: 14),
          ..._tabBody(ctx, p, acts, ofType, meds, procs, freqs),
        ]);
      },
    );
  }

  List<Widget> _tabBody(BuildContext ctx, Rec p, List<Rec> acts, List<Rec> Function(String) ofType, List<Rec> meds, List<Rec> procs, List<Rec> freqs) {
    switch (_tab) {
      case 'Vitals':
        final v = ofType('vitals');
        final pulse = v.reversed.map((a) => n(_payload(a)['pulse_bpm'])).where((x) => x > 0).toList();
        return [
          _logButton('Log vitals', Icons.monitor_heart_outlined, () => _log(
                ctx,
                type: 'vitals',
                title: 'Vital signs',
                fields: const [
                  FieldSpec('temperature_f', 'Temp (°F)', type: FT.number, halfWidth: true),
                  FieldSpec('pulse_bpm', 'Pulse (bpm)', type: FT.number, halfWidth: true),
                  FieldSpec('bp_systolic', 'BP systolic', type: FT.number, halfWidth: true),
                  FieldSpec('bp_diastolic', 'BP diastolic', type: FT.number, halfWidth: true),
                  FieldSpec('respiration', 'Respiration', type: FT.number, halfWidth: true),
                  FieldSpec('spo2_pct', 'SpO₂ %', type: FT.number, halfWidth: true),
                  FieldSpec('weight_kg', 'Weight (kg)', type: FT.number, halfWidth: true),
                  FieldSpec('cbg_rbs', 'CBG random', type: FT.number, halfWidth: true),
                  FieldSpec('cbg_fbs', 'CBG fasting', type: FT.number, halfWidth: true),
                  FieldSpec('cbg_ppbs', 'CBG post-meal', type: FT.number, halfWidth: true),
                ],
                summary: (x) => [
                  if (x['bp_systolic'] != null) 'BP ${x['bp_systolic']}/${x['bp_diastolic'] ?? '?'}',
                  if (x['pulse_bpm'] != null) 'HR ${x['pulse_bpm']}',
                  if (x['spo2_pct'] != null) 'SpO₂ ${x['spo2_pct']}%',
                  if (x['temperature_f'] != null) '${x['temperature_f']}°F',
                ].join(' · '),
                detailTable: 'activity_vitals',
                detailBody: (x) => {...x},
              )),
          if (pulse.length >= 2) ...[
            const SectionLabel('Pulse trend'),
            AppCard(child: SizedBox(height: 70, child: CustomPaint(painter: _SparkPainter(pulse), size: Size.infinite))),
          ],
          ..._entries(v, (a) {
            final x = _payload(a);
            return [
              _chip('BP', x['bp_systolic'] == null ? '—' : '${x['bp_systolic']}/${x['bp_diastolic'] ?? '?'}'),
              _chip('HR', '${x['pulse_bpm'] ?? '—'}'),
              _chip('SpO₂', x['spo2_pct'] == null ? '—' : '${x['spo2_pct']}%'),
              _chip('Temp', x['temperature_f'] == null ? '—' : '${x['temperature_f']}°F'),
            ];
          }),
        ];
      case 'Medication':
        final m = ofType('med');
        return [
          _logButton('Log medication', Icons.medication_outlined, () => _log(
                ctx,
                type: 'med',
                title: 'Medication',
                fields: [
                  FieldSpec('medicine_name', 'Medicine', type: FT.select, required: true, options: [for (final x in meds) Opt(s(x['medicine_name']), s(x['medicine_name']))]),
                  const FieldSpec('dosage', 'Dosage', hint: 'e.g. 5 mg', halfWidth: true),
                  FieldSpec('route', 'Route', type: FT.select, options: opts(['Oral', 'IV', 'IM', 'SC', 'Topical', 'Inhalation']), halfWidth: true),
                  FieldSpec('frequency', 'Frequency', type: FT.select, options: [for (final x in freqs) Opt(s(x['frequency_code']), s(x['frequency_code']))]),
                  FieldSpec('action', 'Action', type: FT.select, required: true, options: opts(['Given', 'Refused', 'Held'])),
                ],
                summary: (x) => '${s(x['medicine_name'])} ${s(x['dosage'])} · ${s(x['action'])}',
                detailTable: 'activity_medication',
                detailBody: (x) => {...x},
                initial: const {'action': 'Given', 'route': 'Oral'},
              )),
          ..._entries(m, (a) {
            final x = _payload(a);
            return [Tag(s(x['action'], 'Given'), tone: s(x['action']) == 'Given' ? Tone.green : Tone.amber), if (s(x['route']).isNotEmpty) Tag(s(x['route']), tone: Tone.grey)];
          }),
        ];
      case 'Intake / Output':
        final io = ofType('io');
        double sumDir(String dir) => io.where((a) => s(_payload(a)['direction']) == dir).fold<double>(0, (t, a) => t + n(_payload(a)['amount_ml']));
        return [
          _logButton('Log intake / output', Icons.water_drop_outlined, () => _log(
                ctx,
                type: 'io',
                title: 'Intake / Output',
                fields: [
                  FieldSpec('direction', 'Type', type: FT.select, required: true, options: opts(['Intake', 'Output'])),
                  FieldSpec('route', 'Route', type: FT.select, options: opts(['Oral', 'NG Tube', 'IV', 'Urine', 'Catheter', 'Stool', 'Vomit'])),
                  const FieldSpec('amount_ml', 'Amount (ml)', type: FT.number),
                  FieldSpec('stool', 'Stool', type: FT.select, options: opts(['None', 'Normal', 'Loose', 'Constipated'])),
                  FieldSpec('vomiting', 'Vomiting', type: FT.select, options: opts(['No', 'Yes'])),
                  FieldSpec('aspiration', 'Aspiration', type: FT.select, options: opts(['No', 'Yes'])),
                ],
                summary: (x) => '${s(x['direction'])} ${x['amount_ml'] ?? ''} ml ${s(x['route'])}'.trim(),
                detailTable: 'activity_intake_output',
                detailBody: (x) => {...x},
                initial: const {'direction': 'Intake'},
              )),
          const SizedBox(height: 12),
          TwoUp([
            Kpi(label: 'Intake', value: '${sumDir('Intake').round()} ml', icon: Icons.arrow_downward, tone: Tone.blue),
            Kpi(label: 'Output', value: '${sumDir('Output').round()} ml', icon: Icons.arrow_upward, tone: Tone.amber),
          ]),
          ..._entries(io, (a) => [Tag(s(_payload(a)['direction']), tone: s(_payload(a)['direction']) == 'Intake' ? Tone.blue : Tone.amber)]),
        ];
      case 'Procedure':
        final pr = ofType('proc');
        return [
          _logButton('Log procedure', Icons.healing_outlined, () => _log(
                ctx,
                type: 'proc',
                title: 'Procedure',
                fields: [
                  FieldSpec('procedure_name', 'Procedure', type: FT.select, required: true, options: [for (final x in procs) Opt(s(x['procedure_name']), s(x['procedure_name']))]),
                  FieldSpec('secretion', 'Secretion', type: FT.select, options: opts(['None', 'Clear', 'White', 'Yellow', 'Blood-stained'])),
                  FieldSpec('oxygen_connected', 'Oxygen connected', type: FT.select, options: opts(['No', 'Yes'])),
                  const FieldSpec('notes', 'Notes', type: FT.multiline),
                ],
                summary: (x) => s(x['procedure_name']),
                detailTable: 'activity_procedure',
                detailBody: (x) => {...x},
              )),
          ..._entries(pr, (a) => [if (s(_payload(a)['notes']).isNotEmpty) Text(s(_payload(a)['notes']), style: const TextStyle(fontSize: 12.5, color: C.ink2))]),
        ];
      case 'General care':
        final care = ofType('care');
        return [
          _logButton('Log general care', Icons.volunteer_activism_outlined, () => _log(
                ctx,
                type: 'care',
                title: 'General care',
                fields: [
                  FieldSpec('care_type', 'Activity', type: FT.select, required: true, options: opts(['Position change', 'Bath / hygiene', 'Meal assisted', 'Mobility / transfer', 'Skin care', 'Physiotherapy', 'Note'])),
                  const FieldSpec('note', 'Details', type: FT.multiline),
                ],
                summary: (x) => '${s(x['care_type'])}${s(x['note']).isEmpty ? '' : ' — ${s(x['note'])}'}',
              )),
          ..._entries(care, (a) => const []),
        ];
      case 'Report':
        return [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Shift report', style: serif(18)),
              const SizedBox(height: 6),
              Text('${acts.length} entries logged on ${prettyDate(_date)} for ${s(p['full_name'])}.', style: const TextStyle(color: C.ink2)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: acts.isEmpty ? null : () => _submitReport(ctx, acts),
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Submit shift report'),
              ),
            ]),
          ),
          const SectionLabel('Timeline'),
          ..._entries(acts, (a) => [Tag(s(a['activity_type']), tone: Tone.navy)]),
        ];
      default: // Summary
        final cnt = (String t) => ofType(t).length;
        return [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Avatar(s(p['full_name']), size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s(p['full_name']), style: serif(19)),
                    Text([if (s(p['age']).isNotEmpty) s(p['age']), s(p['sex']), s(p['patient_id']), s(p['locality'])].where((x) => x.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 12.5, color: C.ink3)),
                  ]),
                ),
                if (s(p['care_level']).isNotEmpty) Tag(s(p['care_level']), tone: Tone.navy),
              ]),
              const SectionLabel('Diagnosis & flags'),
              InfoRow('Diagnosis', s(p['diagnosis'])),
              InfoRow('Allergy', '', valueWidget: Text(s(p['allergy'], '—'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: s(p['allergy']).isEmpty ? C.ink : C.red))),
              InfoRow('Fluid restriction', '', valueWidget: s(p['fluid_restriction']).isEmpty ? const Text('—') : Tag(s(p['fluid_restriction']), tone: Tone.amber)),
              InfoRow('Salt restriction', '', valueWidget: s(p['salt_restriction']).isEmpty ? const Text('—') : Tag(s(p['salt_restriction']), tone: Tone.amber)),
              InfoRow('Fall risk', '', valueWidget: s(p['fall_risk']).isEmpty ? const Text('—') : Tag(s(p['fall_risk']), tone: s(p['fall_risk']) == 'High' ? Tone.red : Tone.amber)),
              InfoRow('Attending doctor', s(p['attending_doctor'])),
            ]),
          ),
          const SectionLabel('This shift at a glance'),
          TwoUp([
            Kpi(label: 'Vitals logged', value: '${cnt('vitals')}', icon: Icons.monitor_heart_outlined, tone: Tone.green),
            Kpi(label: 'Meds given', value: '${ofType('med').where((a) => s(_payload(a)['action']) == 'Given').length}', icon: Icons.medication_outlined, tone: Tone.navy),
            Kpi(label: 'Intake / output', value: '${cnt('io')}', icon: Icons.water_drop_outlined, tone: Tone.blue),
            Kpi(label: 'Procedures', value: '${cnt('proc')}', icon: Icons.healing_outlined, tone: Tone.amber),
          ]),
          const SectionLabel('Recent activity'),
          ..._entries(acts.take(6).toList(), (a) => [Tag(s(a['activity_type']), tone: Tone.navy)]),
        ];
    }
  }

  Widget _logButton(String label, IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 19), label: Text(label)),
      );

  Widget _chip(String k, String v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.line)),
        child: Text('$k $v', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.ink2)),
      );

  List<Widget> _entries(List<Rec> list, List<Widget> Function(Rec) extra) {
    if (list.isEmpty) return [const EmptyState('Nothing logged for this date.', icon: Icons.edit_note)];
    return [
      for (final a in list)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(s(a['logged_time'], '--:--'), style: const TextStyle(fontWeight: FontWeight.w700, color: C.navy)),
                const SizedBox(width: 10),
                Expanded(child: Text(s(a['title']), style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
              if (s(a['detail']).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(s(a['detail']), style: const TextStyle(fontSize: 13, color: C.ink2)),
              ],
              Builder(builder: (_) {
                final ex = extra(a);
                if (ex.isEmpty) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, runSpacing: 6, children: ex));
              }),
            ]),
          ),
        ),
    ];
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v);
  final List<double> v;
  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final mn = v.reduce((a, b) => a < b ? a : b);
    final mx = v.reduce((a, b) => a > b ? a : b);
    final span = (mx - mn) == 0 ? 1.0 : (mx - mn);
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height - 8 - (size.height - 16) * ((v[i] - mn) / span);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = C.green..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeJoin = StrokeJoin.round);
    final dot = Paint()..color = C.greenDk;
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height - 8 - (size.height - 16) * ((v[i] - mn) / span);
      canvas.drawCircle(Offset(x, y), 3.2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.v != v;
}
