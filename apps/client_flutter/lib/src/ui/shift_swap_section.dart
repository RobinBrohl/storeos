import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../application/shift_swap_controller.dart';

class ShiftSwapSection extends StatefulWidget {
  const ShiftSwapSection({required this.controller, super.key});
  final ShiftSwapController controller;

  @override
  State<ShiftSwapSection> createState() => _ShiftSwapSectionState();
}

class _ShiftSwapSectionState extends State<ShiftSwapSection> {
  ShiftSwapController get c => widget.controller;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    final basis = _Identity(c);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !basis.current) return;
      if (c.source != null) {
        c.loadSourceWork();
      } else if (c.detail == null && !c.locked) {
        c.load();
      }
    });
  }

  Future<void> _act(String action) async {
    if (_dialogOpen || c.locked || !c.canRead) return;
    setState(() => _dialogOpen = true);
    final identity = _Identity(c);
    try {
      // Manager decisions always review a fresh authorized projection.
      if (!c.self) {
        final id = (c.detail?.json['request'] as Map?)?['id'] as String?;
        if (id == null) return;
        await c.select(id);
        if (!mounted ||
            !identity.current ||
            (c.detail?.json['request'] as Map?)?['id'] != id) {
          return;
        }
      }
      final detail = c.detail,
          source = c.source,
          colleague = c.colleague,
          counterpart = c.selectedCounterpart,
          work = c.sourceWork;
      bool valid() =>
          mounted &&
          identity.current &&
          !c.locked &&
          identical(detail, c.detail) &&
          identical(source, c.source) &&
          identical(colleague, c.colleague) &&
          identical(counterpart, c.selectedCounterpart) &&
          identical(work, c.sourceWork);
      if (!valid() || !_can(action)) return;
      final request = detail?.json['request'] as Map?;
      final reason = {'withdraw', 'reject'}.contains(action);
      final answer = await showDialog<String>(
        context: context,
        builder: (_) => _SwapConfirmation(
          controller: c,
          valid: valid,
          title: _actionLabel(action),
          needsReason: reason,
          children: [
            Text(_explanation(action)),
            if (source != null) ..._sourceReview(c),
            if (request != null) ..._requestReview(request),
            if (action == 'offer' && counterpart != null)
              _leg(counterpart.json, request!, proposed: true),
          ],
        ),
      );
      if (!mounted || answer == null || !valid() || !_can(action)) return;
      final outcome = action == 'request'
          ? await c.request()
          : await c.act(action, reason: reason ? answer : null);
      if (!mounted || !identity.current) return;
      // Pending/receipt/error evidence belongs to the controller. Outcomes never
      // trigger an automatic retry or erase an unresolved earlier submission.
      switch (outcome) {
        case SwapOutcome.confirmed:
        case SwapOutcome.rejected:
        case SwapOutcome.uncertain:
        case SwapOutcome.reconciliationRequired:
        case SwapOutcome.fenced:
        case SwapOutcome.busy:
          break;
      }
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  bool _can(String action) => switch (action) {
    'request' => c.canRequest && c.sourceWork.isNotEmpty,
    'withdraw' => c.can('source_withdraw') || c.can('recipient_withdraw'),
    'approve' || 'reject' => c.can('manager_$action'),
    _ => c.can(action),
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      if (!c.canRead) {
        return const Center(child: Text('Kein Zugriff auf Schichttausch.'));
      }
      final detail = c.detail?.json, request = detail?['request'] as Map?;
      final blocked = c.locked || _dialogOpen;
      final confirmed = c.lastConfirmed;
      return ListView(
        key: const Key('swap-scroll'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            c.self ? 'Meine Schichttausche' : 'Schichttausch prüfen',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Alle Zeiten in UTC. Tausch erst nach unabhängiger Freigabe.',
          ),
          if (c.busy) const LinearProgressIndicator(key: Key('swap-loading')),
          if (c.error != null)
            SelectableText(c.error!, key: const Key('swap-error')),
          if (confirmed != null) ...[
            SelectableText(
              'Befehl bestätigt · ${_state(confirmed.request.json['status'] as String)} · Version ${confirmed.json['acceptedVersion']}\nOriginalbeleg ${confirmed.json['operationId']}${confirmed.json['replayed'] == true ? ' · Wiederholung bestätigt' : ''}',
              key: const Key('swap-confirmed'),
            ),
            const Text(
              'Der Originalbeleg dokumentiert die Annahme. Aktuelle Aktionen benötigen frisch autorisierte Details.',
            ),
            ExpansionTile(
              key: const Key('swap-receipt'),
              title: const Text('Bestätigten Originalbeleg ansehen'),
              children: _requestReview(confirmed.request.json),
            ),
          ],
          if (c.refreshWarning != null) ...[
            const Text(
              'Aktuelle Details fehlen. Vor weiteren Aktionen erneut laden.',
            ),
            SelectableText(
              c.refreshWarning!,
              key: const Key('swap-refresh-warning'),
            ),
          ],
          if (c.pending != null) ...[
            Text(
              c.pending!.state == SwapSubmission.submitting
                  ? 'Übermittlung läuft. Der Server kann den Befehl bereits ausgeführt haben.'
                  : 'Ausgang ungewiss. Der Server kann den Befehl bereits ausgeführt haben. Ein fehlender Beleg beweist keine Rücknahme. Neue Befehle bleiben gesperrt.',
              key: const Key('swap-uncertain'),
            ),
            SelectableText(
              'Originalauftrag ${c.pending!.requestId} · ${c.pending!.operationId}',
            ),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  key: const Key('swap-retry'),
                  onPressed: c.busy || _dialogOpen ? null : c.retry,
                  child: const Text('Exakt denselben Befehl wiederholen'),
                ),
                OutlinedButton(
                  key: const Key('swap-reconcile'),
                  onPressed: c.busy || _dialogOpen ? null : c.reconcile,
                  child: const Text('Originalbeleg abgleichen'),
                ),
              ],
            ),
          ],
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                key: const Key('swap-refresh'),
                onPressed: blocked ? null : c.load,
                child: const Text('Tausche aktualisieren'),
              ),
              if (request != null || confirmed != null)
                TextButton(
                  key: const Key('swap-reload-detail'),
                  onPressed: blocked
                      ? null
                      : () => c.select(
                          (request ?? confirmed!.request.json)['id'] as String,
                        ),
                  child: const Text('Aktuelle Details laden'),
                ),
            ],
          ),
          if (c.self)
            Wrap(
              spacing: 8,
              children: [
                for (final way in [null, 'incoming', 'outgoing'])
                  ChoiceChip(
                    key: Key('swap-direction-${way ?? 'all'}'),
                    label: Text(switch (way) {
                      'incoming' => 'Einladungen',
                      'outgoing' => 'Eigene Anfragen',
                      _ => 'Alle Richtungen',
                    }),
                    selected: c.direction == way,
                    onSelected: blocked
                        ? null
                        : (_) => c.filter(state: c.status, way: way),
                  ),
              ],
            ),
          Wrap(
            spacing: 8,
            children: [
              for (final state in [null, ...shiftSwapStates])
                ChoiceChip(
                  key: Key('swap-status-${state ?? 'all'}'),
                  label: Text(state == null ? 'Alle Zustände' : _state(state)),
                  selected: c.status == state,
                  onSelected: blocked
                      ? null
                      : (_) => c.filter(state: state, way: c.direction),
                ),
            ],
          ),
          if (c.source != null) ...[
            ..._sourceReview(c),
            const Text('Nur vom Server freigegebene Kolleginnen und Kollegen:'),
            if (!c.busy && c.colleagues.isEmpty)
              const Text('Keine freigegebenen Kontakte.'),
            for (final colleague in c.colleagues)
              ListTile(
                key: Key('swap-colleague-${colleague['employeeId']}'),
                title: Text(colleague['displayName'] as String),
                selected: c.colleague?['employeeId'] == colleague['employeeId'],
                trailing: c.colleague?['employeeId'] == colleague['employeeId']
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: blocked
                    ? null
                    : () =>
                          c.chooseColleague(colleague['employeeId'] as String),
              ),
            if (c.colleagueCursor != null)
              TextButton(
                onPressed: blocked
                    ? null
                    : () => c.chooseSource(c.source!, more: true),
                child: const Text('Weitere Kontakte'),
              ),
            if (c.sourceWork.isEmpty && !c.busy)
              TextButton(
                key: const Key('swap-source-retry'),
                onPressed: blocked ? null : c.loadSourceWork,
                child: const Text('Eigene Arbeitsnachweise laden'),
              ),
            FilledButton(
              key: const Key('swap-request'),
              onPressed: blocked || !_can('request')
                  ? null
                  : () => _act('request'),
              child: const Text('Einladung senden'),
            ),
          ],
          if (!c.busy && c.items.isEmpty)
            const Text(
              'Keine Tauschanfragen in dieser Auswahl.',
              key: Key('swap-empty'),
            ),
          for (final item in c.items)
            ListTile(
              key: Key('swap-${item.json['id']}'),
              title: Text(
                '${item.json['sourceName']} ↔ ${item.json['recipientName']}',
              ),
              subtitle: Text(
                '${_state(item.json['status'] as String)} · Version ${item.json['version']}\n${(item.json['legs'] as List).map((l) => '${l['startsAt']} – ${l['endsAt']} UTC').join('\n')}',
              ),
              onTap: blocked ? null : () => c.select(item.json['id'] as String),
            ),
          if (c.nextCursor != null)
            TextButton(
              key: const Key('swap-more'),
              onPressed: blocked ? null : () => c.load(more: true),
              child: const Text('Weitere Tausche'),
            ),
          if (request != null) ...[
            const Divider(),
            const Text('Aktuell autorisierter Stand'),
            ..._requestReview(request),
            Text(
              detail!['actionable'] == true
                  ? 'Aktuell fortsetzbar (Server prüft erneut).'
                  : 'Aktuell nicht fortsetzbar: ${detail['nonActionableReason'] ?? 'Abgeschlossen'}',
            ),
            if (c.self &&
                detail['participantRole'] == 'recipient' &&
                request['status'] == 'requested' &&
                (detail['availableActions'] as List).contains('offer')) ...[
              TextButton(
                key: const Key('swap-counterparts'),
                onPressed: blocked || detail['actionable'] != true
                    ? null
                    : c.loadCounterparts,
                child: const Text('Eigene Gegenschichten laden'),
              ),
              for (final candidate in c.counterparts)
                ListTile(
                  key: Key('swap-counterpart-${candidate['shiftId']}'),
                  title: Text(
                    '${candidate['startsAt']} – ${candidate['endsAt']} UTC',
                  ),
                  subtitle: Text(
                    'Eigene Schicht ${candidate['shiftId']} · Version ${candidate['version']}',
                  ),
                  selected: c.counterpart?['shiftId'] == candidate['shiftId'],
                  onTap: blocked
                      ? null
                      : () =>
                            c.chooseCounterpart(candidate['shiftId'] as String),
                ),
              if (c.counterpartCursor != null)
                TextButton(
                  onPressed: blocked
                      ? null
                      : () => c.loadCounterparts(more: true),
                  child: const Text('Weitere eigene Gegenschichten'),
                ),
              if (c.selectedCounterpart != null)
                _leg(c.selectedCounterpart!.json, request, proposed: true),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final action
                    in c.self
                        ? ['offer', 'confirm', 'decline', 'withdraw']
                        : ['approve', 'reject'])
                  if (_can(action))
                    FilledButton(
                      key: Key('swap-$action'),
                      onPressed: blocked ? null : () => _act(action),
                      child: Text(_actionLabel(action)),
                    ),
              ],
            ),
            TextButton(
              key: const Key('swap-history'),
              onPressed: blocked
                  ? null
                  : () => c.loadHistory(request['id'] as String),
              child: const Text('Verlauf und Originalbelege laden'),
            ),
            for (final receipt in c.history)
              ExpansionTile(
                key: Key('swap-history-${receipt.json['operationId']}'),
                title: Text(
                  '${receipt.json['kind']} · Version ${receipt.json['acceptedVersion']}',
                ),
                subtitle: Text('Originalbeleg ${receipt.json['operationId']}'),
                children: _requestReview(receipt.request.json),
              ),
            if (c.historyCursor != null)
              TextButton(
                key: const Key('swap-history-more'),
                onPressed: blocked
                    ? null
                    : () => c.loadHistory(request['id'] as String, more: true),
                child: const Text('Weitere Originalbelege'),
              ),
          ],
        ],
      );
    },
  );
}

