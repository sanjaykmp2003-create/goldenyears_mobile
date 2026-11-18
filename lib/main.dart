import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/api_client.dart';
import 'core/auth.dart';
import 'core/config.dart';
import 'core/repo.dart';
import 'core/theme.dart';
import 'screens/login_screen.dart';
import 'shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  await AppConfig.load();
  final api = ApiClient();
  final auth = AuthState(api);
  await auth.restore();
  runApp(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<Repo>(create: (_) => Repo(api)),
      ChangeNotifierProvider<AuthState>.value(value: auth),
    ],
    child: const UnicareApp(),
  ));
}

class UnicareApp extends StatelessWidget {
  const UnicareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Golden Years',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Consumer<AuthState>(
        builder: (_, auth, __) {
          final u = auth.user;
          if (u == null) return const LoginScreen();
          return Shell(key: ValueKey(u.userId), user: u);
        },
      ),
    );
  }
}
