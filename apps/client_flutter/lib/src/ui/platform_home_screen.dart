import '../application/shift_controller.dart';
import 'shift_section.dart';
import 'package:flutter/material.dart';
import 'package:storeos_design_system/storeos_design_system.dart';

import '../application/article_assortment_controller.dart';
import '../application/article_controller.dart';
import '../application/platform_controller.dart';
import '../application/session_controller.dart';
import '../application/stock_controller.dart';
import 'article_section.dart';
import 'assortment_section.dart';
import 'stock_section.dart';
import 'stock_count_section.dart';
import '../application/stock_count_controller.dart';
import 'merchandising_section.dart';
import '../application/merchandising_controller.dart';
import '../application/knowledge_controller.dart';
import 'knowledge_section.dart';
import 'change_password_dialog.dart';
import 'platform_sections.dart';
import 'employee_section.dart';
import 'task_template_section.dart';
import '../application/task_template_controller.dart';
import '../application/employee_controller.dart';
import 'system_status_screen.dart';

enum _Section {
  status,
  organization,
  users,
  audit,
  events,
  plugins,
  people,
  profile,
  templates,
  articles,
  assortment,
  stock,
  merchandising,
  knowledge,
  shifts,
  home,
}

class PlatformHomeScreen extends StatefulWidget {
  const PlatformHomeScreen({
    required this.session,
    required this.platform,
    required this.employees,
    this.templates,
    this.articles,
    this.assortment,
    this.stock,
    this.counts,
    this.ownCounts,
    this.merchandising,
    this.knowledge,
    this.shifts,
    this.home,
    required this.baseUri,
    super.key,
  });

  final SessionController session;
  final PlatformController platform;
  final EmployeeController employees;
  final TaskTemplateController? templates;
  final ArticleController? articles;
  final ArticleAssortmentController? assortment;
  final StockController? stock;
  final StockCountController? counts, ownCounts;
  final MerchandisingController? merchandising;
  final KnowledgeController? knowledge;
  final ShiftController? shifts, home;
  final Uri baseUri;

  @override
  State<PlatformHomeScreen> createState() => _PlatformHomeScreenState();
}

class _PlatformHomeScreenState extends State<PlatformHomeScreen> {
  _Section _selected = _Section.status;

  List<_Section> get _available => [
    _Section.status,
    if (widget.knowledge != null &&
        widget.platform.allows('knowledge.articles.read'))
      _Section.knowledge,
    if (widget.merchandising != null &&
        widget.platform.allows('merchandising.layouts.read'))
      _Section.merchandising,
    if (widget.shifts != null &&
        widget.platform.allows('workforce.shifts.manage'))
      _Section.shifts,
    if (widget.home != null &&
        widget.platform.allows('workforce.shifts.self.read'))
      _Section.home,
    if (widget.templates != null &&
        widget.platform.allows('tasks.templates.manage'))
      _Section.templates,
    if (widget.articles != null &&
        widget.platform.allows('inventory.articles.manage'))
      _Section.articles,
    if (widget.assortment != null &&
        widget.platform.allows('inventory.assortment.manage'))
      _Section.assortment,
    if (widget.stock != null && widget.platform.allows('stock.levels.manage'))
      _Section.stock,
    if (widget.platform.allows('people.self.read')) _Section.profile,
    if (widget.platform.allows('people.manage')) _Section.people,
    if (widget.platform.allows('organization.read')) _Section.organization,
    if (widget.platform.allows('identity.read')) _Section.users,
    if (widget.platform.allows('audit.read')) _Section.audit,
    if (widget.platform.allows('events.read')) _Section.events,
    if (widget.platform.allows('plugins.read')) _Section.plugins,
  ];

  String _label(_Section section) => switch (section) {
    _Section.shifts => 'Schichten',
    _Section.home => 'Meine Arbeit',
    _Section.templates => 'Arbeitsvorlagen',
    _Section.articles => 'Artikel',
    _Section.assortment => 'Sortiment',
    _Section.stock => 'Bestand',
    _Section.merchandising => 'Merchandising',
    _Section.knowledge => 'Wissen',
    _Section.people => 'Mitarbeiter',
    _Section.profile => 'Mein Profil',
    _Section.status => 'Status',
    _Section.organization => 'Organisation',
    _Section.users => 'Benutzer',
    _Section.audit => 'Audit',
    _Section.events => 'Ereignisse',
    _Section.plugins => 'Plugins',
  };

