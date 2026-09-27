import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../application/employee_controller.dart';

class EmployeeSection extends StatefulWidget {
  const EmployeeSection({
    required this.controller,
    required this.self,
    super.key,
  });
  final EmployeeController controller;
  final bool self;
  @override
  State<EmployeeSection> createState() => _EmployeeSectionState();
}

class _EmployeeSectionState extends State<EmployeeSection> {
  EmployeeController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.whenIdle;
      if (!mounted) return;
      if (widget.self) {
        controller.startSelfRefresh();
      } else {
        controller.loadEmployees();
      }
    });
  }

  @override
  void dispose() {
    if (widget.self) controller.stopSelfRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.self ? 'Mein Mitarbeiterprofil' : 'Mitarbeiter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (controller.busy) const LinearProgressIndicator(),
            if (controller.error case final error?)
              Text(error, key: const Key('employee-error')),
            if (controller.notice case final notice?) Text(notice),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: controller.busy
                    ? null
                    : widget.self
                    ? controller.loadSelf
                    : controller.loadEmployees,
                icon: const Icon(Icons.refresh),
                label: const Text('Aktualisieren'),
              ),
            ),
            if (widget.self) ...[
              if (controller.mine case final profile?) _profile(profile),
              if (controller.mine == null &&
                  !controller.busy &&
                  controller.error == null)
                const Text('Kein bestätigtes Mitarbeiterprofil geladen.'),
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('create-employee'),
                  onPressed:
                      controller.busy ||
                          controller.creationUnavailableReason != null
                      ? null
                      : _create,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Mitarbeiter anlegen'),
                ),
              ),
              if (controller.creationUnavailableReason case final reason?)
                Text(reason),
              if (controller.employees?.isEmpty ?? false)
                const Text('Noch keine Mitarbeiterprofile vorhanden.'),
              for (final employee in controller.employees ?? <EmployeeDto>[])
                ListTile(
                  title: Text(employee.displayName),
                  subtitle: Text(employee.isActive ? 'Aktiv' : 'Deaktiviert'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: controller.busy
                      ? null
                      : () => controller.select(employee),
                ),
              if (controller.selected case final selected?) ...[
                const Divider(),
                _profile(selected),
                Wrap(
                  spacing: 12,
                  children: [
                    if (selected.isActive)
                      TextButton(
                        onPressed: controller.busy
                            ? null
                            : () => _rename(selected),
                        child: const Text('Anzeigename ändern'),
                      ),
                    if (selected.isActive)
                      TextButton(
                        onPressed: controller.busy
                            ? null
                            : () => _deactivate(selected),
                        child: const Text('Deaktivieren'),
                      ),
                  ],
                ),
                if (controller.link case final link?) ...[
                  Text('Verknüpfter Account: ${link.accountId}'),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: controller.busy
                          ? null
                          : () => _unlink(selected, link),
                      child: const Text('Verknüpfung entziehen'),
                    ),
                  ),
                ] else if (selected.isActive) ...[
                  const Text(
                    'Kein Account verknüpft. Die Verknüpfung erteilt keine Mitarbeiterrolle.',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: controller.busy ? null : () => _link(selected),
                      child: const Text('Account verknüpfen'),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    ),
  );

  Widget _profile(EmployeeDto employee) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            employee.displayName,
            key: const Key('employee-profile-name'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Standort: ${_locationName(employee.locationId)}'),
          Text('Zuordnung seit: ${employee.assignedFrom.toLocal()}'),
          if (employee.assignedUntil case final until?)
            Text('Zuordnung beendet: ${until.toLocal()}'),
          Text(employee.isActive ? 'Profil aktiv' : 'Profil deaktiviert'),
        ],
      ),
    ),
  );

  String _locationName(String id) =>
      controller.platform.organization?.locations
          .where((location) => location.id == id)
          .firstOrNull
          ?.name ??
      id;

  Future<void> _create() async {
    final locations = controller.configuredLocations;
    if (locations.isEmpty) return;
    var name = '';
    var locationId = locations.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Mitarbeiter anlegen'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('employee-name-input'),
                  decoration: const InputDecoration(labelText: 'Anzeigename'),
                  onChanged: (value) => name = value,
                ),
                DropdownButtonFormField<String>(
                  initialValue: locationId,
                  decoration: const InputDecoration(labelText: 'Standort'),
                  items: locations
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name!),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) update(() => locationId = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Anlegen'),
            ),
          ],
        ),
      ),
    );
    if (mounted && confirmed == true) await controller.create(name, locationId);
  }

  Future<void> _rename(EmployeeDto employee) async {
    var name = employee.displayName;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anzeigename ändern'),
        content: TextFormField(
          initialValue: name,
          onChanged: (value) => name = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (mounted && result != null) await controller.rename(employee, result);
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bestätigen'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _deactivate(EmployeeDto employee) async {
    if (await _confirm(
      'Profil deaktivieren?',
      'Die Standortzuordnung endet. Eine bestehende Account-Verknüpfung und dessen Sitzungen werden widerrufen.',
    )) {
      if (mounted) await controller.deactivate(employee);
    }
  }

  Future<void> _unlink(EmployeeDto employee, EmployeeLinkDto link) async {
    if (await _confirm(
      'Verknüpfung entziehen?',
      'Der Account verliert den Eigenzugriff. Bestehende Sitzungen werden widerrufen.',
    )) {
      if (mounted) await controller.unlink(employee, link);
    }
  }

  Future<void> _link(EmployeeDto employee) async {
    final candidates = controller.linkCandidates;
    final result = await showDialog<PlatformUserDto>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Account am selben Standort wählen'),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Rollen bleiben unverändert. Eigenzugriff benötigt die Rolle Mitarbeiter oder Administrator.',
            ),
          ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Kein aktiver Account am Standort vorhanden.'),
            ),
          for (final account in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, account),
              child: Text('${account.username} (${account.role})'),
            ),
        ],
      ),
    );
    if (mounted && result != null) {
      await controller.linkAccount(employee, result);
    }
  }
}
