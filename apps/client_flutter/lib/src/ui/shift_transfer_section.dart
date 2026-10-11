import 'dart:convert';
import 'package:flutter/material.dart';
import '../application/shift_transfer_controller.dart';

class ShiftTransferSection extends StatefulWidget {
  const ShiftTransferSection({required this.controller, super.key});
  final ShiftTransferController controller;
  @override
  State<ShiftTransferSection> createState() => _ShiftTransferSectionState();
}

class _ShiftTransferSectionState extends State<ShiftTransferSection> {
  ShiftTransferController get c => widget.controller;
  final reason = TextEditingController();
  Object? identity;
  String? selected;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && c.source == null && c.detail == null) c.load();
    });
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> _act(String action) async {
    final binding = c.sessionIdentity;
    final text = action == 'approve'
        ? 'The original Shift and Tasks will be cancelled. Exact replacement work will be published to the named recipient.'
        : action == 'accept'
        ? 'Your acceptance still requires independent manager approval. The schedule stays unchanged until approval.'
        : action == 'propose'
        ? 'Submit this exact Shift to the named recipient? Acceptance still requires manager approval.'
        : 'Confirm $action?';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm $action'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        !identical(binding, c.sessionIdentity)) {
      return;
    }
    final outcome = action == 'propose'
        ? await c.propose()
        : await c.act(
            action,
            reason: {'withdraw', 'reject'}.contains(action)
                ? reason.text
                : null,
          );
    if (mounted &&
        identical(binding, c.sessionIdentity) &&
        outcome == TransferOutcome.confirmed) {
      reason.clear();
    }
  }

  List<Widget> _work(List tasks) => [
    for (final t in tasks)
      ListTile(
        title: Text('${(t['position'] as int) + 1}. ${t['title']}'),
        subtitle: SelectableText(
          'Template ${t['templateId']} · revision ${t['revisionId']}\n${t['knowledgeGuidance'] == null ? '' : jsonEncode(t['knowledgeGuidance'])}\n${t['planogramGuidance'] == null ? '' : jsonEncode(t['planogramGuidance'])}',
        ),
      ),
  ];
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      if (!identical(identity, c.sessionIdentity)) {
        identity = c.sessionIdentity;
        reason.clear();
        selected = null;
      }
      if (selected != c.detail?.id) {
        selected = c.detail?.id;
        reason.clear();
      }
      final d = c.detail?.json;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            c.self ? 'My shift transfers' : 'Shift transfer review',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null) Text(c.error!, key: const Key('transfer-error')),
          if (c.lastConfirmed != null)
            SelectableText(
              'Confirmed command: ${(c.lastConfirmed!['request'] as Map)['status']} · ${c.confirmedId}',
              key: const Key('transfer-confirmed'),
            ),
          if (c.refreshWarning != null)
            Text(c.refreshWarning!, key: const Key('transfer-refresh-warning')),
          if (c.pending != null)
            FilledButton(
              onPressed: c.busy ? null : c.retry,
              child: const Text('Retry exact command'),
            ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: c.locked ? null : c.load,
                child: const Text('Refresh transfers'),
              ),
              if (c.confirmedId != null)
                TextButton(
                  onPressed: c.locked ? null : () => c.select(c.confirmedId!),
                  child: const Text('Reload current detail'),
                ),
              TextButton(
                onPressed: c.locked ? null : c.closeDetail,
                child: const Text('Close detail'),
              ),
            ],
          ),
          if (c.self)
            Wrap(
              spacing: 8,
              children: [
                for (final direction in [null, 'incoming', 'outgoing'])
                  ChoiceChip(
                    label: Text(direction ?? 'All'),
                    selected: c.direction == direction,
                    onSelected: c.locked
                        ? null
                        : (_) => c.filter(way: direction, state: c.status),
                  ),
              ],
            ),
          Wrap(
            spacing: 8,
            children: [
              for (final status in [
                null,
                'proposed',
                'accepted',
                'approved',
                'declined',
                'withdrawn',
                'rejected',
              ])
                ChoiceChip(
                  label: Text(status ?? 'All states'),
                  selected: c.status == status,
                  onSelected: c.locked
                      ? null
                      : (_) => c.filter(state: status, way: c.direction),
                ),
            ],
          ),
          if (c.source != null) ...[
            Text(
              'Source: ${c.sourceName ?? c.session.user!.username} · recipient: ${c.recipient?['displayName'] ?? 'choose one colleague'}',
            ),
            Text(
              'Exact source Shift ${c.source!.id} · version ${c.source!.version}',
            ),
            Text(
              '${c.source!.draft.startsAt.toIso8601String()} – ${c.source!.draft.endsAt.toIso8601String()}',
            ),
            ..._work(c.sourceTasks),
            const Text(
              'Choose one colleague. Acceptance does not change the schedule until manager approval.',
            ),
            for (final r in c.recipients)
              ListTile(
                key: Key('transfer-recipient-${r['employeeId']}'),
                selected: c.recipient?['employeeId'] == r['employeeId'],
                trailing: c.recipient?['employeeId'] == r['employeeId']
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: c.locked ? null : () => c.chooseRecipient(r),
                title: Text(r['displayName'] as String),
              ),
            if (c.recipientCursor != null)
              TextButton(
                onPressed: c.locked
                    ? null
                    : () => c.chooseSource(c.source!, more: true),
                child: const Text('More recipients'),
              ),
            FilledButton(
              key: const Key('transfer-propose'),
              onPressed: c.locked || c.recipient == null
                  ? null
                  : () => _act('propose'),
              child: const Text('Submit exact proposal'),
            ),
          ],
          for (final r in c.items)
            ListTile(
              key: Key('transfer-${r.id}'),
              title: Text(
                '${r.json['sourceName']} → ${r.json['recipientName']} · ${r.status}',
              ),
              subtitle: Text('${r.json['startsAt']} – ${r.json['endsAt']}'),
              onTap: c.locked ? null : () => c.select(r.id),
            ),
          if (c.nextCursor != null)
            TextButton(
              onPressed: c.locked ? null : () => c.load(more: true),
              child: const Text('More transfers'),
            ),
          if (d != null) ...[
            SelectableText(
              'Transfer ${d['id']} · ${d['status']} · version ${d['version']}',
            ),
            Text('${d['sourceName']} → ${d['recipientName']}'),
            Text('${d['startsAt']} – ${d['endsAt']}'),
            SelectableText(
              'Original Shift ${d['sourceShiftId']} · captured version ${d['sourceVersion']}',
            ),
            ..._work(d['tasks'] as List),
            if (d['nonActionableReason'] != null)
              Text(
                'Currently unavailable: ${d['nonActionableReason']}. Close the request explicitly before proposing again.',
              ),
            if (d['acceptedAt'] != null)
              SelectableText(
                'Accepted ${d['acceptedAt']} by ${d['acceptedBy']}. Manager approval is still required for accepted proposals.',
              ),
            if (d['terminalAt'] != null)
              SelectableText(
                'Decision ${d['terminalAt']} by ${d['terminalBy']}',
              ),
            if (d['terminalReason'] != null)
              SelectableText(d['terminalReason'] as String),
            if (d['replacementShiftId'] != null)
              SelectableText('Replacement Shift ${d['replacementShiftId']}'),
            for (final link in d['taskLinks'] as List)
              SelectableText(
                'Task ${link['sourceTaskId']} → ${link['replacementTaskId']} · revision ${link['revisionId']}',
              ),
            if (c.can('withdraw') || c.can('reject'))
              TextField(
                key: const Key('transfer-reason'),
                controller: reason,
                enabled: !c.locked,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Reason for withdrawal or rejection',
                ),
              ),
            Wrap(
              spacing: 12,
              children: [
                for (final action
                    in c.self
                        ? ['accept', 'decline', 'withdraw']
                        : ['approve', 'reject'])
                  FilledButton(
                    key: Key('transfer-$action'),
                    onPressed: c.can(action) ? () => _act(action) : null,
                    child: Text(action),
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );
}