  IconData _icon(_Section section) => switch (section) {
    _Section.shifts => Icons.calendar_month_outlined,
    _Section.home => Icons.assignment_outlined,
    _Section.templates => Icons.checklist_outlined,
    _Section.articles => Icons.inventory_2_outlined,
    _Section.assortment => Icons.storefront_outlined,
    _Section.stock => Icons.warehouse_outlined,
    _Section.merchandising => Icons.view_quilt_outlined,
    _Section.knowledge => Icons.menu_book_outlined,
    _Section.people => Icons.badge_outlined,
    _Section.profile => Icons.person_outline,
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
      case _Section.shifts:
      case _Section.home:
      case _Section.templates:
      case _Section.articles:
      case _Section.assortment:
      case _Section.stock:
      case _Section.merchandising:
      case _Section.knowledge:
      case _Section.people:
      case _Section.profile:
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
      case _Section.shifts:
      case _Section.home:
      case _Section.templates:
      case _Section.articles:
      case _Section.assortment:
      case _Section.stock:
      case _Section.merchandising:
      case _Section.knowledge:
        break;
      case _Section.people:
        widget.employees.loadEmployees();
      case _Section.profile:
        widget.employees.loadSelf();
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
    _Section.shifts => ShiftSection(
      key: const ValueKey('shifts'),
      controller: widget.shifts!,
    ),
    _Section.home => ShiftSection(
      key: const ValueKey('work-home'),
      controller: widget.home!,
      countsShortcut:
          widget.ownCounts != null &&
              widget.platform.allows('stock.counts.self.read')
          ? () => _openCounts(widget.ownCounts!)
          : null,
      knowledgeShortcut:
          widget.knowledge != null &&
              widget.platform.allows('knowledge.articles.read')
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Wissen')),
                  body: KnowledgeSection(controller: widget.knowledge!),
                ),
              ),
            )
          : null,
    ),
    _Section.templates => TaskTemplateSection(controller: widget.templates!),
    _Section.articles => ArticleSection(controller: widget.articles!),
    _Section.assortment => AssortmentSection(
      controller: widget.assortment!,
      platform: widget.platform,
    ),
    _Section.stock => StockSection(
      controller: widget.stock!,
      platform: widget.platform,
      countsShortcut:
          widget.counts != null && widget.platform.allows('stock.counts.manage')
          ? () => _openCounts(widget.counts!)
          : null,
    ),
    _Section.merchandising => MerchandisingSection(
      controller: widget.merchandising!,
    ),
    _Section.knowledge => KnowledgeSection(controller: widget.knowledge!),
    _Section.people => EmployeeSection(
      key: const ValueKey('employees'),
      controller: widget.employees,
      self: false,
    ),
    _Section.profile => EmployeeSection(
      key: const ValueKey('my-employee'),
      controller: widget.employees,
      self: true,
    ),
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

  void _openCounts(StockCountController controller) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Inventurzählungen')),
            body: StockCountSection(controller: controller),
          ),
        ),
      );

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
      final useDrawer = !wide && sections.length > 5;
      return Scaffold(
        drawer: useDrawer
            ? Drawer(
                child: SafeArea(
                  child: ListView(
                    children: [
                      for (final item in sections)
                        ListTile(
                          leading: Icon(_icon(item)),
                          title: Text(_label(item)),
                          selected: item == section,
                          onTap: () {
                            Navigator.of(context).pop();
                            _select(item);
                          },
                        ),
                    ],
                  ),
                ),
              )
            : null,
        appBar: AppBar(
          leading: useDrawer
              ? Builder(
                  builder: (context) => IconButton(
                    key: const Key('open-navigation'),
                    tooltip: 'Navigation öffnen',
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                )
              : null,
          title: Text('StoreOS · ${_label(section)}'),
          actions: [
            if (section != _Section.status &&
                section != _Section.templates &&
                section != _Section.articles &&
                section != _Section.assortment &&
                section != _Section.stock &&
                section != _Section.merchandising &&
                section != _Section.knowledge &&
                section != _Section.shifts &&
                section != _Section.home)
              IconButton(
                key: const Key('platform-refresh'),
                tooltip: 'Ansicht aktualisieren',
                onPressed: widget.platform.isBusy
                    ? null
                    : () => _refresh(section),
                icon: const Icon(Icons.refresh),
              ),
            if (widget.platform.allows('identity.self.password'))
              IconButton(
                key: const Key('change-password-button'),
                tooltip: 'Passwort ändern',
                onPressed: widget.session.isBusy
                    ? null
                    : () => showChangePasswordDialog(context, widget.session),
                icon: const Icon(Icons.password_outlined),
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
        bottomNavigationBar: wide || useDrawer || sections.length < 2
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
