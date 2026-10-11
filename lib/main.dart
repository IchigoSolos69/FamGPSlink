import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'family_controller.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyStartup());
}

Future<FamilyController> openFamily() async {
  await Firebase.initializeApp();
  final controller = FamilyController();
  try {
    await controller.initialize();
    return controller;
  } catch (_) {
    controller.dispose();
    rethrow;
  }
}

class FamilyStartup extends StatefulWidget {
  const FamilyStartup({super.key, this.open = openFamily});

  final Future<FamilyController> Function() open;

  @override
  State<FamilyStartup> createState() => _FamilyStartupState();
}

class _FamilyStartupState extends State<FamilyStartup> {
  FamilyController? _controller;
  Object? _error;
  bool _starting = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final generation = ++_generation;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final controller = await widget.open();
      if (!mounted || generation != _generation) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _starting = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _starting = false;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FamGpsApp(
    controller: _controller,
    starting: _starting,
    startupError: _error,
    onRetry: () => unawaited(_open()),
  );
}

class FamGpsApp extends StatelessWidget {
  const FamGpsApp({
    super.key,
    this.controller,
    this.starting = false,
    this.startupError,
    this.onRetry,
  });
  final FamilyController? controller;
  final bool starting;
  final Object? startupError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FamGPSlink',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff16745b)),
      scaffoldBackgroundColor: const Color(0xfff5f7f4),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff5f7f4),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    ),
    home: starting
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : startupError != null
        ? StartupErrorPage(error: startupError!, onRetry: onRetry!)
        : controller == null
        ? const SetupPage()
        : AnimatedBuilder(
            animation: controller!,
            builder: (context, _) {
              final family = controller!;
              if (family.loading) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (family.self == null) return WelcomePage(controller: family);
              return FamilyHome(controller: family);
            },
          ),
  );
}
