import 'package:flutter/material.dart';
import 'package:storeos_design_system/storeos_design_system.dart';

import '../application/platform_controller.dart';
import '../application/session_controller.dart';
import 'platform_sections.dart';
import 'system_status_screen.dart';

enum _Section { status, organization, users, audit, events, plugins }

class PlatformHomeScreen extends StatefulWidget {
  const PlatformHomeScreen({
    required this.session,
    required this.platform,
    required this.baseUri,
    super.key,
  });

  final SessionController session;
  final PlatformController platform;
  final Uri baseUri;

  @override
  State<PlatformHomeScreen> createState() => _PlatformHomeScreenState();
}

class _PlatformHomeScreenState extends State<PlatformHomeScreen> {
  _Section _selected = _Section.status;

  List<_Section> get _available => [
    _Section.status,
    if (widget.platform.allows('organization.read')) _Section.organization,
    if (widget.platform.allows('identity.read')) _Section.users,
    if (widget.platform.allows('audit.read')) _Section.audit,
    if (widget.platform.allows('events.read')) _Section.events,
    if (widget.platform.allows('plugins.read')) _Section.plugins,
  ];

  String _label(_Section section) => switch (section) {
    _Section.status => 'Status',
    _Section.organization => 'Organisation',
    _Section.users => 'Benutzer',
    _Section.audit => 'Audit',
    _Section.events => 'Ereignisse',
    _Section.plugins => 'Plugins',
  };

  IconData _icon(_Section section) => switch (section) {
    _Section.status => Icons.monitor_heart_outlined,
    _Section.organization => Icons.corporate_fare_outlined,
    _Section.users => Icons.people_outline,
    _Section.audit => Icons.history_outlined,
    _Section.events => Icons.notifications_active_outlined,
    _Section.plugins => Icons.extension_outlined,
  };

  void _select(_Section section) {
    setState(() => _selected = section);
    switch (section) {
      case _Section.status:
        break;
      case _Section.organization:
        if (widget.platform.organization == null) {
          widget.platform.loadOrganization();
        }
      case _Section.users:
        if (widget.platform.users == null) widget.platform.loadUsers();
      case _Section.audit:
        if (widget.platform.audit == null) widget.platform.loadAudit();
      case _Section.events:
        if (widget.platform.events == null) widget.platform.loadEvents();
      case _Section.plugins:
        if (widget.platform.plugins == null) widget.platform.loadPlugins();
    }
  }

  void _refresh(_Section section) {
    switch (section) {
      case _Section.status:
        widget.session.refreshStatus();
      case _Section.organization:
        widget.platform.loadOrganization();
      case _Section.users:
        widget.platform.loadUsers();
      case _Section.audit:
        widget.platform.loadAudit();
      case _Section.events:
        widget.platform.loadEvents();
      case _Section.plugins:
        widget.platform.loadPlugins();
    }
  }

  Widget _body(_Section section) => switch (section) {
    _Section.status => SystemStatusView(
      controller: widget.session,
      baseUri: widget.baseUri,
    ),
    _Section.organization => OrganizationSection(controller: widget.platform),
    _Section.users => UsersSection(controller: widget.platform),
    _Section.audit => LogSection(controller: widget.platform, audit: true),
    _Section.events => LogSection(controller: widget.platform, audit: false),
    _Section.plugins => PluginsSection(controller: widget.platform),
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.platform,
    builder: (context, _) {
      final sections = _available;
      final section = sections.contains(_selected)
          ? _selected
          : _Section.status;
      final index = sections.indexOf(section);
      final wide = MediaQuery.sizeOf(context).width >= 900;
      return Scaffold(
        appBar: AppBar(
          title: Text('StoreOS · ${_label(section)}'),
          actions: [
            if (section != _Section.status)
              IconButton(
                key: const Key('platform-refresh'),
                tooltip: 'Ansicht aktualisieren',
                onPressed: widget.platform.isBusy
                    ? null
                    : () => _refresh(section),
                icon: const Icon(Icons.refresh),
              ),
            IconButton(
              key: const Key('logout-button'),
              tooltip: 'Abmelden',
              onPressed: widget.session.isBusy ? null : widget.session.signOut,
              icon: const Icon(Icons.logout),
            ),
            const SizedBox(width: StoreSpacing.sm),
          ],
        ),
        body: Row(
          children: [
            if (wide && sections.length >= 2)
              NavigationRail(
                selectedIndex: index,
                extended: MediaQuery.sizeOf(context).width >= 1150,
                onDestinationSelected: (value) => _select(sections[value]),
                destinations: [
                  for (final item in sections)
                    NavigationRailDestination(
                      icon: Icon(_icon(item)),
                      label: Text(_label(item)),
                    ),
                ],
              ),
            Expanded(
              child: Column(
                children: [
                  if (widget.platform.isBusy) const LinearProgressIndicator(),
                  if (widget.platform.error case final error?)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        StoreSpacing.md,
                        StoreSpacing.sm,
                        StoreSpacing.md,
                        0,
                      ),
                      child: StoreStatusPanel(
                        title: 'Anfrage nicht abgeschlossen',
                        message: error,
                        tone: StoreStatusTone.warning,
                      ),
                    ),
                  if (widget.platform.notice case final notice?)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        StoreSpacing.md,
                        StoreSpacing.sm,
                        StoreSpacing.md,
                        0,
                      ),
                      child: StoreStatusPanel(
                        title: 'Änderung bestätigt',
                        message: notice,
                        tone: StoreStatusTone.positive,
                      ),
                    ),
                  if (widget.platform.context == null &&
                      !widget.platform.isBusy)
                    TextButton.icon(
                      onPressed: widget.platform.retryInitial,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Berechtigungen erneut laden'),
                    ),
                  Expanded(child: _body(section)),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide || sections.length < 2
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (value) => _select(sections[value]),
                destinations: [
                  for (final item in sections)
                    NavigationDestination(
                      icon: Icon(_icon(item)),
                      label: _label(item),
                    ),
                ],
              ),
      );
    },
  );
}
