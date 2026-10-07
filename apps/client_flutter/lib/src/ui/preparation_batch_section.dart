import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../application/preparation_batch_controller.dart';

class PreparationBatchSection extends StatefulWidget {
  const PreparationBatchSection({required this.controller, super.key});
  final PreparationBatchController controller;
  @override
  State<PreparationBatchSection> createState() =>
      _PreparationBatchSectionState();
}

class _PreparationBatchSectionState extends State<PreparationBatchSection> {
  PreparationBatchController get c => widget.controller;
  final planned = TextEditingController(),
      actual = TextEditingController(),
      note = TextEditingController(),
      reason = TextEditingController(),
      replacement = TextEditingController();
  Object? identity;
  String? selected;
  String? localError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.load();
    });
  }

  @override
  void dispose() {
    for (final input in [planned, actual, note, reason, replacement]) {
      input.dispose();
    }
    super.dispose();
  }

  void _clear() {
    for (final input in [planned, actual, note, reason, replacement]) {
      input.clear();
    }
    localError = null;
  }

  int _count(TextEditingController field, {bool correction = false}) {
    if (!RegExp(r'^[0-9]{1,4}$').hasMatch(field.text.trim())) {
      throw const FormatException(
        'Enter a whole number of declared Recipe batches.',
      );
    }
    return declaredBatchCount(
      int.parse(field.text.trim()),
      correction: correction,
    );
  }

  Future<void> _act(Future<PreparationOutcome> Function() action) async {
    final binding = c.sessionIdentity;
    try {
      final outcome = await action();
      if (mounted && identical(binding, c.sessionIdentity)) {
        setState(() {
          localError = null;
          if (outcome == PreparationOutcome.confirmed) _clear();
        });
      }
    } on FormatException catch (e) {
      if (mounted && identical(binding, c.sessionIdentity)) {
        setState(() => localError = e.message);
      }
    }
  }

  Widget _field(
    String key,
    String label,
    TextEditingController field, {
    bool numeric = false,
  }) => TextField(
    key: Key(key),
    controller: field,
    enabled: !c.locked,
    keyboardType: numeric ? TextInputType.number : TextInputType.text,
    maxLength: numeric ? null : 500,
    decoration: InputDecoration(labelText: label),
  );
  Widget _instruction(RecipeContent content, int number) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Exact approved Recipe revision $number'),
          SelectableText('${content.produced.sku} · ${content.produced.name}'),
          const Text('Ingredients for one declared Recipe batch'),
          SelectableText(content.batchDescription),
          for (final i in content.ingredients)
            SelectableText(
              '${i.position}. ${i.article.sku} · ${i.article.name} · ${i.quantity} ${i.article.unit}',
            ),
          SelectableText(content.preparation),
        ],
      ),
    ),
  );
  Widget _confirmation(Map<String, dynamic> result) {
    final batch = result['batch'] as Map<String, dynamic>?;
    final correction = result['correction'] as Map<String, dynamic>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Confirmed command result (immutable evidence)'),
        if (correction != null) ...[
          Text(
            'Correction ${correction['correctionNumber']} confirmed: ${correction['previousEffectiveCount']} → ${correction['replacementDeclaredBatchCount']} declared Recipe batches',
          ),
          Text(
            'Confirmed original completion: ${c.confirmedOriginalCount} declared Recipe batches',
          ),
          if (correction['replacementDeclaredBatchCount'] == 0)
            const Text(
              'Reported completion corrected to 0 declared Recipe batches. Lifecycle remains completed.',
            ),
          SelectableText(
            '${correction['correctedAt']} · ${correction['correctedBy']}',
          ),
        ],
        if (batch != null) ...[
          if (c.lastConfirmedKind == 'complete')
            Text(
              'Completion confirmed: ${batch['actualDeclaredBatchCount']} declared Recipe batches',
            ),
          if (c.lastConfirmedKind == 'open') const Text('Opening confirmed.'),
          if (c.lastConfirmedKind == 'employee_cancel' ||
              c.lastConfirmedKind == 'manager_cancel')
            const Text('Cancellation confirmed.'),
          Text('${batch['status']} · version ${batch['version']}'),
          SelectableText(
            '${batch['completedAt'] ?? batch['cancelledAt'] ?? batch['openedAt']} · ${batch['completedBy'] ?? batch['cancelledBy'] ?? batch['openedBy']}',
          ),
        ],
      ],
    );
  }

  Future<bool> _confirmCorrection(int count) async {
    final binding = c.sessionIdentity;
    final b = c.detail!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final valid =
              identical(binding, c.sessionIdentity) &&
              c.detail?.id == b.id &&
              c.detail?.version == b.version &&
              c.detail?.latestCorrectionNumber == b.latestCorrectionNumber;
          return AlertDialog(
            title: const Text('Correct reported completion'),
            content: valid
                ? Text(
                    'Original: ${b.actual} declared Recipe batches\nCurrent effective: ${b.effective}\nReplacement: $count\nReason: ${reason.text}\nOriginal completion remains immutable.',
                  )
                : const Text('Session changed. Reload server evidence.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Back'),
              ),
              FilledButton(
                key: const Key('batch-confirm-correction'),
                onPressed: valid ? () => Navigator.pop(context, true) : null,
                child: const Text('Confirm correction'),
              ),
            ],
          );
        },
      ),
    );
    return confirmed == true &&
        identical(binding, c.sessionIdentity) &&
        c.detail?.id == b.id &&
        c.detail?.version == b.version &&
        c.detail?.latestCorrectionNumber == b.latestCorrectionNumber;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final selection = c.detail?.id ?? c.selection?.revisionId;
      if (!identical(identity, c.sessionIdentity) || selected != selection) {
        identity = c.sessionIdentity;
        selected = selection;
        _clear();
      }
      final b = c.detail;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            c.self ? 'My preparation batches' : 'Preparation history',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Operator declarations of whole declared Recipe batches. No Stock effect.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null) Text(c.error!),
          if (localError != null) Text(localError!),
          if (c.notice != null) Text(c.notice!),
          if (c.lastConfirmed case final result?) _confirmation(result),
          if (c.refreshWarning != null) Text(c.refreshWarning!),
          if (c.detail == null && c.confirmedBatchId != null)
            TextButton(
              key: const Key('batch-reload-detail'),
              onPressed: c.locked ? null : () => c.select(c.confirmedBatchId!),
              child: const Text('Reload authoritative batch detail'),
            ),
          if (c.pending != null)
            FilledButton(
              key: const Key('batch-retry'),
              onPressed: c.busy ? null : () => _act(c.retry),
              child: const Text('Retry exact command'),
            ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: c.locked ? null : () => c.load(),
                child: const Text('Refresh history'),
              ),
              DropdownButton<String>(
                value: c.status ?? 'all',
                items: [
                  for (final s in ['all', 'open', 'completed', 'cancelled'])
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: c.locked
                    ? null
                    : (s) => c.filter(s == 'all' ? null : s),
              ),
              if (c.self && c.canExecute && c.canReadRecipe)
                FilledButton(
                  key: const Key('batch-choose-recipe'),
                  onPressed: c.locked ? null : () => c.choices(),
                  child: const Text('Select approved Recipe'),
                ),
            ],
          ),
          for (final item in c.items)
            ListTile(
              key: Key('batch-${item.id}'),
              title: Text('${item.status} · ${item.id}'),
              subtitle: Text(
                'Employee ${item.json['employeeId']} · planned ${item.json['plannedDeclaredBatchCount'] ?? '—'} · original ${item.actual ?? '—'} · effective ${item.effective ?? '—'} declared Recipe batches',
              ),
              onTap: c.locked ? null : () => c.select(item.id),
            ),
          if (c.nextCursor != null)
            TextButton(
              onPressed: c.locked ? null : () => c.load(more: true),
              child: const Text('More batches'),
            ),
          for (final recipe in c.recipes)
            ListTile(
              key: Key('batch-recipe-${recipe.recipe}'),
              title: Text(recipe.content.produced.name),
              subtitle: Text(
                'Revision ${recipe.revisionNumber} · ${recipe.content.batchDescription}',
              ),
              onTap: c.locked ? null : () => c.choose(recipe),
            ),
          if (c.recipeCursor != null)
            TextButton(
              onPressed: c.locked ? null : () => c.choices(more: true),
              child: const Text('More Recipes'),
            ),
          if (c.selection case final preview?) ...[
            _instruction(preview.content, preview.revisionNumber),
            const Text(
              'Current eligibility is rechecked when opening, including local Assortment and ingredient units.',
            ),
            _field(
              'batch-planned',
              'Planned declared Recipe batches (optional, 1–9999)',
              planned,
              numeric: true,
            ),
            FilledButton(
              key: const Key('batch-open'),
              onPressed: c.locked
                  ? null
                  : () => _act(
                      () => c.open(
                        planned.text.trim().isEmpty ? null : _count(planned),
                      ),
                    ),
              child: const Text('Open preparation batch'),
            ),
          ],
          if (b != null) ...[
            SelectableText(
              'Batch ${b.id}\nLocation ${b.json['locationId']}\nEmployee ${b.json['employeeId']}\nRecipe ${b.json['recipeId']}\nRevision ${b.json['revisionId']}\nOpened ${b.json['openedAt']} by ${b.json['openedBy']}\nPlanned ${b.json['plannedDeclaredBatchCount'] ?? '—'} declared Recipe batches\n${b.status} · version ${b.version}',
            ),
            if (c.canReadRecipe)
              TextButton(
                key: const Key('batch-instruction'),
                onPressed: c.locked ? null : c.readInstruction,
                child: const Text('Open retained Recipe instruction'),
              ),
            if (c.instruction case final instruction?) ...[
              _instruction(
                RecipeContent.fromJson(
                  instruction['content'] as Map<String, dynamic>,
                ),
                instruction['revisionNumber'] as int,
              ),
              const Text(
                'Current warnings (frozen content above remains authoritative)',
              ),
              for (final warning in instruction['warnings'] as List)
                Text(warning.toString()),
            ],
            if (b.status == 'open' && c.canExecute) ...[
              if (c.self) ...[
                _field(
                  'batch-actual',
                  'Actual declared Recipe batches (1–9999)',
                  actual,
                  numeric: true,
                ),
                _field('batch-note', 'Completion note (optional)', note),
                FilledButton(
                  key: const Key('batch-complete'),
                  onPressed: c.locked
                      ? null
                      : () => _act(() => c.complete(_count(actual), note.text)),
                  child: const Text('Report completion'),
                ),
              ],
              _field('batch-cancel-reason', 'Cancellation reason', reason),
              TextButton(
                key: const Key('batch-cancel'),
                onPressed: c.locked
                    ? null
                    : () => _act(() => c.cancel(reason.text)),
                child: Text(
                  c.self
                      ? 'Cancel preparation'
                      : 'Manager cancel abandoned preparation',
                ),
              ),
            ],
            if (b.status == 'completed') ...[
              Text('Original completion: ${b.actual} declared Recipe batches'),
              SelectableText(
                'Completed ${b.json['completedAt']} by ${b.json['completedBy']}',
              ),
              if (b.json['completionNote'] != null)
                SelectableText(b.json['completionNote'] as String),
              Text(
                b.effective == 0
                    ? 'Reported completion corrected to 0 declared Recipe batches.'
                    : 'Effective count: ${b.effective} declared Recipe batches',
              ),
              for (final correction in b.json['corrections'] as List? ?? [])
                SelectableText(
                  'Correction ${correction['correctionNumber']}: ${correction['previousEffectiveCount']} → ${correction['replacementDeclaredBatchCount']}\n${correction['correctedAt']} · ${correction['correctedBy']}\n${correction['reason']}',
                ),
              if (!c.self && c.canExecute) ...[
                _field(
                  'batch-replacement',
                  'Replacement declared Recipe batches (0–9999)',
                  replacement,
                  numeric: true,
                ),
                _field('batch-correction-reason', 'Correction reason', reason),
                FilledButton(
                  key: const Key('batch-correct'),
                  onPressed: c.locked
                      ? null
                      : () => _act(() async {
                          final count = _count(replacement, correction: true);
                          preparationEvidenceText(reason.text);
                          if (!await _confirmCorrection(count)) {
                            return PreparationOutcome.rejected;
                          }
                          return c.correct(count, reason.text);
                        }),
                  child: const Text('Review count correction'),
                ),
              ],
            ],
            if (b.status == 'cancelled')
              SelectableText(
                'Cancelled ${b.json['cancelledAt']} by ${b.json['cancelledBy']}\n${b.json['cancellationReason']}',
              ),
            TextButton(
              onPressed: c.locked ? null : c.closeDetail,
              child: const Text('Close detail'),
            ),
          ],
        ],
      );
    },
  );
}
