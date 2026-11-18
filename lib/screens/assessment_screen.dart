import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/ui.dart';

class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({super.key});
  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  String _filter = 'All';
  String _q = '';
  Future<void> Function()? _doReload;

  List<FieldSpec> _fields(List<Rec> patients) => [
        FieldSpec(
          'patient_id',
          'Patient',
          type: FT.select,
          required: true,
          section: 'A. Demographics',
          options: [for (final p in patients) Opt(s(p['patient_id']), s(p['full_name'], s(p['patient_id'])))],
        ),
        const FieldSpec('location_address', 'Care location / address', type: FT.multiline),
        const FieldSpec('bus_facility', 'Bus / transport access'),
        const FieldSpec('nearby_hotels', 'Nearby hotels / food'),
        const FieldSpec('attending_doctor', 'Attending doctor'),
        const FieldSpec('medical_history', 'Medical history', type: FT.multiline, section: 'B. Medical information'),
        const FieldSpec('current_medication', 'Current medication', type: FT.multiline),
        const FieldSpec('allergies', 'Allergies'),
        FieldSpec('mobility', 'Mobility', type: FT.select, options: opts(['Independent', 'Walker', 'Stick', 'Bed Bound']), section: 'C–F. Functional assessment'),
        FieldSpec('feeding', 'Feeding', type: FT.select, options: opts(['Independent', 'Needs Help', 'NG Tube Fed'])),
        FieldSpec('continence', 'Continence', type: FT.select, options: opts(['Continent', 'Diaper', 'Catheterized'])),
        FieldSpec('medication_assistance', 'Medication assistance', type: FT.select, options: opts(['Self', 'Needs Help'])),
        FieldSpec('care_plan_care_required', 'Care required', type: FT.select, options: const [
          Opt('Attendant', 'Attendant (General Caregiver)'),
          Opt('Nurse', 'Nurse (GNM / BSc Professional)'),
        ], section: 'G. Care plan'),
        FieldSpec('care_plan_duration', 'Duration / service type', type: FT.select, options: const [
          Opt('24 Hours', '24 Hours (Full-Time / Live-in)'),
          Opt('12 Hours', '12 Hours (Half-Day)'),
          Opt('Visit based', 'Visit based'),
        ]),
        FieldSpec('care_plan_shift', 'Shift', type: FT.select, options: const [
          Opt('Day Shift', 'Day Shift (08:00 – 20:00)'),
          Opt('Night Shift', 'Night Shift (20:00 – 08:00)'),
          Opt('24 Hours', '24 Hours (Continuous)'),
        ]),
        FieldSpec('care_plan_gender_pref', 'Gender preference', type: FT.select, options: opts(['Female', 'Male'])),
        const FieldSpec('tariff_per_day', 'Tariff per day (₹)', type: FT.number),
        FieldSpec('status', 'Status', type: FT.select, options: const [
          Opt('Approved', 'Approved & ready for duty roster'),
          Opt('Draft', 'Draft'),
        ]),
      ];

  Future<void> _edit(BuildContext ctx, Rec? a, List<Rec> patients) async {
    final repo = ctx.read<Repo>();
    final isEdit = a != null;
    final byPatient = indexBy(patients, 'patient_id');
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Patient assessment',
      title: isEdit ? 'Edit assessment' : 'New assessment',
      subtitle: isEdit ? s(a!['assessment_id']) : 'Home assessment & care plan',
      fields: _fields(patients),
      initial: a ?? const {'status': 'Approved', 'tariff_per_day': 1800, 'care_plan_care_required': 'Nurse', 'care_plan_duration': '24 Hours'},
      saveLabel: isEdit ? 'Save changes' : 'Save assessment',
      onSave: (v) async {
        final p = byPatient[s(v['patient_id'])];
        final body = <String, dynamic>{
          ...v,
          'patient_name': s(p?['full_name']),
          'allergies': v['allergies'] ?? p?['allergy'],
        };
        if (isEdit) {
          await repo.update('assessment', s(a!['assessment_id']), body);
        } else {
          await repo.create('assessment', {
            ...body,
            'assessment_id': Repo.newId('ASM'),
            'assessed_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      },
    );
    if (ok) await _doReload?.call();
  }

  Future<void> _delete(BuildContext ctx, Rec a) async {
    if (!await confirmDialog(ctx, text: 'Assessment ${s(a['assessment_id'])} will be removed.')) return;
    try {
      await ctx.read<Repo>().remove('assessment', s(a['assessment_id']));
      await _doReload?.call();
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DataView(
      tables: const ['assessment', 'patient'],
      builder: (ctx, d, reload) {
        _doReload = reload;
        final all = d['assessment']!;
        final patients = d['patient']!;
        final rows = all.where((r) {
          if (_filter != 'All' && s(r['status']) != _filter) return false;
          if (_q.isNotEmpty) {
            final q = _q.toLowerCase();
            return s(r['patient_name']).toLowerCase().contains(q) || s(r['assessment_id']).toLowerCase().contains(q);
          }
          return true;
        }).toList()
          ..sort((a, b) => s(b['assessed_at']).compareTo(s(a['assessed_at'])));

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: addFab('New assessment', () => _edit(ctx, null, patients)),
          body: ListView(physics: kScrollPhysics, padding: kPagePad, children: [
            PageHeader(eyebrow: 'Client Journey', title: 'Patient Assessment', subtitle: '${all.length} assessments recorded'),
            SearchBox(hint: 'Search patient or assessment ID', onChanged: (v) => setState(() => _q = v)),
            const SizedBox(height: 10),
            Seg(options: const ['All', 'Approved', 'Draft'], value: _filter, onChanged: (v) => setState(() => _filter = v)),
            const SizedBox(height: 14),
            if (rows.isEmpty) const EmptyState('No assessments yet.', icon: Icons.fact_check_outlined),
            for (final a in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => _edit(ctx, a, patients),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Avatar(s(a['patient_name']), tone: Tone.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s(a['patient_name'], '—'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          Text('${s(a['assessment_id'])} · ${prettyDate(a['assessed_at'])}', style: const TextStyle(fontSize: 12.5, color: C.ink3)),
                        ]),
                      ),
                      Tag(s(a['status'], 'Draft'), tone: s(a['status']) == 'Approved' ? Tone.green : Tone.amber, dot: true),
                      RowActions(onEdit: () => _edit(ctx, a, patients), onDelete: () => _delete(ctx, a)),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (s(a['mobility']).isNotEmpty) Tag(s(a['mobility']), tone: Tone.navy),
                      if (s(a['feeding']).isNotEmpty) Tag(s(a['feeding']), tone: Tone.blue),
                      if (s(a['care_plan_care_required']).isNotEmpty) Tag(s(a['care_plan_care_required']), tone: Tone.purple),
                      if (s(a['care_plan_shift']).isNotEmpty) Tag(s(a['care_plan_shift']), tone: Tone.grey),
                    ]),
                    if (n(a['tariff_per_day']) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('Tariff ${inr(a['tariff_per_day'])} / day', style: const TextStyle(fontSize: 12.5, color: C.ink2, fontWeight: FontWeight.w600)),
                      ),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}
