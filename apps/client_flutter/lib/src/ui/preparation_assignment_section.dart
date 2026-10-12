import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../application/preparation_assignment_controller.dart';
import '../application/preparation_batch_controller.dart';
import 'preparation_batch_section.dart';

class PreparationAssignmentSection extends StatefulWidget {
  const PreparationAssignmentSection({
    required this.controller,
    required this.batches,
    super.key,
  });
  final PreparationAssignmentController controller;
  final PreparationBatchController batches;
  @override
  State<PreparationAssignmentSection> createState() =>
      _PreparationAssignmentSectionState();
}

class _PreparationAssignmentSectionState
    extends State<PreparationAssignmentSection> {
  PreparationAssignmentController get c => widget.controller;
  final planned = TextEditingController(), reason = TextEditingController();
  Object? identity;
  String? localError;
  BuildContext? dialogContext;
  @override
  void initState() {
    super.initState();
    identity = c.sessionIdentity;
    c.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.load();
    });
  }

  void _changed() {
    if (!identical(identity, c.sessionIdentity)) {
      identity = c.sessionIdentity;
      planned.clear();
      reason.clear();
      localError = null;
      final dialog = dialogContext;
      dialogContext = null;
      if (dialog != null && dialog.mounted) {
        Navigator.of(dialog).pop(false);
      }
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    planned.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> _act(Future<AssignmentOutcome> Function() work) async {
    final binding = c.sessionIdentity;
    try {
      final outcome = await work();
      if (mounted && identical(binding, c.sessionIdentity)) {
        setState(() {
          localError = null;
          if (outcome == AssignmentOutcome.confirmed) {
            planned.clear();
            reason.clear();
          }
        });
      }
    } on FormatException catch (e) {
      if (mounted && identical(binding, c.sessionIdentity)) {
        setState(() => localError = e.message);
      }
    }
  }

  Future<void> _create() async {
    final binding = c.sessionIdentity;
    try {
      if (!RegExp(r'^[0-9]{1,4}$').hasMatch(planned.text.trim())) {
        throw const FormatException(
          'Enter 1–9999 whole declared Recipe batches.',
        );
      }
      final count = declaredBatchCount(int.parse(planned.text.trim())),
          recipe = c.selection,
          employee = c.employeeSelection;
      if (recipe == null || employee == null || c.locked) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          dialogContext = context;
          return AlertDialog(
            title: const Text('Confirm preparation assignment'),
            content: Text(
              '${employee['displayName']}\n${recipe.content.produced.name}\nExact revision ${recipe.revisionNumber}\nRequested: $count declared Recipe batches',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Back'),
              ),
              FilledButton(
                key: const Key('assignment-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create assignment'),
              ),
            ],
          );
        },
      );
      dialogContext = null;
      if (confirmed == true &&
          mounted &&
          identical(binding, c.sessionIdentity) &&
          identical(recipe, c.selection) &&
          identical(employee, c.employeeSelection) &&
          !c.locked) {
        await _act(() => c.create(count));
      }
    } on FormatException catch (e) {
      if (mounted && identical(binding, c.sessionIdentity)) {
        setState(() => localError = e.message);
      }
    }
  }

  Widget _recipe(RecipeContent content, int number) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Exact approved Recipe revision $number'),
          SelectableText('${content.produced.sku} · ${content.produced.name}'),
          SelectableText(
            'One declared Recipe batch: ${content.batchDescription}',
          ),
          SelectableText(content.preparation),
          for (final i in content.ingredients)
            SelectableText(
              '${i.article.sku} · ${i.article.name} · ${i.quantity} ${i.article.unit}',
            ),
        ],
      ),
    ),
  );
  Future<void> _openBatch(String id) async {
    final binding = c.sessionIdentity;
    await widget.batches.select(id);
    if (!mounted ||
        !identical(binding, c.sessionIdentity) ||
        widget.batches.detail?.id != id) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Assigned preparation Batch')),
          body: PreparationBatchSection(controller: widget.batches),
        ),
      ),
    );
    if (mounted && identical(binding, c.sessionIdentity) && c.detail != null) {
      await c.select(c.detail!.id);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final a = c.detail;
      final batch = a?.json['batch'] as Map?;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            c.self ? 'My preparation assignments' : 'Preparation assignments',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Requested whole declared Recipe batches. Actual execution is recorded by the linked Batch. No Stock effect.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null) Text(c.error!),
          if (localError != null) Text(localError!),
          if (c.notice != null) Text(c.notice!),
          if (c.lastConfirmed != null)
            Text(
              'Accepted ${c.pending?.kind ?? 'command'} · assignment ${c.confirmedId}${(c.lastConfirmed!['batch'] as Map?)?['batchId'] == null ? '' : ' · Batch ${(c.lastConfirmed!['batch'] as Map)['batchId']}'}',
            ),
          if (c.refreshWarning != null) Text(c.refreshWarning!),
          if (a == null && c.confirmedId != null)
            TextButton(
              onPressed: c.locked ? null : () => c.select(c.confirmedId!),
              child: const Text('Reload authoritative assignment detail'),
            ),
          if (c.pending != null)
            FilledButton(
              key: const Key('assignment-retry'),
              onPressed: c.busy ? null : () => _act(c.retry),
              child: const Text('Retry exact command'),
            ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: c.locked ? null : () => c.load(),
                child: const Text('Refresh assignments'),
              ),
              DropdownButton<String>(
                value: c.status ?? 'all',
                items: [
                  for (final s in ['all', 'assigned', 'started', 'withdrawn'])
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: c.locked
                    ? null
                    : (s) => c.filter(s == 'all' ? null : s),
              ),
              if (!c.self && c.canExecute)
                TextButton(
                  key: const Key('assignment-choose-recipe'),
                  onPressed: c.locked ? null : () => c.choices(),
                  child: const Text('Select approved Recipe'),
                ),
              if (!c.self && c.canExecute)
                TextButton(
                  key: const Key('assignment-choose-employee'),
                  onPressed: c.locked ? null : () => c.assignees(),
                  child: const Text('Select eligible Employee'),
                ),
            ],
          ),
          for (final item in c.items)
            ListTile(
              key: Key('assignment-${item.id}'),
              title: Text('${item.status} · ${item.id}'),
              subtitle: Text(
                'Requested ${item.planned} · Employee ${item.json['employeeId']}',
              ),
              onTap: c.locked ? null : () => c.select(item.id),
            ),
          if (c.nextCursor != null)
            TextButton(
              onPressed: c.locked ? null : () => c.load(more: true),
              child: const Text('More assignments'),
            ),
          for (final r in c.recipes)
            ListTile(
              key: Key('assignment-recipe-${r.recipe}'),
              title: Text(r.content.produced.name),
              subtitle: Text('Revision ${r.revisionNumber}'),
              onTap: c.locked ? null : () => c.choose(r),
            ),
          if (c.recipeCursor != null)
            TextButton(
              onPressed: c.locked ? null : () => c.choices(more: true),
              child: const Text('More Recipes'),
            ),
          for (final e in c.employees)
            ListTile(
              key: Key('assignment-employee-${e['id']}'),
              title: Text(e['displayName'] as String),
              onTap: c.locked ? null : () => c.chooseEmployee(e),
            ),
          if (c.employeeCursor != null)
            TextButton(
              onPressed: c.locked ? null : () => c.assignees(more: true),
              child: const Text('More Employees'),
            ),
          if (c.selection case final r?) ...[
            _recipe(r.content, r.revisionNumber),
            if (c.employeeSelection != null)
              Text('Assigned Employee: ${c.employeeSelection!['displayName']}'),
            TextField(
              key: const Key('assignment-planned'),
              controller: planned,
              enabled: !c.locked,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Requested declared Recipe batches (1–9999)',
              ),
            ),
            FilledButton(
              key: const Key('assignment-create'),
              onPressed: c.locked || c.employeeSelection == null
                  ? null
                  : _create,
              child: const Text('Review assignment'),
            ),
          ],
          if (a != null) ...[
            SelectableText(
              'Assignment ${a.id} · ${a.status} · version ${a.version}',
            ),
            SelectableText('Exact assigned revision: ${a.json['revisionId']}'),
            Text('Requested: ${a.planned} declared Recipe batches'),
            TextButton(
              key: const Key('assignment-read-recipe'),
              onPressed: c.locked ? null : c.readInstruction,
              child: const Text('Read exact assigned Recipe'),
            ),
            TextButton(
              key: const Key('assignment-history'),
              onPressed: c.locked ? null : c.readHistory,
              child: const Text('Read assignment history'),
            ),
            if (a.status == 'assigned' && c.self && c.canExecute)
              FilledButton(
                key: const Key('assignment-start'),
                onPressed: c.locked ? null : () => _act(c.start),
                child: const Text('Start preparation'),
              ),
            if (a.status == 'assigned' && !c.self && c.canExecute) ...[
              TextField(
                key: const Key('assignment-reason'),
                controller: reason,
                enabled: !c.locked,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Withdrawal reason',
                ),
              ),
              TextButton(
                key: const Key('assignment-withdraw'),
                onPressed: c.locked
                    ? null
                    : () => _act(() => c.withdraw(reason.text)),
                child: const Text('Withdraw unstarted assignment'),
              ),
            ],
            if (a.status == 'withdrawn')
              SelectableText('Withdrawn: ${a.json['withdrawalReason']}'),
            if (batch != null) ...[
              Text('Linked Batch outcome: ${batch['status']}'),
              Text(
                'Original completed declaration: ${batch['actualDeclaredBatchCount'] ?? '—'}',
              ),
              Text(
                'Effective corrected count: ${batch['effectiveDeclaredBatchCount'] ?? '—'}',
              ),
              for (final correction in batch['corrections'] as List)
                SelectableText(
                  'Correction ${(correction as Map)['correctionNumber']}: ${correction['previousEffectiveCount']} → ${correction['replacementDeclaredBatchCount']} · ${correction['reason']}',
                ),
              FilledButton(
                key: const Key('assignment-open-batch'),
                onPressed: c.locked ? null : () => _openBatch(a.batchId!),
                child: const Text('Open linked Batch'),
              ),
            ],
          ],
          if (c.instruction case final j?) ...[
            _recipe(
              RecipeContent.fromJson(
                Map<String, dynamic>.from(j['content'] as Map),
              ),
              j['revisionNumber'] as int,
            ),
            for (final warning in j['warnings'] as List)
              Text('Current eligibility: $warning'),
          ],
          if (c.history case final h?)
            SelectableText(
              'Created by ${(h['assignment'] as Map)['createdBy']} at ${(h['assignment'] as Map)['createdAt']}\nStarted by ${(h['assignment'] as Map)['startedBy'] ?? '—'} at ${(h['assignment'] as Map)['startedAt'] ?? '—'}\nWithdrawn by ${(h['assignment'] as Map)['withdrawnBy'] ?? '—'} at ${(h['assignment'] as Map)['withdrawnAt'] ?? '—'}',
            ),
        ],
      );
    },
  );
}
