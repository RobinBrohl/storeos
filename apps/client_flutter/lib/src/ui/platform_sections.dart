import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:storeos_design_system/storeos_design_system.dart';

import '../application/platform_controller.dart';
import '../application/platform_models.dart';

class OrganizationSection extends StatelessWidget {
  const OrganizationSection({required this.controller, super.key});

  final PlatformController controller;

  @override
  Widget build(BuildContext context) {
    final organization = controller.organization;
    if (organization == null) {
      return const _EmptySection(
        'Organisation wird vom Standortserver geladen.',
      );
    }
    final editable = controller.allows('organization.write');
    return _SectionList(
      title: 'Unternehmen und Standorte',
      children: [
        if (organization.needsSetup)
          StoreStatusPanel(
            title: 'Einrichtung offen',
            message:
                'Unternehmen und erster Standort haben noch keinen Namen. Die bestehenden IDs bleiben erhalten.',
            tone: StoreStatusTone.warning,
          ),
        if (organization.needsSetup && editable) ...[
          const SizedBox(height: StoreSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('organization-setup'),
              onPressed: controller.isBusy
                  ? null
                  : () => _setup(context, organization),
              icon: const Icon(Icons.tune),
              label: const Text('Ersteinrichtung abschließen'),
            ),
          ),
        ],
        const SizedBox(height: StoreSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(StoreSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unternehmen',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: StoreSpacing.sm),
                Text(organization.company.name ?? 'Noch nicht eingerichtet'),
                Text(
                  'ID: ${organization.company.id} · Version ${organization.company.version}',
                ),
                if (editable && !organization.needsSetup)
                  TextButton.icon(
                    key: const Key('rename-company'),
                    onPressed: controller.isBusy
                        ? null
                        : () => _renameCompany(context, organization.company),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Unternehmen umbenennen'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: StoreSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                'Standorte',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (editable && !organization.needsSetup)
              FilledButton.tonalIcon(
                key: const Key('create-location'),
                onPressed: controller.isBusy
                    ? null
                    : () => _createLocation(context),
                icon: const Icon(Icons.add),
                label: const Text('Anlegen'),
              ),
          ],
        ),
        for (final location in organization.locations)
          Card(
            child: ListTile(
              title: Text(location.name ?? 'Noch nicht eingerichtet'),
              subtitle: Text(
                'ID: ${location.id} · Version ${location.version}',
              ),
              trailing: editable && !organization.needsSetup
                  ? IconButton(
                      tooltip: 'Standort umbenennen',
                      onPressed: controller.isBusy
                          ? null
                          : () => _renameLocation(context, location),
                      icon: const Icon(Icons.edit_outlined),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Future<void> _setup(
    BuildContext context,
    OrganizationSnapshot current,
  ) async {
    final values = await _twoTextDialog(
      context,
      title: 'Ersteinrichtung',
      firstLabel: 'Unternehmensname',
      secondLabel: 'Name des ersten Standorts',
      firstInitial: current.company.name ?? '',
      secondInitial: current.locations.first.name ?? '',
    );
    if (values == null) return;
    await controller.setup(values.$1, values.$2);
  }

  Future<void> _renameCompany(
    BuildContext context,
    CompanyRecord company,
  ) async {
    final name = await _textDialog(
      context,
      title: 'Unternehmen umbenennen',
      label: 'Neuer Name',
      initial: company.name ?? '',
    );
    if (name != null) await controller.renameCompany(name);
  }

  Future<void> _createLocation(BuildContext context) async {
    final name = await _textDialog(
      context,
      title: 'Standort anlegen',
      label: 'Standortname',
    );
    if (name != null) await controller.createLocation(name);
  }

  Future<void> _renameLocation(
    BuildContext context,
    LocationRecord location,
  ) async {
    final name = await _textDialog(
      context,
      title: 'Standort umbenennen',
      label: 'Neuer Name',
      initial: location.name ?? '',
    );
    if (name != null) await controller.renameLocation(location, name);
  }
}

class UsersSection extends StatelessWidget {
  const UsersSection({required this.controller, super.key});

  final PlatformController controller;

  @override
  Widget build(BuildContext context) {
    final users = controller.users;
    if (users == null) {
      return const _EmptySection('Benutzerliste noch nicht geladen.');
    }
    final locations =
        controller.organization?.locations ?? const <LocationRecord>[];
    return _SectionList(
      title: 'Benutzer und Rollen',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('create-user'),
            onPressed: controller.isBusy || locations.isEmpty
                ? null
                : () => _createUser(context, locations),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Benutzer anlegen'),
          ),
        ),
        const SizedBox(height: StoreSpacing.md),
        if (users.isEmpty) const Text('Keine Benutzer geliefert.'),
        for (final user in users)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(StoreSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${_roleLabel(user.role)} · ${user.isActive ? 'Aktiv' : 'Deaktiviert'} · Version ${user.version}',
                  ),
                  Text('Standort-ID: ${user.locationId}'),
                  Wrap(
                    spacing: StoreSpacing.sm,
                    children: [
                      TextButton.icon(
                        onPressed: controller.isBusy
                            ? null
                            : () => _editUser(context, user),
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Rolle und Status'),
                      ),
                      TextButton.icon(
                        onPressed: controller.isBusy
                            ? null
                            : () => _resetPassword(context, user),
                        icon: const Icon(Icons.password_outlined),
                        label: const Text('Passwort ersetzen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _createUser(
    BuildContext context,
    List<LocationRecord> locations,
  ) async {
    final result = await _userCreateDialog(context, locations);
    if (result == null) return;
    await controller.createUser(
      username: result.username,
      password: result.password,
      locationId: result.locationId,
      role: result.role,
    );
  }

  Future<void> _editUser(BuildContext context, PlatformUser user) async {
    final result = await _userEditDialog(context, user);
    if (result != null) {
      await controller.updateUser(user, result.$1, result.$2);
    }
  }

  Future<void> _resetPassword(BuildContext context, PlatformUser user) async {
    final password = await _textDialog(
      context,
      title: 'Passwort für ${user.username} ersetzen',
      label: 'Neues Passwort',
      secret: true,
    );
    if (password != null) await controller.resetPassword(user, password);
  }
}

String _roleLabel(String role) => switch (role) {
  'admin' => 'Administrator',
  'auditor' => 'Auditor',
  'viewer' => 'Leser',
  'employee' => 'Mitarbeiter',
  _ => role,
};

class _SectionList extends StatelessWidget {
  const _SectionList({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: ListView(
        padding: const EdgeInsets.all(StoreSpacing.lg),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: StoreSpacing.lg),
          ...children,
        ],
      ),
    ),
  );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(StoreSpacing.lg),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

Future<String?> _textDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  bool secret = false,
  int maxLines = 1,
}) async {
  var value = initial;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: TextFormField(
          initialValue: initial,
          onChanged: (next) => value = next,
          autofocus: true,
          obscureText: secret,
          maxLines: secret ? 1 : maxLines,
          minLines: secret ? 1 : maxLines,
          decoration: InputDecoration(labelText: label),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, value),
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
}

Future<(String, String)?> _twoTextDialog(
  BuildContext context, {
  required String title,
  required String firstLabel,
  required String secondLabel,
  String firstInitial = '',
  String secondInitial = '',
}) async {
  var first = firstInitial;
  var second = secondInitial;
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: firstInitial,
              onChanged: (value) => first = value,
              decoration: InputDecoration(labelText: firstLabel),
            ),
            const SizedBox(height: StoreSpacing.md),
            TextFormField(
              initialValue: secondInitial,
              onChanged: (value) => second = value,
              decoration: InputDecoration(labelText: secondLabel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (first, second)),
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
}

class _NewUser {
  const _NewUser(this.username, this.password, this.locationId, this.role);
  final String username;
  final String password;
  final String locationId;
  final String role;
}

Future<_NewUser?> _userCreateDialog(
  BuildContext context,
  List<LocationRecord> locations,
) async {
  String name = '';
  String password = '';
  String locationId = locations.first.id;
  String role = 'viewer';
  return showDialog<_NewUser>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        scrollable: true,
        title: const Text('Benutzer anlegen'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                onChanged: (value) => name = value,
                decoration: const InputDecoration(labelText: 'Benutzername'),
              ),
              const SizedBox(height: StoreSpacing.md),
              TextFormField(
                onChanged: (value) => password = value,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Startpasswort'),
              ),
              const SizedBox(height: StoreSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: locationId,
                decoration: const InputDecoration(labelText: 'Heimatstandort'),
                items: [
                  for (final location in locations)
                    DropdownMenuItem(
                      value: location.id,
                      child: Text(location.name ?? location.id),
                    ),
                ],
                onChanged: (value) =>
                    setDialogState(() => locationId = value ?? locationId),
              ),
              const SizedBox(height: StoreSpacing.md),
              _roleDropdown(
                role,
                (value) => setDialogState(() => role = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _NewUser(name, password, locationId, role),
            ),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    ),
  );
}

Future<(String, bool)?> _userEditDialog(
  BuildContext context,
  PlatformUser user,
) async {
  String role = user.role;
  bool isActive = user.isActive;
  return showDialog<(String, bool)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('${user.username} verwalten'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _roleDropdown(
                role,
                (value) => setDialogState(() => role = value),
              ),
              SwitchListTile(
                title: const Text('Account aktiv'),
                value: isActive,
                onChanged: (value) => setDialogState(() => isActive = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (role, isActive)),
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
}

Widget _roleDropdown(String value, ValueChanged<String> onChanged) =>
    DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Rolle'),
      items: const [
        DropdownMenuItem(value: 'viewer', child: Text('Leser')),
        DropdownMenuItem(value: 'employee', child: Text('Mitarbeiter')),
        DropdownMenuItem(value: 'auditor', child: Text('Auditor')),
        DropdownMenuItem(value: 'admin', child: Text('Administrator')),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );

class LogSection extends StatelessWidget {
  const LogSection({required this.controller, required this.audit, super.key});

  final PlatformController controller;
  final bool audit;

  @override
  Widget build(BuildContext context) {
    final rows = audit ? controller.audit : controller.events;
    final cursor = audit
        ? controller.auditNextCursor
        : controller.eventsNextCursor;
    if (rows == null) {
      return _EmptySection(
        audit
            ? 'Audit-Protokoll noch nicht geladen.'
            : 'Ereignisse noch nicht geladen.',
      );
    }
    return _SectionList(
      title: audit ? 'Audit-Protokoll' : 'Ereignisse und Zustellung',
      children: [
        if (rows.isEmpty) const Text('Keine Einträge auf dieser Seite.'),
        for (final row in rows)
          Card(
            child: ExpansionTile(
              title: Text(_rowTitle(row)),
              subtitle: Text(_rowSubtitle(row)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(StoreSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent('  ').convert(row),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (!audit &&
                          row['status'] == 'dead_letter' &&
                          controller.context?.role == 'admin')
                        TextButton.icon(
                          key: Key('replay-${row['eventId']}'),
                          onPressed: controller.isBusy
                              ? null
                              : () => controller.replayEvent(row),
                          icon: const Icon(Icons.replay),
                          label: const Text('Zustellung erneut einreihen'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (cursor != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: Key(audit ? 'audit-more' : 'events-more'),
              onPressed: controller.isBusy
                  ? null
                  : audit
                  ? () => controller.loadAudit(more: true)
                  : () => controller.loadEvents(more: true),
              icon: const Icon(Icons.expand_more),
              label: const Text('Weitere Einträge laden'),
            ),
          ),
      ],
    );
  }

  String _rowTitle(Map<String, dynamic> row) {
    if (audit) {
      return '${row['action'] ?? 'Unbekannte Aktion'} · ${row['entityType'] ?? 'Objekt'}';
    }
    return '${row['type'] ?? 'Unbekanntes Ereignis'} · ${row['status'] ?? 'Status unbekannt'}';
  }

  String _rowSubtitle(Map<String, dynamic> row) {
    final time = audit ? row['occurredAt'] : row['recordedAt'];
    final id = audit ? row['id'] : row['eventId'];
    return '${time ?? 'Zeit unbekannt'} · ${id ?? 'ID unbekannt'}';
  }
}

class PluginsSection extends StatelessWidget {
  const PluginsSection({required this.controller, super.key});

  final PlatformController controller;

  @override
  Widget build(BuildContext context) {
    final plugins = controller.plugins;
    if (plugins == null) {
      return const _EmptySection('Plugin-Registrierungen noch nicht geladen.');
    }
    return _SectionList(
      title: 'Externe Plugin-API-Clients',
      children: [
        const StoreStatusPanel(
          title: 'Externer API-Client',
          message:
              'StoreOS registriert und berechtigt externe Clients. Es wird kein Plugin-Code installiert oder ausgeführt.',
          tone: StoreStatusTone.neutral,
        ),
        const SizedBox(height: StoreSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('register-plugin'),
            onPressed: controller.isBusy ? null : () => _register(context),
            icon: const Icon(Icons.add),
            label: const Text('Manifest registrieren'),
          ),
        ),
        const SizedBox(height: StoreSpacing.md),
        if (plugins.isEmpty)
          const Text('Keine Plugin-Registrierungen vorhanden.'),
        for (final plugin in plugins)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(StoreSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'ID: ${plugin.id} · ${plugin.status} · Version ${plugin.version}',
                  ),
                  if (plugin.locationId case final locationId?)
                    Text('Standort-ID: $locationId'),
                  if (plugin.tokenExpiresAt case final expiry?)
                    Text('Token läuft ab: $expiry'),
                  Text(
                    'Freigegebene Rechte: ${plugin.permissions.join(', ').isEmpty ? 'keine' : plugin.permissions.join(', ')}',
                  ),
                  Text(
                    'Abonnements: ${plugin.subscriptions.join(', ').isEmpty ? 'keine' : plugin.subscriptions.join(', ')}',
                  ),
                  ExpansionTile(
                    title: const Text('Manifest ansehen'),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(plugin.manifest),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: StoreSpacing.sm,
                    children: [
                      if (plugin.status != 'approved')
                        TextButton.icon(
                          key: Key('approve-${plugin.id}'),
                          onPressed: controller.isBusy
                              ? null
                              : () => _approve(context, plugin),
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('Freigeben'),
                        ),
                      if (plugin.status == 'approved')
                        TextButton.icon(
                          key: Key('disable-${plugin.id}'),
                          onPressed: controller.isBusy
                              ? null
                              : () => _disable(context, plugin),
                          icon: const Icon(Icons.block_outlined),
                          label: const Text('Deaktivieren'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _register(BuildContext context) async {
    final source = await _textDialog(
      context,
      title: 'Plugin-Manifest registrieren',
      label: 'Manifest als JSON',
      maxLines: 12,
      initial: const JsonEncoder.withIndent('  ').convert({
        'id': '',
        'name': '',
        'version': '1.0.0',
        'vendor': '',
        'coreApiVersion': 1,
        'capabilities': ['organization.read'],
        'permissions': ['organization.read'],
        'subscriptions': <String>[],
        'configurationSchema': {
          'type': 'object',
          'properties': <String, dynamic>{},
          'additionalProperties': false,
        },
      }),
    );
    if (source != null) await controller.registerPlugin(source);
  }

  Future<void> _approve(BuildContext context, PluginRecord plugin) async {
    final scope = await _pluginScopeDialog(
      context,
      plugin,
      controller.organization?.locations ?? const <LocationRecord>[],
    );
    if (scope == null) return;
    final approval = await controller.approvePlugin(
      plugin,
      locationId: scope.locationId,
      permissions: scope.permissions,
      subscriptions: scope.subscriptions,
    );
    if (approval == null || !context.mounted) return;
    await _tokenDialog(context, approval);
  }

  Future<void> _disable(BuildContext context, PluginRecord plugin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Plugin deaktivieren?'),
        content: Text(
          '${plugin.displayName}: Das Token und ausstehende Zustellungen werden widerrufen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deaktivieren'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.disablePlugin(plugin);
  }
}

class _PluginScope {
  const _PluginScope(this.locationId, this.permissions, this.subscriptions);
  final String locationId;
  final List<String> permissions;
  final List<String> subscriptions;
}

Future<_PluginScope?> _pluginScopeDialog(
  BuildContext context,
  PluginRecord plugin,
  List<LocationRecord> locations,
) {
  if (locations.isEmpty) return Future.value();
  String locationId = plugin.locationId ?? locations.first.id;
  final permissions = plugin.permissions.toSet();
  final subscriptions = plugin.subscriptions.toSet();
  return showDialog<_PluginScope>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('${plugin.displayName} freigeben'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Die Auswahl muss innerhalb des registrierten Manifests liegen.',
                ),
                const SizedBox(height: StoreSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: locationId,
                  decoration: const InputDecoration(labelText: 'Ein Standort'),
                  items: [
                    for (final location in locations)
                      DropdownMenuItem(
                        value: location.id,
                        child: Text(location.name ?? location.id),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => locationId = value ?? locationId),
                ),
                const SizedBox(height: StoreSpacing.md),
                Text(
                  'Leserechte',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final value in plugin.requestedPermissions)
                  CheckboxListTile(
                    dense: true,
                    title: Text(value),
                    value: permissions.contains(value),
                    onChanged: (selected) => setDialogState(() {
                      selected == true
                          ? permissions.add(value)
                          : permissions.remove(value);
                    }),
                  ),
                Text(
                  'Ereignistypen',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final value in plugin.requestedSubscriptions)
                  CheckboxListTile(
                    dense: true,
                    title: Text(value),
                    value: subscriptions.contains(value),
                    onChanged: (selected) => setDialogState(() {
                      selected == true
                          ? subscriptions.add(value)
                          : subscriptions.remove(value);
                    }),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _PluginScope(
                locationId,
                permissions.toList()..sort(),
                subscriptions.toList()..sort(),
              ),
            ),
            child: const Text('Freigeben und Token erzeugen'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _tokenDialog(
  BuildContext context,
  PluginApproval approval,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    bool visible = false;
    return StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Plugin-Token – einmalige Anzeige'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Jetzt sicher übernehmen. Nach dem Schließen kann StoreOS dieses Token nicht erneut anzeigen.',
              ),
              const SizedBox(height: StoreSpacing.md),
              Text('Gültig bis: ${approval.tokenExpiresAt}'),
              const SizedBox(height: StoreSpacing.md),
              if (visible)
                SelectableText(approval.token, key: const Key('plugin-token'))
              else
                const Text('Token verborgen'),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => setDialogState(() => visible = !visible),
            icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
            label: Text(visible ? 'Verbergen' : 'Anzeigen'),
          ),
          TextButton.icon(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: approval.token)),
            icon: const Icon(Icons.copy),
            label: const Text('Kopieren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  },
);
