import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/ui.dart';

const kEnquiryStages = ['New', 'Contacted', 'Visit scheduled', 'Awaiting consent', 'Converted'];

class EnquiriesScreen extends StatefulWidget {
  const EnquiriesScreen({super.key});
  @override
  State<EnquiriesScreen> createState() => _EnquiriesScreenState();
}

class _EnquiriesScreenState extends State<EnquiriesScreen> {
  String _filter = 'All';
  String _q = '';
  Future<void> Function()? _doReload;

  List<FieldSpec> get _fields => [
        const FieldSpec('stage', 'Enquiry stage', type: FT.select, options: [
          Opt('New', 'New'),
          Opt('Contacted', 'Contacted'),
          Opt('Visit scheduled', 'Visit scheduled'),
          Opt('Awaiting consent', 'Awaiting consent'),
          Opt('Converted', 'Converted (placed)'),
        ]),
        const FieldSpec('patient_name', 'Patient name', required: true, section: 'Patient'),
        const FieldSpec('age', 'Age', type: FT.number, halfWidth: true),
        FieldSpec('sex', 'Sex', type: FT.select, options: opts(['Female', 'Male', 'Other']), halfWidth: true),
        const FieldSpec('address', 'Address', type: FT.multiline),
        const FieldSpec('contact_name', 'Contact person', section: 'Enquirer'),
        FieldSpec('relationship', 'Relationship', type: FT.select, options: opts(['Son', 'Daughter', 'Spouse', 'Relative', 'Other'])),
        const FieldSpec('contact_phone', 'Phone', type: FT.phone),
        const FieldSpec('contact_email', 'Email', type: FT.email),
        FieldSpec('service_type', 'Service needed', type: FT.select, options: opts(['Attendant', 'Nurse']), section: 'Requirement'),
        FieldSpec('shift_requirement', 'Shift', type: FT.select, options: opts(['24 Hours', 'Day Shift', 'Night Shift'])),
        FieldSpec('gender_preference', 'Caregiver gender preference', type: FT.select, options: opts(['Female', 'Male', 'No preference'])),
        const FieldSpec('requirement_notes', 'Requirement notes', type: FT.multiline),
        FieldSpec('heard_source', 'How did they hear about us?', type: FT.select, options: opts(['Doctor', 'Existing Client', 'Website / Google', 'Other']), section: 'Source & visit'),
        const FieldSpec('initial_visit_date', 'Initial visit date', type: FT.date),
      ];

  Future<void> _edit(BuildContext ctx, Rec? e) async {
    final repo = ctx.read<Repo>();
    final isEdit = e != null;
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Client journey',
      title: isEdit ? 'Edit enquiry' : 'New enquiry',
      subtitle: isEdit ? s(e!['enquiry_id']) : 'Capture the first call',
      fields: _fields,
      initial: e ?? const {'stage': 'New'},
      saveLabel: isEdit ? 'Save changes' : 'Save enquiry',
      onSave: (v) async {
        final stage = s(v['stage'], 'New');
        final body = <String, dynamic>{...v, 'stage': stage, 'placed': stage == 'Converted'};
        if (isEdit) {
          await repo.update('enquiry', s(e!['enquiry_id']), body);
        } else {
          await repo.create('enquiry', {
            ...body,
            'enquiry_id': Repo.newId('ENQ'),
            'enquiry_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      },
    );
    if (ok) await _doReload?.call();
  }

  Future<void> _delete(BuildContext ctx, Rec e) async {
    if (!await confirmDialog(ctx, text: 'The enquiry for ${s(e['patient_name'], 'this patient')} will be removed.')) return;
    try {
      await ctx.read<Repo>().remove('enquiry', s(e['enquiry_id']));
      await _doReload?.call();
    } catch (err) {
      if (ctx.mounted) toast(ctx, errText(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: addFab('New enquiry', () => _edit(context, null)),
      body: DataView(
        tables: const ['enquiry'],
        builder: (ctx, d, reload) {
          _doReload = reload;
          final all = d['enquiry']!;
          final rows = all.where((r) {
            if (_filter != 'All' && s(r['stage']) != _filter) return false;
            if (_q.isNotEmpty) {
              final q = _q.toLowerCase();
              return s(r['patient_name']).toLowerCase().contains(q) ||
                  s(r['contact_name']).toLowerCase().contains(q) ||
                  s(r['contact_phone']).contains(q);
            }
            return true;
          }).toList()
            ..sort((a, b) => s(b['enquiry_at']).compareTo(s(a['enquiry_at'])));

          return ListView(physics: kScrollPhysics, padding: kPagePad, children: [
            PageHeader(eyebrow: 'Client Journey', title: 'Enquiries', subtitle: '${all.length} enquiries · first call to placement'),
            SearchBox(hint: 'Search patient, contact or phone', onChanged: (v) => setState(() => _q = v)),
            const SizedBox(height: 10),
            Seg(options: ['All', ...kEnquiryStages], value: _filter, onChanged: (v) => setState(() => _filter = v)),
            const SizedBox(height: 14),
            if (rows.isEmpty) const EmptyState('No enquiries match.', icon: Icons.chat_bubble_outline),
            for (final e in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => _edit(ctx, e),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Avatar(s(e['patient_name']), tone: Tone.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s(e['patient_name'], '—'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          Text(
                            [s(e['age']).isEmpty ? '' : '${s(e['age'])} yrs', s(e['sex'])].where((x) => x.isNotEmpty).join(' · '),
                            style: const TextStyle(fontSize: 12.5, color: C.ink3),
                          ),
                        ]),
                      ),
                      Tag(s(e['stage'], 'New'), tone: toneFor(s(e['stage'])), dot: true),
                      RowActions(onEdit: () => _edit(ctx, e), onDelete: () => _delete(ctx, e)),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (s(e['service_type']).isNotEmpty || s(e['service_requested']).isNotEmpty)
                        Tag(s(e['service_type'], s(e['service_requested'])), tone: Tone.navy),
                      if (s(e['shift_requirement']).isNotEmpty) Tag(s(e['shift_requirement']), tone: Tone.blue),
                      if (s(e['heard_source']).isNotEmpty) Tag(s(e['heard_source']), tone: Tone.grey),
                    ]),
                    if (s(e['contact_name']).isNotEmpty || s(e['contact_phone']).isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        [s(e['contact_name']), s(e['relationship']).isEmpty ? '' : '(${s(e['relationship'])})', s(e['contact_phone'])]
                            .where((x) => x.isNotEmpty)
                            .join(' '),
                        style: const TextStyle(fontSize: 12.5, color: C.ink2),
                      ),
                    ],
                    if (e['enquiry_at'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Received ${prettyDateTime(e['enquiry_at'])}', style: const TextStyle(fontSize: 11.5, color: C.ink3)),
                      ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
