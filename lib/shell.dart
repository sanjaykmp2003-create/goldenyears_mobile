import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/auth.dart';
import 'core/repo.dart';
import 'core/theme.dart';
import 'screens/admin_roles_screen.dart';
import 'screens/admin_users_screen.dart';
import 'screens/assessment_screen.dart';
import 'screens/attendance_screen.dart';
import 'screens/billing_screen.dart';
import 'screens/clients_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/duty_screen.dart';
import 'screens/enquiries_screen.dart';
import 'screens/leave_screen.dart';
import 'screens/masters_screen.dart';
import 'screens/nurse_app_screen.dart';
import 'screens/payroll_screen.dart';
import 'widgets/ui.dart';

class ScreenDef {
  final String key, label, section;
  final IconData icon;
  final Widget Function(UserContext user) build;
  const ScreenDef(this.key, this.label, this.section, this.icon, this.build);
}

/// Same screens, grouping and labels as the web sidebar (layout/Sidebar.tsx).
final List<ScreenDef> kScreens = [
  ScreenDef('dashboard', 'Dashboard', 'Overview', Icons.dashboard_outlined, (u) => DashboardScreen(user: u)),
  ScreenDef('enquiry', 'Enquiries', 'Client Journey', Icons.chat_bubble_outline, (u) => const EnquiriesScreen()),
  ScreenDef('clients', 'Clients & Patients', 'Client Journey', Icons.groups_outlined, (u) => const ClientsScreen()),
  ScreenDef('assessment', 'Patient Assessment', 'Client Journey', Icons.fact_check_outlined, (u) => const AssessmentScreen()),
  ScreenDef('duty', 'Duty Roster', 'Care Delivery', Icons.calendar_month_outlined, (u) => DutyScreen(user: u)),
  ScreenDef('attendance', 'Attendance', 'Care Delivery', Icons.access_time, (u) => AttendanceScreen(user: u)),
  ScreenDef('leave', 'Leave Requests', 'Care Delivery', Icons.event_available_outlined, (u) => LeaveScreen(user: u)),
  ScreenDef('nurseapp', 'Patient Summary & Charts', 'Nurses App', Icons.smartphone_outlined, (u) => NurseAppScreen(user: u)),
  ScreenDef('billing', 'Client Billing', 'Finance', Icons.receipt_long_outlined, (u) => const BillingScreen()),
  ScreenDef('payroll', 'Nurse Payroll', 'Finance', Icons.payments_outlined, (u) => const PayrollScreen()),
  ScreenDef('masters', 'Masters', 'Configuration', Icons.settings_outlined, (u) => const MastersScreen()),
  ScreenDef('roles', 'Role Management', 'Configuration', Icons.shield_outlined, (u) => const AdminRolesScreen()),
  ScreenDef('users', 'User Management', 'Configuration', Icons.manage_accounts_outlined, (u) => const AdminUsersScreen()),
];

/// Preferred bottom-bar tabs; the first four the user is allowed to see are used.
const _bottomPriority = ['dashboard', 'clients', 'attendance', 'nurseapp', 'duty', 'enquiry', 'billing', 'leave'];

class Shell extends StatefulWidget {
  const Shell({super.key, required this.user});
  final UserContext user;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  late String _page;

  List<ScreenDef> get _allowed => kScreens.where((d) => widget.user.can(d.key)).toList();

  @override
  void initState() {
    super.initState();
    final a = _allowed;
    _page = a.any((d) => d.key == 'dashboard') ? 'dashboard' : (a.isNotEmpty ? a.first.key : 'dashboard');
  }

  List<ScreenDef> get _bottom {
    final a = _allowed;
    final out = <ScreenDef>[];
    for (final k in _bottomPriority) {
      final d = a.where((x) => x.key == k);
      if (d.isNotEmpty && out.length < 4) out.add(d.first);
    }
    return out;
  }

  Future<void> _logout() async {
    await context.read<Repo>().clearCache();
    if (mounted) await context.read<AuthState>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _allowed;
    if (allowed.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Golden Years')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const EmptyState('No screens are assigned to your role. Ask an administrator to grant access.', icon: Icons.lock_outline),
              OutlinedButton(onPressed: _logout, child: const Text('Sign out')),
            ]),
          ),
        ),
      );
    }
    final current = allowed.firstWhere((d) => d.key == _page, orElse: () => allowed.first);
    final bottom = _bottom;
    final bi = bottom.indexWhere((d) => d.key == current.key);

    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: Text(current.label),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PopupMenuButton<String>(
              tooltip: 'Account',
              offset: const Offset(0, 44),
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              onSelected: (v) {
                if (v == 'out') _logout();
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text('${widget.user.userId}\n${widget.user.userType}',
                      style: const TextStyle(fontSize: 12.5, color: C.ink2)),
                ),
                const PopupMenuItem<String>(value: 'out', child: Text('Sign out')),
              ],
              child: Avatar(widget.user.userId, size: 34),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(allowed, current),
      body: SafeArea(top: false, child: KeyedSubtree(key: ValueKey(current.key), child: current.build(widget.user))),
      bottomNavigationBar: bottom.length < 2
          ? null
          : NavigationBar(
              selectedIndex: bi >= 0 ? bi : bottom.length,
              onDestinationSelected: (i) {
                if (i == bottom.length) {
                  _scaffold.currentState?.openDrawer();
                } else {
                  setState(() => _page = bottom[i].key);
                }
              },
              destinations: [
                for (final d in bottom)
                  NavigationDestination(icon: Icon(d.icon), label: d.label.split(' ').first.replaceAll('&', '')),
                const NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
              ],
            ),
    );
  }

  Drawer _buildDrawer(List<ScreenDef> allowed, ScreenDef current) {
    final sections = <String>[];
    for (final d in allowed) {
      if (!sections.contains(d.section)) sections.add(d.section);
    }
    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.line2))),
            child: Image.asset('assets/golden-years-logo.png', height: 56, fit: BoxFit.contain),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 6, 12, 12), children: [
              for (final sec in sections) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                  child: Text(sec.toUpperCase(),
                      style: const TextStyle(fontSize: 10.5, letterSpacing: 1.3, color: C.ink3, fontWeight: FontWeight.w600)),
                ),
                for (final d in allowed.where((x) => x.section == sec))
                  _navItem(d, d.key == current.key),
              ],
            ]),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(children: [
              Avatar(widget.user.userId, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.user.userId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(widget.user.userType[0].toUpperCase() + widget.user.userType.substring(1),
                      style: const TextStyle(fontSize: 11.5, color: C.ink3)),
                ]),
              ),
              IconButton(onPressed: _logout, tooltip: 'Sign out', icon: const Icon(Icons.logout, size: 19, color: C.ink3)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _navItem(ScreenDef d, bool on) => Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Material(
          color: on ? C.greenLt : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () {
              Navigator.pop(context); // close drawer
              setState(() => _page = d.key);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
              child: Row(children: [
                Icon(d.icon, size: 20, color: on ? C.greenDk : C.ink3),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(d.label,
                      style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? C.greenDk : C.ink2)),
                ),
              ]),
            ),
          ),
        ),
      );
}
