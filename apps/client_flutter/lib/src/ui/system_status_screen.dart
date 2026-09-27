import 'package:flutter/material.dart';
import 'package:storeos_design_system/storeos_design_system.dart';

import '../application/session_controller.dart';

class SystemStatusScreen extends StatelessWidget {
  const SystemStatusScreen({
    required this.controller,
    required this.baseUri,
    super.key,
  });

  final SessionController controller;
  final Uri baseUri;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final user = controller.user;
    final checkedAt = controller.checkedAt;
    final databaseReachable = status?.database == 'reachable';

    return Scaffold(
      appBar: AppBar(
        title: const Text('StoreOS'),
        actions: [
          IconButton(
            key: const Key('logout-button'),
            tooltip: 'Abmelden',
            onPressed: controller.isBusy ? null : controller.signOut,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: StoreSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(StoreSpacing.lg),
              children: [
                Text(
                  'Standort-Systemstatus',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: StoreSpacing.sm),
                Text('Angemeldet als ${user?.username ?? ''}'),
                const SizedBox(height: StoreSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('refresh-button'),
                    onPressed: controller.isBusy
                        ? null
                        : controller.refreshStatus,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Status aktualisieren'),
                  ),
                ),
                const SizedBox(height: StoreSpacing.lg),
                if (controller.isBusy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: StoreSpacing.md),
                  const StoreStatusPanel(
                    title: 'Status wird geladen',
                    message: 'Der Standortserver wird gerade abgefragt.',
                    tone: StoreStatusTone.neutral,
                  ),
                ] else if (status == null) ...[
                  StoreStatusPanel(
                    title: 'Status nicht abrufbar',
                    message:
                        controller.error ??
                        'Der Standortserver hat keinen Status geliefert.',
                    tone: StoreStatusTone.warning,
                  ),
                ] else ...[
                  StoreStatusPanel(
                    title: databaseReachable
                        ? 'Standortserver erreichbar'
                        : 'Standortserver eingeschränkt',
                    message: databaseReachable
                        ? 'Die Datenbankverbindung wurde vom Server bestätigt.'
                        : 'Datenbankstatus laut Server: ${status.database}',
                    tone: databaseReachable
                        ? StoreStatusTone.positive
                        : StoreStatusTone.warning,
                  ),
                  const SizedBox(height: StoreSpacing.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(StoreSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Serverantwort',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: StoreSpacing.md),
                          _detail('Dienst', status.service),
                          _detail('API-Version', status.apiVersion.toString()),
                          _detail('Unternehmen-ID', status.companyId),
                          _detail('Standort-ID', status.locationId),
                          _detail('Datenbank', status.database),
                          if (checkedAt != null)
                            _detail(
                              'Abgerufen',
                              MaterialLocalizations.of(context).formatTimeOfDay(
                                TimeOfDay.fromDateTime(checkedAt),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: StoreSpacing.lg),
                Text(
                  'Server: ${baseUri.origin}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: StoreSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
