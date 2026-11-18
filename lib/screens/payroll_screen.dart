import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../widgets/ui.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  late String _period = DateFormat('yyyy-MM').format(DateTime.now());
  String _q = '';
  bool _running = false;
  Future<void> Function()? _doReload;

  List<String> get _periods {
    final now = DateTime.now();
    return [for (var i = 0; i < 6; i++) DateFormat('yyyy-MM').format(DateTime(now.year, now.month - i, 1))];
  }

  Future<void> _run(BuildContext ctx) async {
    final ok = await confirmDialog(
      ctx,
      title: 'Run payroll for $_period?',
      text: 'The server computes pay from attendance, duty roster and approved leave for all active nurses. Existing draft rows for this period are recalculated.',
      action: 'Run payroll',
    );
    if (!ok || !ctx.mounted) return;
    setState(() => _running = true);
    try {
      await ctx.read<ApiClient>().post('/payroll/run', {'payPeriod': _period});
      await _doReload?.call();
      if (ctx.mounted) toast(ctx, 'Payroll calculated for $_period');
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _setStatus(BuildContext ctx, Rec p, String status) async {
    try {
      await ctx.read<Repo>().update('payroll', s(p['payroll_id']), {
        'status': status,
        if (status != 'Draft') 'processed_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _doReload?.call();
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DataView(
      tables: const ['payroll', 'nurse_master'],
      builder: (ctx, d, reload) {
        _doReload = reload;
        final nById = indexBy(d['nurse_master']!, 'nurse_id');
        final rows = d['payroll']!.where((p) {
          if (s(p['pay_period']) != _period) return false;
          if (_q.isNotEmpty) {
            final q = _q.toLowerCase();
            return s(nById[s(p['nurse_id'])]?['full_name']).toLowerCase().contains(q) || s(p['nurse_id']).toLowerCase().contains(q);
          }
          return true;
        }).toList()
          ..sort((a, b) => s(a['nurse_id']).compareTo(s(b['nurse_id'])));

        final total = rows.fold<double>(0, (t, p) => t + n(p['net_salary']));
        final ded = rows.fold<double>(0, (t, p) => t + n(p['deductions']));
        final avg = rows.isEmpty ? 0.0 : total / rows.length;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _running ? null : () => _run(ctx),
            backgroundColor: C.green,
            foregroundColor: Colors.white,
            icon: _running
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow_rounded),
            label: Text('Run payroll', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          body: ListView(physics: kScrollPhysics, padding: kPagePad, children: [
            PageHeader(eyebrow: 'Finance', title: 'Nurse Payroll', subtitle: 'Verified shift-pay model · $_period'),
            Seg(options: _periods, value: _period, onChanged: (v) => setState(() => _period = v)),
            const SizedBox(height: 14),
            TwoUp([
              Kpi(label: 'Total payout', value: inr(total), icon: Icons.payments_outlined, tone: Tone.green),
              Kpi(label: 'Nurses paid', value: '${rows.length}', icon: Icons.groups_outlined, tone: Tone.navy),
              Kpi(label: 'Avg. net salary', value: inr(avg), icon: Icons.balance_outlined, tone: Tone.blue),
              Kpi(label: 'Total deductions', value: inr(ded), icon: Icons.remove_circle_outline, tone: Tone.red, valueColor: C.red),
            ]),
            const SizedBox(height: 16),
            SearchBox(hint: 'Search nurse by name or ID', onChanged: (v) => setState(() => _q = v)),
            const SizedBox(height: 14),
            if (rows.isEmpty) EmptyState('No payroll for $_period yet. Tap “Run payroll”.', icon: Icons.payments_outlined),
            for (final p in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Avatar(s(nById[s(p['nurse_id'])]?['full_name'], s(p['nurse_id'])), tone: Tone.navy),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s(nById[s(p['nurse_id'])]?['full_name'], s(p['nurse_id'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${s(p['nurse_id'])} · ${s(nById[s(p['nurse_id'])]?['role'])}', style: const TextStyle(fontSize: 12.5, color: C.ink3)),
                        ]),
                      ),
                      Tag(s(p['status'], 'Draft'), tone: toneFor(s(p['status'])), dot: true),
                    ]),
                    const SizedBox(height: 10),
                    const Divider(),
                    InfoRow('Shifts worked', s(p['shifts_worked'], '0')),
                    InfoRow('Basic', inr(p['basic'])),
                    if (n(p['allowances']) > 0) InfoRow('Allowances', inr(p['allowances'])),
                    if (n(p['lop_days']) > 0) InfoRow('LOP days', s(p['lop_days'])),
                    InfoRow('Deductions', '− ${inr(p['deductions'])}'),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Net salary', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(inr(p['net_salary']), style: serif(20, color: C.greenDk)),
                      ]),
                    ),
                    if (s(p['status']) != 'Paid') ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        if (s(p['status']) == 'Draft')
                          Expanded(child: OutlinedButton(onPressed: () => _setStatus(ctx, p, 'Processed'), child: const Text('Mark processed')))
                        else
                          Expanded(child: OutlinedButton(onPressed: () => _setStatus(ctx, p, 'Draft'), child: const Text('Back to draft'))),
                        const SizedBox(width: 10),
                        Expanded(child: FilledButton(onPressed: () => _setStatus(ctx, p, 'Paid'), child: const Text('Mark paid'))),
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
