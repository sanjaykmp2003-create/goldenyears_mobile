import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/ui.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _filter = 'All';
  String _q = '';
  Future<void> Function()? _doReload;

  static const _clientKeys = [
    'account_holder_name', 'relationship_to_patient', 'phone', 'email', 'address', 'billing_type', 'status',
    'caretaker_type', 'caretaker_name', 'caretaker_phone',
  ];
  static const _patientKeys = [
    'full_name', 'age', 'sex', 'diagnosis', 'care_level', 'allergy', 'attending_doctor',
    'fluid_restriction', 'salt_restriction', 'fall_risk',
  ];

  List<FieldSpec> get _fields => [
        const FieldSpec('account_holder_name', 'Account holder name', required: true, section: 'Client (bill payer)'),
        FieldSpec('relationship_to_patient', 'Relationship to patient', type: FT.select, options: opts(['Son', 'Daughter', 'Spouse', 'Relative', 'Self', 'Other'])),
        const FieldSpec('phone', 'Phone', type: FT.phone, required: true),
        const FieldSpec('email', 'Email', type: FT.email),
        const FieldSpec('address', 'Address', type: FT.multiline),
        FieldSpec('billing_type', 'Billing cycle', type: FT.select, options: opts(['Monthly', 'Fortnightly', 'Weekly']), halfWidth: true),
        FieldSpec('status', 'Status', type: FT.select, options: opts(['Active', 'Paused']), halfWidth: true),
        FieldSpec('caretaker_type', 'On-site caretaker', type: FT.select, options: opts(['Son', 'Daughter', 'Nurse', 'Other']), section: 'Caretaker'),
        const FieldSpec('caretaker_name', 'Caretaker name'),
        const FieldSpec('caretaker_phone', 'Caretaker phone', type: FT.phone),
        const FieldSpec('p_full_name', 'Patient name', section: 'Patient'),
        const FieldSpec('p_age', 'Age', type: FT.number, halfWidth: true),
        FieldSpec('p_sex', 'Sex', type: FT.select, options: opts(['Female', 'Male', 'Other']), halfWidth: true),
        const FieldSpec('p_diagnosis', 'Diagnosis', type: FT.multiline),
        FieldSpec('p_care_level', 'Care level', type: FT.select, options: const [
          Opt('Basic', 'Basic Care'),
          Opt('Advance', 'Advance Care'),
          Opt('Critical', 'Critical Care (ICU at home)'),
        ]),
        const FieldSpec('p_allergy', 'Allergy'),
        const FieldSpec('p_attending_doctor', 'Attending doctor'),
        const FieldSpec('p_fluid_restriction', 'Fluid restriction', hint: 'e.g. 1.5 L/day', halfWidth: true),
        const FieldSpec('p_salt_restriction', 'Salt restriction', hint: 'e.g. < 2g/day', halfWidth: true),
        FieldSpec('p_fall_risk', 'Fall risk', type: FT.select, options: opts(['Low', 'Medium', 'High'])),
      ];

  Future<void> _edit(BuildContext ctx, Rec? client, Rec? patient) async {
    final repo = ctx.read<Repo>();
    final isEdit = client != null;
    final initial = <String, dynamic>{
      'status': 'Active',
      'billing_type': 'Monthly',
      ...?client,
      if (patient != null) for (final k in _patientKeys) 'p_$k': patient[k],
    };
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Client journey',
      title: isEdit ? 'Edit client & patient' : 'New client & patient',
      subtitle: isEdit ? s(client!['client_id']) : 'One billing account, one or more patients',
      fields: _fields,
      initial: initial,
      saveLabel: isEdit ? 'Save changes' : 'Create client',
      onSave: (v) async {
        final cBody = {for (final k in _clientKeys) k: v[k]};
        final pBody = {for (final k in _patientKeys) k: v['p_$k']};
        final hasPatient = s(pBody['full_name']).isNotEmpty;
        String clientId;
        if (isEdit) {
          clientId = s(client!['client_id']);
          await repo.update('client', clientId, cBody);
        } else {
          clientId = Repo.newId('CL');
          await repo.create('client', {...cBody, 'client_id': clientId});
        }
        if (hasPatient) {
          if (patient != null) {
            await repo.update('patient', s(patient['patient_id']), pBody);
          } else {
            await repo.create('patient', {
              ...pBody,
              'patient_id': Repo.newId('PT'),
              'client_id': clientId,
              'status': 'Active',
              'address': v['address'],
            });
          }
        }
      },
    );
    if (ok) await _doReload?.call();
  }

  Future<void> _delete(BuildContext ctx, Rec c) async {
    if (!await confirmDialog(ctx, text: '${s(c['account_holder_name'], 'This client')} will be removed.')) return;
    try {
      await ctx.read<Repo>().remove('client', s(c['client_id']));
      await _doReload?.call();
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: addFab('New client', () => _edit(context, null, null)),
      body: DataView(
        tables: const ['client', 'patient'],
        builder: (ctx, d, reload) {
          _doReload = reload;
          final clients = d['client']!;
          final patients = d['patient']!;
          final byClient = <String, List<Rec>>{};
          for (final p in patients) {
            byClient.putIfAbsent(s(p['client_id']), () => []).add(p);
          }
          final rows = clients.where((c) {
            if (_filter != 'All' && s(c['status']) != _filter) return false;
            if (_q.isNotEmpty) {
              final q = _q.toLowerCase();
              final pts = byClient[s(c['client_id'])] ?? const <Rec>[];
              return s(c['account_holder_name']).toLowerCase().contains(q) ||
                  s(c['phone']).contains(q) ||
                  s(c['client_id']).toLowerCase().contains(q) ||
                  pts.any((p) => s(p['full_name']).toLowerCase().contains(q));
            }
            return true;
          }).toList();

          return ListView(physics: kScrollPhysics, padding: kPagePad, children: [
            PageHeader(eyebrow: 'Client Journey', title: 'Clients & Patients', subtitle: '${clients.length} clients · ${patients.length} patients'),
            SearchBox(hint: 'Search client, patient, phone or ID', onChanged: (v) => setState(() => _q = v)),
            const SizedBox(height: 10),
            Seg(options: const ['All', 'Active', 'Paused'], value: _filter, onChanged: (v) => setState(() => _filter = v)),
            const SizedBox(height: 14),
            if (rows.isEmpty) const EmptyState('No clients found.', icon: Icons.groups_outlined),
            for (final c in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ClientCard(
                  client: c,
                  patients: byClient[s(c['client_id'])] ?? const <Rec>[],
                  onEdit: (p) => _edit(ctx, c, p),
                  onDelete: () => _delete(ctx, c),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.patients, required this.onEdit, required this.onDelete});
  final Rec client;
  final List<Rec> patients;
  final void Function(Rec? patient) onEdit;
  final VoidCallback onDelete;

  Tone _care(String? l) => switch ((l ?? '').toLowerCase()) {
        'critical' => Tone.red,
        'advance' => Tone.navy,
        'basic' => Tone.green,
        _ => Tone.grey,
      };

  @override
  Widget build(BuildContext context) {
    final p = patients.isNotEmpty ? patients.first : null;
    return AppCard(
      onTap: () => onEdit(p),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(s(client['account_holder_name']), tone: Tone.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s(client['account_holder_name'], '—'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text('${s(client['client_id'])}${s(client['phone']).isEmpty ? '' : ' · ${s(client['phone'])}'}',
                  style: const TextStyle(fontSize: 12.5, color: C.ink3)),
            ]),
          ),
          Tag(s(client['status'], 'Active'), tone: toneFor(s(client['status'])), dot: true),
          RowActions(onEdit: () => onEdit(p), onDelete: onDelete),
        ]),
        if (patients.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(),
          for (final pt in patients)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Avatar(s(pt['full_name']), size: 30, tone: Tone.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s(pt['full_name'], '—'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    Text(
                      [if (s(pt['age']).isNotEmpty) '${s(pt['age'])} yrs', s(pt['sex']), s(pt['diagnosis'])].where((x) => x.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: C.ink3),
                    ),
                  ]),
                ),
                if (s(pt['care_level']).isNotEmpty) Tag(s(pt['care_level']), tone: _care(s(pt['care_level']))),
              ]),
            ),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('No patient added yet — tap to add.', style: TextStyle(fontSize: 12.5, color: C.ink3)),
          ),
      ]),
    );
  }
}
