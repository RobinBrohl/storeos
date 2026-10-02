import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_design_system/storeos_design_system.dart';

import '../application/session_controller.dart';

Future<void> showChangePasswordDialog(
  BuildContext context,
  SessionController controller,
) {
  controller.clearMessages();
  return showDialog<void>(
    context: context,
    builder: (context) => _ChangePasswordDialog(controller: controller),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.controller});

  final SessionController controller;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmation = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text;
    final next = _next.text;
    setState(() => _localError = null);
    if (current.isEmpty) {
      setState(() => _localError = 'Aktuelles Passwort eingeben.');
      return;
    }
    final bytes = passwordUtf8ByteLength(next);
    if (bytes < passwordMinUtf8Bytes || bytes > passwordMaxUtf8Bytes) {
      setState(() {
        _localError =
            'Das neue Passwort muss $passwordMinUtf8Bytes bis '
            '$passwordMaxUtf8Bytes UTF-8-Bytes lang sein.';
      });
      return;
    }
    if (next == current) {
      setState(() {
        _localError =
            'Das neue Passwort muss sich vom aktuellen unterscheiden.';
      });
      return;
    }
    if (_confirmation.text != next) {
      setState(() {
        _localError =
            'Die Bestätigung stimmt nicht mit dem neuen Passwort überein.';
      });
      return;
    }
    final success = await widget.controller.changePassword(
      currentPassword: current,
      newPassword: next,
    );
    if (!mounted) return;
    if (success || !widget.controller.isAuthenticated) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final busy = widget.controller.isBusy;
      final error = _localError ?? widget.controller.error;
      return AlertDialog(
        scrollable: true,
        title: const Text('Passwort ändern'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('current-password-field'),
                controller: _current,
                enabled: !busy,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Aktuelles Passwort',
                ),
              ),
              const SizedBox(height: StoreSpacing.md),
              TextField(
                key: const Key('new-password-field'),
                controller: _next,
                enabled: !busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Neues Passwort'),
              ),
              const SizedBox(height: StoreSpacing.md),
              TextField(
                key: const Key('confirm-password-field'),
                controller: _confirmation,
                enabled: !busy,
                obscureText: true,
                onSubmitted: (_) => busy ? null : _submit(),
                decoration: const InputDecoration(
                  labelText: 'Neues Passwort bestätigen',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: StoreSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(error, key: const Key('change-password-error')),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('change-password-cancel'),
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('change-password-submit'),
            onPressed: busy ? null : _submit,
            child: Text(busy ? 'Wird geändert …' : 'Passwort ändern'),
          ),
        ],
      );
    },
  );
}