/// Account equality cannot identify an authorization lifetime.
class _Identity {
  _Identity(this.c)
    : session = c.sessionIdentity,
      context = c.platform.contextIdentity;
  final ShiftSwapController c;
  final Object? session;
  final Object context;
  bool get current =>
      c.canRead &&
      identical(session, c.sessionIdentity) &&
      identical(session, c.session.sessionIdentity) &&
      identical(context, c.platform.contextIdentity);
}

class _SwapConfirmation extends StatefulWidget {
  const _SwapConfirmation({
    required this.controller,
    required this.valid,
    required this.title,
    required this.children,
    required this.needsReason,
  });
  final ShiftSwapController controller;
  final bool Function() valid;
  final String title;
  final List<Widget> children;
  final bool needsReason;
  @override
  State<_SwapConfirmation> createState() => _SwapConfirmationState();
}

class _SwapConfirmationState extends State<_SwapConfirmation> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _closing = false;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (!widget.valid()) {
        _reason.clear();
        if (!_closing) {
          _closing = true;
          final route = ModalRoute.of(context)!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && route.isActive) {
              Navigator.of(context).removeRoute(route);
            }
          });
        }
        return const SizedBox.shrink();
      }
      return AlertDialog(
        title: Text(widget.title),
        scrollable: true,
        content: SizedBox(
          width: 680,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...widget.children,
                if (widget.needsReason)
                  TextFormField(
                    key: const Key('swap-reason'),
                    controller: _reason,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText:
                          'Begründung (1–500 Unicode-Zeichen nach Kürzung)',
                    ),
                    validator: (value) {
                      try {
                        transferReason(value);
                        return null;
                      } on TransferInputException {
                        return 'Begründung mit 1–500 Zeichen ohne Steuerzeichen eingeben.';
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('swap-cancel'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('swap-dialog-confirm'),
            onPressed: () {
              if (!widget.valid() ||
                  _closing ||
                  !_form.currentState!.validate()) {
                return;
              }
              _closing = true;
              Navigator.pop(
                context,
                widget.needsReason ? transferReason(_reason.text) : '',
              );
            },
            child: const Text('Verbindlich bestätigen'),
          ),
        ],
      );
    },
  );
}

