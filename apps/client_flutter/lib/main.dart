import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_design_system/storeos_design_system.dart';

import 'src/app/storeos_app.dart';
import 'src/config/api_configuration.dart';
import 'src/data/http_store_api.dart';
import 'src/data/http_platform_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final configuration = ApiConfiguration.fromEnvironment();
    final client = http.Client();
    runApp(
      StoreOsApp(
        api: HttpStoreApi(baseUri: configuration.baseUri, client: client),
        platformApi: HttpPlatformApi(
          baseUri: configuration.baseUri,
          client: client,
        ),
        baseUri: configuration.baseUri,
      ),
    );
  } on FormatException catch (error) {
    runApp(
      MaterialApp(
        title: 'StoreOS – Konfiguration',
        theme: StoreTheme.light(),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(StoreSpacing.lg),
                child: StoreStatusPanel(
                  title: 'Serveradresse prüfen',
                  message:
                      '${error.message} Bitte STOREOS_API_URL korrigieren.',
                  tone: StoreStatusTone.critical,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
