import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/auth.dart';
import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/theme.dart';
import '../widgets/ui.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.user});
  final UserContext user;

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  String _short(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}k';
    return inr(v);
  }

  @override
  Widget build(BuildContext context) {
    return DataView(
      tables: const ['nurse_master', 'client', 'invoice', 'leave_request', 'attendance', 'enquiry', 'duty_roster', 'assessment', 'patient'],
      builder: (ctx, d, reload) {
        try {
          final nurses = d['nurse_master'] ?? const [];
          final clients = d['client'] ?? const [];
          final invoices = d['invoice'] ?? const [];
          final leaves = d['leave_request'] ?? const [];
          final attendance = d['attendance'] ?? const [];
          final enquiries = d['enquiry'] ?? const [];
          final duties = d['duty_roster'] ?? const [];
          final assessments = d['assessment'] ?? const [];
          final patients = d['patient'] ?? const [];
          final nurseById = indexBy(nurses, 'nurse_id');
        final pending = leaves.where((l) => s(l['status']) == 'Pending').toList();
        final todayStr = today();
        final todayAtt = attendance.where((a) => dateOnly(a['shift_date']) == todayStr).toList();
        final present = todayAtt.where((a) => s(a['status']) == 'Present').length;
        final absent = todayAtt.where((a) => s(a['status']) == 'Absent').length;

        final billed = invoices.fold<double>(0, (t, r) => t + n(r['total_amount']));
        final due = invoices
            .where((r) => ['Due', 'Pending', 'Overdue'].contains(s(r['status'])))
            .fold<double>(0, (t, r) => t + n(r['total_amount']));
        final paid = invoices.where((r) => s(r['status']) == 'Paid').fold<double>(0, (t, r) => t + n(r['total_amount']));
        final activeClients = clients.where((c) => s(c['status']) == 'Active').length;
        final openEnq = enquiries.where((e) => s(e['stage']) != 'Converted' && s(e['stage']) != 'Closed').length;

        List<Widget> kpis;
        switch (user.userType) {
          case 'nurse':
            final mine = duties.where((x) => s(x['nurse_id']) == s(user.linkedId)).toList();
            final myAtt = attendance.where((x) => s(x['nurse_id']) == s(user.linkedId)).toList();
            kpis = [
              Kpi(label: 'My duties', value: '${mine.length}', icon: Icons.calendar_month_outlined, tone: Tone.green),
              Kpi(label: 'Shifts attended', value: '${myAtt.where((a) => s(a['status']) == 'Present').length}', icon: Icons.access_time, tone: Tone.navy),
              Kpi(label: 'Pending leave', value: '${pending.length}', icon: Icons.event_busy_outlined, tone: Tone.amber),
              Kpi(label: 'Today', value: todayAtt.any((a) => s(a['nurse_id']) == s(user.linkedId)) ? 'Marked' : 'Not marked', icon: Icons.today_outlined, tone: Tone.blue),
            ];
            break;
          case 'assessor':
            kpis = [
              Kpi(label: 'Open enquiries', value: '$openEnq', icon: Icons.chat_bubble_outline, tone: Tone.green),
              Kpi(label: 'Active clients', value: '$activeClients', icon: Icons.groups_outlined, tone: Tone.navy),
              Kpi(label: 'Assessments', value: '${assessments.length}', icon: Icons.fact_check_outlined, tone: Tone.blue),
              Kpi(label: 'Patients', value: '${patients.length}', icon: Icons.personal_injury_outlined, tone: Tone.purple),
            ];
            break;
          default:
            kpis = [
              Kpi(label: 'Nurses registered', value: '${nurses.length}', icon: Icons.groups_outlined, tone: Tone.green),
              Kpi(label: 'Active clients under care', value: '$activeClients', icon: Icons.favorite_border, tone: Tone.navy),
              Kpi(label: 'Total billed amount', value: _short(billed), icon: Icons.receipt_long_outlined, tone: Tone.blue),
              Kpi(label: 'Outstanding dues', value: _short(due), icon: Icons.warning_amber_rounded, tone: Tone.red, valueColor: C.red),
            ];
        }

        final canReview = user.isManagement;
        return ListView(physics: kScrollPhysics, padding: kPagePad, children: [
          PageHeader(
            eyebrow: 'Care Operations Snapshot',
            title: '${_greeting()}, ${user.userId}',
            subtitle: 'Live status from the Unicare server. Pull down to refresh.',
          ),
          TwoUp(kpis),
          if (user.isManagement) ...[
            const SectionLabel('Workforce today'),
            AppCard(
              child: Column(children: [
                InfoRow('Present', '', valueWidget: Tag('$present', tone: Tone.green, dot: true)),
                InfoRow('Absent', '', valueWidget: Tag('$absent', tone: Tone.red, dot: true)),
                InfoRow('Not yet marked', '${(nurses.length - todayAtt.length).clamp(0, 9999)}'),
              ]),
            ),
            const SectionLabel('Collections'),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: billed <= 0 ? 0 : (paid / billed).clamp(0, 1).toDouble(),
                    minHeight: 10,
                    backgroundColor: C.line,
                    color: C.green,
                  ),
                ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Collected ${inr(paid)}', style: const TextStyle(fontSize: 12.5, color: C.greenDk, fontWeight: FontWeight.w600)),
                  Text('Due ${inr(due)}', style: const TextStyle(fontSize: 12.5, color: C.red, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
          ],
          SectionLabel('Pending leave requests (${pending.length})'),
          if (pending.isEmpty)
            const AppCard(child: EmptyState('Nothing waiting for review.', icon: Icons.check_circle_outline))
          else
            ...pending.take(8).map((l) {
              final nm = s(nurseById[s(l['nurse_id'])]?['full_name'], s(l['nurse_id']));
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Avatar(nm, tone: Tone.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(nm, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${s(l['leave_type'], 'Leave')} · ${prettyDate(l['from_date'])} → ${prettyDate(l['to_date'])}',
                              style: const TextStyle(fontSize: 12.5, color: C.ink3)),
                        ]),
                      ),
                      const Tag('Pending', tone: Tone.amber),
                    ]),
                    if (canReview) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _review(ctx, l, 'Rejected', reload),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _review(ctx, l, 'Approved', reload),
                            child: const Text('Approve'),
                          ),
                        ),
                      ]),
                    ],
                  ]),
                ),
              );
            }),
          if (user.isManagement || user.userType == 'assessor') ...[
            SectionLabel('Open enquiries ($openEnq)'),
            ...enquiries
                .where((e) => s(e['stage']) != 'Converted' && s(e['stage']) != 'Closed')
                .take(5)
                .map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        child: Row(children: [
                          Avatar(s(e['patient_name']), tone: Tone.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s(e['patient_name'], '—'), style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(s(e['service_type'], s(e['service_requested'], s(e['contact_name']))),
                                  style: const TextStyle(fontSize: 12.5, color: C.ink3)),
                            ]),
                          ),
                          Tag(s(e['stage'], 'New'), tone: toneFor(s(e['stage']))),
                        ]),
                      ),
                    )),
          ],
        ]);
        } catch (err, stack) {
          debugPrint('Dashboard render error: $err\n$stack');
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.error_outline, color: C.red, size: 48),
              const SizedBox(height: 12),
              Text('Error rendering dashboard: $err',
                  style: const TextStyle(color: C.red, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Text('$stack', style: const TextStyle(fontSize: 11, color: C.ink3)),
            ],
          );
        }
      },
    );
  }

  Future<void> _review(BuildContext ctx, Rec leave, String status, Future<void> Function() reload) async {
    final repo = ctx.read<Repo>();
    try {
      await repo.update('leave_request', s(leave['leave_id']), {'status': status, 'approver_id': user.userId});
      await reload();
      if (ctx.mounted) toast(ctx, 'Leave $status');
    } catch (e) {
      if (ctx.mounted) toast(ctx, errText(e));
    }
  }
}