List<Widget> _sourceReview(ShiftSwapController c) => [
  Text('Eigene Ausgangsschicht · ${c.session.user?.username ?? ''}'),
  SelectableText(
    '${c.source!.id} · Version ${c.source!.version}\n${c.source!.draft.startsAt.toIso8601String()} – ${c.source!.draft.endsAt.toIso8601String()} UTC',
  ),
  for (final task in c.sourceWork)
    ..._task({
      'id': task.id,
      'templateId': task.templateId,
      'revisionId': task.revisionId,
      'position': task.position,
      'title': task.title,
      'knowledgeGuidance': task.content?.knowledgeGuidance?.toJson(),
      'planogramGuidance': task.content?.planogramGuidance?.toJson(),
    }),
  if (c.colleague != null) Text('Einladung an ${c.colleague!['displayName']}'),
];

List<Widget> _requestReview(Map r) => [
  SelectableText(
    'Tausch ${r['id']} · ${_state(r['status'] as String)} · Version ${r['version']}',
  ),
  Text('${r['sourceName']} ↔ ${r['recipientName']}'),
  for (final leg in r['legs'] as List) _leg(leg as Map, r),
  SelectableText(
    'Anfrage ${r['requestedAt']} UTC · ${r['requestOperationId']}',
  ),
  if (r['offeredAt'] != null)
    SelectableText('Angebot ${r['offeredAt']} UTC · ${r['offerOperationId']}'),
  if (r['confirmedAt'] != null)
    SelectableText(
      'Paarbestätigung ${r['confirmedAt']} UTC · ${r['confirmationOperationId']}',
    ),
  if (r['terminalAt'] != null)
    SelectableText(
      'Entscheidung ${r['terminalKind']} · ${r['terminalAt']} UTC · ${r['terminalOperationId']}',
    ),
  if (r['terminalReason'] != null)
    SelectableText(r['terminalReason'] as String),
];

