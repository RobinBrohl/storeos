import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:storeos_design_system/storeos_design_system.dart';

import '../application/session_controller.dart';
import '../data/store_api.dart';
import '../ui/login_screen.dart';
import '../ui/system_status_screen.dart';

class StoreOsApp extends StatefulWidget {
  const StoreOsApp({required this.api, required this.baseUri, super.key});

  final StoreApi api;
  final Uri baseUri;

  @override
  State<StoreOsApp> createState() => _StoreOsAppState();
}

class _StoreOsAppState extends State<StoreOsApp> {
  late final SessionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SessionController(widget.api);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => MaterialApp(
        title: 'StoreOS',
        debugShowCheckedModeBanner: false,
        theme: StoreTheme.light(),
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: _controller.isAuthenticated
            ? SystemStatusScreen(
                controller: _controller,
                baseUri: widget.baseUri,
              )
            : LoginScreen(controller: _controller, baseUri: widget.baseUri),
      ),
    );
  }
}
