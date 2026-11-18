import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/ui.dart';

class _Master {
  final String key, label, table, pk, prefix, noun;
  final IconData icon;
  final List<FieldSpec> fields;
  final String Function(Rec) title;
  final String Function(Rec) subtitle;
  final String? Function(Rec)? tag;
  const _Master(this.key, this.label, this.table, this.pk, this.prefix, this.noun, this.icon, this.fields, this.title, this.subtitle, {this.tag});
}

final _masters = <_Master>[
  _Master('nurse', 'Nurses & staff', 'nurse_master', 'nurse_id', 'UNI-N', 'staff member', Icons.badge_outlined, [
    const FieldSpec('full_name', 'Full name', required: true),
    const FieldSpec('phone', 'Phone', type: FT.phone),
    FieldSpec('role', 'Role', type: FT.select, options: opts(['Nurse', 'Caregiver', 'Attendant', 'ICU Nurse', 'Head Nurse'])),
    FieldSpec('qualification', 'Qualification', type: FT.select, options: opts(['ANM', 'GNM', 'BSc Nursing', 'Caregiver'])),
    const FieldSpec('nursing_college', 'Nursing college'),
    const FieldSpec('rn_rm_no', 'RN / RM number'),
    const FieldSpec('date_of_joining', 'Date of joining', type: FT.date),
    const FieldSpec('per_day_salary', 'Per-day salary (₹)', type: FT.number, halfWidth: true),
    const FieldSpec('basic_salary', 'Basic salary (₹)', type: FT.number, halfWidth: true),
    FieldSpec('status', 'Status', type: FT.select, options: opts(['Active', 'Inactive'])),
    const FieldSpec('is_head_nurse', 'Head nurse (excluded from payroll run)', type: FT.toggle),
  ], (r) => s(r['full_name'], s(r['nurse_id'])), (r) => '${s(r['nurse_id'])} · ${s(r['role'])} · ${s(r['qualification'])}', tag: (r) => s(r['status'])),
  _Master('pricing', 'Pricing', 'pricing_master', 'price_code', 'PRC', 'price', Icons.sell_outlined, [
    const FieldSpec('category', 'Category', required: true),
    FieldSpec('duty_type', 'Duty type', type: FT.select, options: opts(['Attendant', 'Nurse'])),
    FieldSpec('shift_type', 'Shift', type: FT.select, options: opts(['Day Shift', 'Night Shift', '24 Hours'])),
    const FieldSpec('basis', 'Basis', hint: 'per shift / per day / per visit'),
    const FieldSpec('tariff', 'Tariff (₹)', type: FT.number, halfWidth: true),
    const FieldSpec('night_charge', 'Night charge (₹)', type: FT.number, halfWidth: true),
    const FieldSpec('cost', 'Cost (₹)', type: FT.number, halfWidth: true),
    const FieldSpec('gst_pct', 'GST %', type: FT.number, halfWidth: true),
    const FieldSpec('is_active', 'Active', type: FT.toggle),
  ], (r) => s(r['category'], s(r['price_code'])), (r) => '${s(r['duty_type'])} · ${s(r['shift_type'])} · ${inr(r['tariff'])}', tag: (r) => b(r['is_active']) ? 'Active' : 'Inactive'),
  _Master('service', 'Services', 'service_master', 'service_id', 'SVC', 'service', Icons.medical_services_outlined, [
    const FieldSpec('service_name', 'Service name', required: true),
    const FieldSpec('description', 'Description', type: FT.multiline),
    const FieldSpec('is_active', 'Active', type: FT.toggle),
  ], (r) => s(r['service_name'], s(r['service_id'])), (r) => s(r['description'], s(r['service_id'])), tag: (r) => b(r['is_active']) ? 'Active' : 'Inactive'),
  _Master('procedure', 'Procedures', 'procedure_master', 'procedure_id', 'PRO', 'procedure', Icons.healing_outlined, [
    const FieldSpec('procedure_name', 'Procedure name', required: true),
    const FieldSpec('is_active', 'Active', type: FT.toggle),
  ], (r) => s(r['procedure_name'], s(r['procedure_id'])), (r) => s(r['procedure_id']), tag: (r) => b(r['is_active']) ? 'Active' : 'Inactive'),
  _Master('medicine', 'Medicines', 'medicine_master', 'medicine_id', 'MED', 'medicine', Icons.medication_outlined, [
    const FieldSpec('medicine_name', 'Medicine name', required: true),
    const FieldSpec('is_active', 'Active', type: FT.toggle),
  ], (r) => s(r['medicine_name'], s(r['medicine_id'])), (r) => s(r['medicine_id']), tag: (r) => b(r['is_active']) ? 'Active' : 'Inactive'),
  _Master('frequency', 'Frequencies', 'frequency_master', 'frequency_id', 'FRQ', 'frequency', Icons.schedule_outlined, [
    const FieldSpec('frequency_code', 'Code', required: true, hint: 'e.g. BD, TDS'),
    const FieldSpec('description', 'Description'),
  ], (r) => s(r['frequency_code'], s(r['frequency_id'])), (r) => s(r['description'])),
  _Master('operational', 'Operational staff', 'operational_staff_master', 'person_id', 'OPS', 'person', Icons.support_agent_outlined, [
    const FieldSpec('full_name', 'Full name', required: true),
    const FieldSpec('role_desc', 'Role'),
    const FieldSpec('phone', 'Phone', type: FT.phone),
    const FieldSpec('is_active', 'Active', type: FT.toggle),
  ], (r) => s(r['full_name'], s(r['person_id'])), (r) => '${s(r['role_desc'])} · ${s(r['phone'])}', tag: (r) => b(r['is_active']) ? 'Active' : 'Inactive'),
];