Widget _leg(Map l, Map r, {bool proposed = false}) {
  final a = l['leg'] == 'a',
      owner = r[a ? 'sourceName' : 'recipientName'],
      incoming = r[a ? 'recipientName' : 'sourceName'];
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${a ? 'A' : 'B'} · Originalarbeit von $owner${proposed ? ' · gewählte Gegenschicht' : ''}',
          ),
          Text('Nach Freigabe übernimmt $incoming diese Arbeit.'),
          SelectableText(
            'Originalschicht ${l['sourceShiftId']} · erfasste Version ${l['sourceVersion']}',
          ),
          Text('${l['startsAt']} – ${l['endsAt']} UTC'),
          for (final task in l['tasks'] as List) ..._task(task as Map),
          if (l['replacementShiftId'] != null)
            SelectableText(
              'Veröffentlichte Ersatzschicht ${l['replacementShiftId']}',
            ),
          for (final link in l['taskLinks'] as List)
            SelectableText(
              'Aufgabe ${link['sourceTaskId']} → ${link['replacementTaskId']}\nSchicht ${link['sourceShiftId']} → ${link['replacementShiftId']} · Vorlage ${link['templateId']} / ${link['revisionId']} · Position ${link['position']}',
            ),
        ],
      ),
    ),
  );
}

