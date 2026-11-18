import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/auth.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../widgets/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  bool _showPass = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Username and password are required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().login(_user.text.trim(), _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editServer() async {
    String selected = AppConfig.isSit ? 'SIT' : 'DEV';
    final ctl = TextEditingController(text: AppConfig.apiUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text('Server Environment', style: serif(18)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Switch between local DEV and cloud SIT, or enter a custom URL:',
                style: TextStyle(fontSize: 12.5, color: C.ink3)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('DEV (Local)')),
                  selected: selected == 'DEV',
                  onSelected: (val) {
                    if (val) {
                      setDlgState(() {
                        selected = 'DEV';
                        ctl.text = AppConfig.devUrl;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('SIT (Cloud)')),
                  selected: selected == 'SIT',
                  onSelected: (val) {
                    if (val) {
                      setDlgState(() {
                        selected = 'SIT';
                        ctl.text = AppConfig.sitUrl;
                      });
                    }
                  },
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'API URL', hintText: 'https://...'),
              onChanged: (_) {
                setDlgState(() {
                  selected = 'CUSTOM';
                });
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save & Apply')),
          ],
        ),
      ),
    );
    if (saved == true && ctl.text.trim().isNotEmpty) {
      await AppConfig.setApiUrl(ctl.text);
      if (mounted) setState(() {});
    }
    ctl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF0F4F8), Color(0xFFD9E2EC)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 36, offset: Offset(0, 18))],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Center(child: Image.asset('assets/golden-years-logo.png', height: 70)),
                    const SizedBox(height: 14),
                    Text('Golden Years', textAlign: TextAlign.center, style: serif(24, color: C.navy)),
                    const SizedBox(height: 4),
                    const Text('Care Operations Console', textAlign: TextAlign.center, style: TextStyle(color: C.ink3, fontSize: 14)),
                    const SizedBox(height: 24),
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: C.redLt,
                          borderRadius: BorderRadius.circular(8),
                          border: const Border(left: BorderSide(color: C.red, width: 4)),
                        ),
                        child: Text(_error!, style: const TextStyle(color: C.redDk, fontSize: 13)),
                      ),
                    TextField(
                      controller: _user,
                      enabled: !_loading,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Username', hintText: 'e.g. admin', floatingLabelBehavior: FloatingLabelBehavior.always),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pass,
                      enabled: !_loading,
                      obscureText: !_showPass,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: '••••••••',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        suffixIcon: IconButton(
                          icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                          onPressed: () => setState(() => _showPass = !_showPass),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                      child: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Sign in to Console', style: TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    TextButton.icon(
                      onPressed: _loading ? null : _editServer,
                      icon: const Icon(Icons.dns_outlined, size: 16, color: C.ink3),
                      label: Text('Server [${AppConfig.currentEnv}]: ${AppConfig.apiUrl}',
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: C.ink3)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
