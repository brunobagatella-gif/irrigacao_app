import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controllers/app_controller.dart';
import 'firebase_options.dart';
import 'views/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  var firebaseOk = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseOk = true;
  } catch (e) {
    debugPrint('Firebase indisponível, abrindo em modo demonstração: $e');
  }

  runApp(ChangeNotifierProvider(
    create: (_) => AppController(prefs: prefs, firebaseDisponivel: firebaseOk),
    child: const IrrigacaoApp(),
  ));
}

class IrrigacaoApp extends StatelessWidget {
  const IrrigacaoApp({super.key});

  static const verde = Color(0xFF2E7D32);

  ThemeData _tema(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: verde, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          b == Brightness.light ? const Color(0xFFF4F7F2) : scheme.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minha Horta',
      debugShowCheckedModeBanner: false,
      theme: _tema(Brightness.light),
      // visual de horta pensado para o tema claro
      themeMode: ThemeMode.light,
      darkTheme: _tema(Brightness.dark),
      home: const HomeShell(),
    );
  }
}