List<Widget> _task(Map t) => [
  Text('${(t['position'] as int) + 1}. ${t['title']}'),
  SelectableText(
    'Aufgabe ${t['id']} · Vorlage ${t['templateId']} · Revision ${t['revisionId']}',
  ),
  if (t['knowledgeGuidance'] case final Map pin)
    SelectableText(
      'Wissen · Artikel ${pin['articleId']} · Revision ${pin['revisionId']}',
    ),
  if (t['planogramGuidance'] case final Map pin)
    SelectableText(
      'Planogramm · Einrichtung ${pin['fixtureId']} · Zuweisung ${pin['assignmentId']} · Revision ${pin['revisionId']}',
    ),
];

String _state(String s) => switch (s) {
  'requested' => 'Angefragt',
  'offered' => 'Gegenschicht angeboten',
  'confirmed' => 'Paar bestätigt',
  'approved' => 'Freigegeben',
  'declined' => 'Abgelehnt',
  'withdrawn' => 'Zurückgezogen',
  'rejected' => 'Durch Leitung abgelehnt',
  _ => s,
};
String _actionLabel(String a) => switch (a) {
  'request' => 'Einladung senden',
  'offer' => 'Genau diese Gegenschicht anbieten',
  'confirm' => 'Genau dieses Paar bestätigen',
  'approve' => 'Beide Schichten freigeben',
  'reject' => 'Tausch mit Begründung ablehnen',
  'withdraw' => 'Tausch mit Begründung zurückziehen',
  'decline' => 'Einladung / Angebot ablehnen',
  _ => a,
};
String _explanation(String a) => switch (a) {
  'request' =>
    'Diese Einladung ändert den Dienstplan noch nicht. Die Gegenschicht wird erst von der eingeladenen Person angeboten.',
  'offer' =>
    'Sie bieten genau diese eigene Gegenschicht zur Originalarbeit von A an. A muss das Paar bestätigen. Der Dienstplan bleibt bis zur unabhängigen Freigabe unverändert.',
  'confirm' =>
    'Sie bestätigen das gespeicherte Paar: Ihre Originalarbeit geht an B; die Originalarbeit von B kommt zu Ihnen. Erst die unabhängige Leitung gibt den Tausch frei.',
  'approve' =>
    'Mit Freigabe werden beide Originalschichten samt Aufgaben gemeinsam storniert und beide exakten Ersatzschichten veröffentlicht. Der Server prüft Ihre unabhängige Berechtigung erneut.',
  _ =>
    'Der Tausch wird ohne Dienstplanänderung abgeschlossen. Bisherige Angebote, Bestätigungen und Nachweise bleiben erhalten.',
};
