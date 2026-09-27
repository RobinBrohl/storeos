import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:storeos_design_system/storeos_design_system.dart';

import '../application/session_controller.dart';
import '../application/platform_controller.dart';
import '../application/employee_controller.dart';
import '../application/task_template_controller.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import '../ui/login_screen.dart';
import '../ui/platform_home_screen.dart';
import '../ui/system_status_screen.dart';

class StoreOsApp extends StatefulWidget {
  const StoreOsApp({
    required this.api,
    required this.baseUri,
    this.platformApi,
    super.key,
  });

  final StoreApi api;
  final Uri baseUri;
  final PlatformApi? platformApi;

  @override
  State<StoreOsApp> createState() => _StoreOsAppState();
}

class _StoreOsAppState extends State<StoreOsApp> {
  late final SessionController _controller;
  PlatformController? _platformController;
  EmployeeController? _employees;
  TaskTemplateController? _templates;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _controller = SessionController(widget.api);
    _controller.addListener(_closeDialogsOnSessionEnd);
    if (widget.platformApi case final api?) {
      _platformController = PlatformController(_controller, api);
      _employees = EmployeeController(_controller, _platformController!, api);
      _templates = TaskTemplateController(
        _controller,
        _platformController!,
        api,
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_closeDialogsOnSessionEnd);
    _templates?.dispose();
    _employees?.dispose();
    _platformController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _closeDialogsOnSessionEnd() {
    final authenticated = _controller.isAuthenticated;
    if (_wasAuthenticated && !authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
    _wasAuthenticated = authenticated;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => MaterialApp(
        title: 'StoreOS',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        theme: StoreTheme.light(),
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: _controller.isAuthenticated
            ? _platformController == null
                  ? SystemStatusScreen(
                      controller: _controller,
                      baseUri: widget.baseUri,
                    )
                  : PlatformHomeScreen(
                      session: _controller,
                      platform: _platformController!,
                      employees: _employees!,
                      templates: _templates!,
                      baseUri: widget.baseUri,
                    )
            : LoginScreen(controller: _controller, baseUri: widget.baseUri),
      ),
    );
  }
}
