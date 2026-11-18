import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../widgets/form_sheet.dart';
import '../widgets/ui.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  String _status = 'All';
  String _q = '';
  Future<void> Function()? _doReload;

  List<Opt> _clientOpts(List<Rec> clients) =>
      [for (final c in clients) Opt(s(c['client_id']), '${s(c['account_holder_name'])} (${s(c['client_id'])})')];

  // ---- manual invoice (same fields as the web invoice drawer) -------------
  Future<void> _manual(BuildContext ctx, Rec? inv, List<Rec> clients) async {
    final repo = ctx.read<Repo>();
    final isEdit = inv != null;
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Finance',
      title: isEdit ? 'Edit invoice' : 'New invoice',
      subtitle: isEdit ? s(inv!['invoice_id']) : 'Enter the invoice total manually',
      fields: [
        FieldSpec('client_id', 'Client', type: FT.select, required: true, options: _clientOpts(clients)),
        const FieldSpec('billing_period', 'Billing period', required: true, hint: 'e.g. June 2026'),
        FieldSpec('billing_type', 'Billing type', type: FT.select, options: opts(['Monthly', 'Fortnightly', 'Weekly', 'Advance']), halfWidth: true),
        FieldSpec('status', 'Status', type: FT.select, options: opts(['Pending', 'Due', 'Paid', 'Overdue', 'Draft']), halfWidth: true),
        const FieldSpec('subtotal', 'Subtotal (₹)', type: FT.number, halfWidth: true),
        const FieldSpec('discount', 'Discount (₹)', type: FT.number, halfWidth: true),
        const FieldSpec('total_amount', 'Total amount (₹)', type: FT.number, required: true),
        const FieldSpec('due_date', 'Due date', type: FT.date),
      ],
      initial: inv ?? const {'status': 'Pending', 'billing_type': 'Monthly'},
      saveLabel: isEdit ? 'Save changes' : 'Create invoice',
      onSave: (v) async {
        if (isEdit) {
          await repo.update('invoice', s(inv!['invoice_id']), v);
        } else {
          await repo.create('invoice', {
            ...v,
            'invoice_id': Repo.newId('INV'),
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      },
    );
    if (ok) await _doReload?.call();
  }

  // ---- server-side generation (POST /api/billing/invoices, rules R9.1-R9.5)
  Future<void> _generate(BuildContext ctx, List<Rec> clients, List<Rec> patients) async {
    final api = ctx.read<ApiClient>();
    final ok = await showFormSheet(
      ctx,
      eyebrow: 'Finance',
      title: 'Generate from attendance',
      subtitle: 'The server totals shifts served × contract tariff',
      fields: [
        FieldSpec('clientId', 'Client', type: FT.select, required: true, options: _clientOpts(clients)),
        FieldSpec('patientId', 'Patient (optional)', type: FT.select, options: [
          for (final p in patients) Opt(s(p['patient_id']), s(p['full_name'], s(p['patient_id']))),
        ]),
        const FieldSpec('billingPeriod', 'Billing period', required: true, hint: 'e.g. June 2026'),
        const FieldSpec('fromDate', 'From', type: FT.date, required: true, halfWidth: true),
        const FieldSpec('toDate', 'To', type: FT.date, required: true, halfWidth: true),
        FieldSpec('billingType', 'Billing type', type: FT.select, options: opts(['Monthly', 'Advance'])),
        const FieldSpec('items', 'Consumables (₹)', type: FT.number, section: 'Extras', halfWidth: true),
        const FieldSpec('conveyance', 'Conveyance (₹)', type: FT.number, halfWidth: true),
        const FieldSpec('additional', 'Additional (₹)', type: FT.number, halfWidth: true),
        const FieldSpec('discount', 'Discount (₹)', type: FT.number, halfWidth: true),
      ],
      initial: const {'billingType': 'Monthly'},
      saveLabel: 'Generate invoice',
      onSave: (v) async {
        await api.post('/billing/invoices', {
          'clientId': v['clientId'],
          if (v['patientId'] != null) 'patientId': v['patientId'],
          'billingPeriod': v['billingPeriod'],
          'fromDate': v['fromDate'],
          'toDate': v['toDate'],
          'billingType': v['billingType'] ?? 'Monthly',
          'extras': {
            if (v['items'] != null) 'items': v['items'],
            if (v['conveyance'] != null) 'conveyance': v['conveyance'],
            if (v['additional'] != null) 'additional': v['additional'],
            if (v['discount'] != null) 'discount': v['discount'],
          },
        });
      },
    );
    if (ok) await _doReload?.call();
  }

  Future<void> _chooseCreate(BuildContext ctx, List<Rec> clients, List<Rec> patients) async {
    final pick = await showModalBottomSheet<String>(
      context: ctx,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined, color: C.greenDk),
              title: const Text('Generate from attendance', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Server calculates shifts × tariff'),
              onTap: () => Navigator.pop(c, 'gen'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note, color: C.navy),
              title: const Text('Enter manually', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Type the invoice total yourself'),
              onTap: () => Navigator.pop(c, 'man'),
            ),
          ]),
        ),
      ),
    );
    if (!ctx.mounted) return;
    if (pick == 'gen') await _generate(ctx, clients, patients);
    if (pick == 'man') await _manual(ctx, null, clients);
  }

  // ---- invoice detail + payment ------------------------------------------
  Future<void> _detail(BuildContext ctx, Rec inv, String clientName) async {
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InvoiceDetail(invoice: inv, clientName: clientName),
    );
    await _doReload?.call();
  }

  Future<void> _delete(BuildContext ctx, Rec inv) async {
    if (!await confirmDialog(ctx, text: 'Invoice ${s(inv['invoice_id'])} will be removed.')) return;
    try {
      await ctx.read<Repo>().remove('invoice', s(inv['invoice_id']));
      await _doReload?.call();
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DataView(
      tables: const ['invoice', 'client', 'patient'],
      builder: (ctx, d, reload) {
        _doReload = reload;
        final invoices = d['invoice']!;
        final clients = d['client']!;
        final patients = d['patient']!;
        final cById = indexBy(clients, 'client_id');
        final rows = invoices.where((r) {
          if (_status != 'All' && s(r['status']).toLowerCase() != _status.toLowerCase()) return false;
          if (_q.isNotEmpty) {
            final q = _q.toLowerCase();
            return s(r['invoice_id']).toLowerCase().contains(q) ||
                s(cById[s(r['client_id'])]?['account_holder_name']).toLowerCase().contains(q);
          }
          return true;
        }).toList()
          ..sort((a, b) => s(b['created_at']).compareTo(s(a['created_at'])));

        double sum(bool Function(Rec) f) => invoices.where(f).fold<double>(0, (t, r) => t + n(r['total_amount']));
        final billed = sum((_) => true);
        final paid = sum((r) => s(r['status']) == 'Paid');
        final due = sum((r) => ['Due', 'Pending', 'Overdue'].contains(s(r['status'])));

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: addFab('New invoice', () => _chooseCreate(ctx, clients, patients)),
          body: ListView(physics: kScrollPhysics, padding: kPagePad, children: [
            const PageHeader(eyebrow: 'Finance', title: 'Client Billing', subtitle: 'Itemised invoices for home care services.'),
            TwoUp([
              Kpi(label: 'Total billed', value: inr(billed), icon: Icons.receipt_long_outlined, tone: Tone.blue),
              Kpi(label: 'Collected', value: inr(paid), icon: Icons.check_circle_outline, tone: Tone.green),
              Kpi(label: 'Outstanding', value: inr(due), icon: Icons.warning_amber_rounded, tone: Tone.red, valueColor: C.red),
              Kpi(label: 'Invoices', value: '${invoices.length}', icon: Icons.numbers, tone: Tone.navy),
            ]),
            const SizedBox(height: 16),
            SearchBox(hint: 'Search invoice or client', onChanged: (v) => setState(() => _q = v)),
            const SizedBox(height: 10),
            Seg(options: const ['All', 'Paid', 'Pending', 'Due', 'Overdue', 'Draft'], value: _status, onChanged: (v) => setState(() => _status = v)),
            const SizedBox(height: 14),
            if (rows.isEmpty) const EmptyState('No invoices.', icon: Icons.receipt_long_outlined),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => _detail(ctx, r, s(cById[s(r['client_id'])]?['account_holder_name'], s(r['client_id']))),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: C.blueLt, borderRadius: BorderRadius.circular(11)),
                      child: const Icon(Icons.description_outlined, color: C.blue, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s(cById[s(r['client_id'])]?['account_holder_name'], s(r['client_id'], '—')), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${s(r['invoice_id'])} · ${s(r['billing_period'], '—')}', style: const TextStyle(fontSize: 12.5, color: C.ink3)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(inr(r['total_amount']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      const SizedBox(height: 4),
                      Tag(s(r['status'], '—'), tone: toneFor(s(r['status']))),
                    ]),
                    RowActions(onEdit: () => _manual(ctx, r, clients), onDelete: () => _delete(ctx, r)),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

/// Bottom sheet showing line items (GET /api/billing/invoices/:id) with "Record payment".
class _InvoiceDetail extends StatefulWidget {
  const _InvoiceDetail({required this.invoice, required this.clientName});
  final Rec invoice;
  final String clientName;
  @override
  State<_InvoiceDetail> createState() => _InvoiceDetailState();
}

class _InvoiceDetailState extends State<_InvoiceDetail> {
  List<Rec> _items = [];
  bool _loading = true;
  String? _error;
  late Rec _inv = widget.invoice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<ApiClient>().get('/billing/invoices/${Uri.encodeComponent(s(_inv['invoice_id']))}');
      if (!mounted) return;
      setState(() {
        _inv = Map<String, dynamic>.from(d['invoice'] as Map);
        _items = ((d['items'] ?? const []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _pay() async {
    final repo = context.read<Repo>();
    final ok = await showFormSheet(
      context,
      eyebrow: 'Finance',
      title: 'Record payment',
      subtitle: '${s(_inv['invoice_id'])} · ${widget.clientName}',
      fields: [
        const FieldSpec('amount', 'Amount received (₹)', type: FT.number, required: true),
        FieldSpec('method', 'Mode of payment', type: FT.select, required: true, options: opts(['UPI', 'Bank transfer', 'Cheque', 'Cash'])),
        const FieldSpec('reference_no', 'Reference / transaction no.'),
      ],
      initial: {'amount': _inv['total_amount'], 'method': 'UPI'},
      saveLabel: 'Record payment',
      onSave: (v) async {
        await repo.create('payment', {
          ...v,
          'payment_id': Repo.newId('PAY'),
          'invoice_id': s(_inv['invoice_id']),
          'client_id': s(_inv['client_id']),
          'paid_at': DateTime.now().toUtc().toIso8601String(),
          'status': 'Success',
        });
        if (n(v['amount']) >= n(_inv['total_amount'])) {
          await repo.update('invoice', s(_inv['invoice_id']), {'status': 'Paid'});
        }
      },
    );
    if (ok) {
      await _load();
      if (mounted) toast(context, 'Payment recorded');
    }
  }

  @override
  Widget build(BuildContext context) {
    final paid = s(_inv['status']) == 'Paid';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('INVOICE', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: C.greenDk, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(s(_inv['invoice_id']), style: serif(21)),
              Text(widget.clientName, style: const TextStyle(fontSize: 12.5, color: C.ink3)),
            ]),
          ),
          Tag(s(_inv['status'], '—'), tone: toneFor(s(_inv['status'])), dot: true),
        ]),
        const SizedBox(height: 12),
        const Divider(),
        InfoRow('Billing period', s(_inv['billing_period'])),
        InfoRow('Subtotal', inr(_inv['subtotal'])),
        if (n(_inv['discount']) > 0) InfoRow('Discount', '− ${inr(_inv['discount'])}'),
        const SizedBox(height: 6),
        const Text('LINE ITEMS', style: TextStyle(fontSize: 11, letterSpacing: 1, color: C.ink3, fontWeight: FontWeight.w600)),
        if (_loading)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: C.green)))
        else if (_error != null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: const TextStyle(color: C.redDk)))
        else if (_items.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No itemised lines on this invoice.', style: TextStyle(color: C.ink3)))
        else
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final it in _items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s(it['description']), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                        if (s(it['basis']).isNotEmpty) Text(s(it['basis']), style: const TextStyle(fontSize: 12, color: C.ink3)),
                      ]),
                    ),
                    Text(inr(it['amount']), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
            ]),
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(inr(_inv['total_amount']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: paid ? null : _pay,
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: Text(paid ? 'Paid in full' : 'Record payment'),
        ),
      ]),
    );
  }
}