class MastersScreen extends StatefulWidget {
  const MastersScreen({super.key});
  @override
  State<MastersScreen> createState() => _MastersScreenState();
}

class _MastersScreenState extends State<MastersScreen> {
  _Master _m = _masters.first;
  String _q = '';
  Future<void> Function()? _doReload;

  Future<void> _edit(BuildContext ctx, Rec? r) async {
    final repo = ctx.read<Repo>();
    final m = _m;
    final isEdit = r != null;
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Masters',
      title: isEdit ? 'Edit ${m.noun}' : 'Add ${m.noun}',
      subtitle: isEdit ? s(r![m.pk]) : null,
      fields: m.fields,
      initial: r ?? const {'is_active': true, 'status': 'Active'},
      saveLabel: isEdit ? 'Save changes' : 'Add record',
      onSave: (v) async {
        if (isEdit) {
          await repo.update(m.table, s(r![m.pk]), v);
        } else {
          await repo.create(m.table, {...v, m.pk: Repo.newId(m.prefix)});
        }
      },
    );
    if (ok) await _doReload?.call();
  }

  Future<void> _delete(BuildContext ctx, Rec r) async {
    if (!await confirmDialog(ctx, text: '${_m.title(r)} will be removed.')) return;
    try {
      await ctx.read<Repo>().remove(_m.table, s(r[_m.pk]));
      await _doReload?.call();
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return KeyedSubtree(
      key: ValueKey(m.key),
      child: DataView(
        tables: [m.table],
        builder: (ctx, d, reload) {
          _doReload = reload;
          final all = d[m.table]!;
          final rows = all.where((r) => _q.isEmpty || '${m.title(r)} ${m.subtitle(r)}'.toLowerCase().contains(_q.toLowerCase())).toList();
          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: addFab('Add record', () => _edit(ctx, null)),
            body: ListView(physics: kScrollPhysics, padding: kPagePad, children: [
              PageHeader(eyebrow: 'Configuration', title: 'Masters', subtitle: '${all.length} ${m.label.toLowerCase()}'),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _masters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final x = _masters[i];
                    final on = x.key == m.key;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _m = x;
                        _q = '';
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: on ? C.green : C.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: on ? C.green : C.line),
                        ),
                        child: Row(children: [
                          Icon(x.icon, size: 16, color: on ? Colors.white : C.ink3),
                          const SizedBox(width: 7),
                          Text(x.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: on ? Colors.white : C.ink2)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SearchBox(hint: 'Search ${m.label.toLowerCase()}', onChanged: (v) => setState(() => _q = v)),
              const SizedBox(height: 14),
              if (rows.isEmpty) EmptyState('No ${m.label.toLowerCase()} yet. Tap “Add record”.', icon: m.icon),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    onTap: () => _edit(ctx, r),
                    child: Row(children: [
                      Avatar(m.title(r), tone: Tone.navy),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.title(r), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(m.subtitle(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: C.ink3)),
                        ]),
                      ),
                      if (m.tag != null && (m.tag!(r) ?? '').isNotEmpty) Tag(m.tag!(r)!, tone: toneFor(m.tag!(r))),
                      RowActions(onEdit: () => _edit(ctx, r), onDelete: () => _delete(ctx, r)),
                    ]),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
