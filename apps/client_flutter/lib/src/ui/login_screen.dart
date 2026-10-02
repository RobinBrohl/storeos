import 'package:flutter/material.dart';
import 'package:storeos_design_system/storeos_design_system.dart';

import '../application/session_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.controller,
    required this.baseUri,
    super.key,
  });

  final SessionController controller;
  final Uri baseUri;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final password = _passwordController.text;
    _passwordController.clear();
    await widget.controller.signIn(
      username: _usernameController.text,
      password: password,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Padding(
                      padding: const EdgeInsets.all(StoreSpacing.lg),
                      child: wide
                          ? Row(
                              children: [
                                Expanded(child: _introduction(context)),
                                const SizedBox(width: StoreSpacing.lg),
                                SizedBox(
                                  width: 360,
                                  child: _loginCard(context),
                                ),
                              ],
                            )
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _introduction(context),
                                  const SizedBox(height: StoreSpacing.xl),
                                  _loginCard(context),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _introduction(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.storefront_outlined, size: 56, color: scheme.primary),
        const SizedBox(height: StoreSpacing.md),
        Text(
          'StoreOS',
          style: textTheme.displaySmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: StoreSpacing.sm),
        Text('Standortbetrieb', style: textTheme.headlineSmall),
        const SizedBox(height: StoreSpacing.sm),
        Text(
          'Melden Sie sich am lokalen Standortserver an, um dessen aktuellen Systemstatus zu sehen.',
          style: textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _loginCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(StoreSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Anmelden',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: StoreSpacing.sm),
              Text('Server: ${widget.baseUri.origin}'),
              const SizedBox(height: StoreSpacing.lg),
              TextFormField(
                key: const Key('username-field'),
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Benutzername'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Benutzername eingeben.'
                    : null,
              ),
              const SizedBox(height: StoreSpacing.md),
              TextFormField(
                key: const Key('password-field'),
                controller: _passwordController,
                obscureText: _obscurePassword,
                onFieldSubmitted: (_) => _submit(),
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Passwort',
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Passwort anzeigen'
                        : 'Passwort verbergen',
                    onPressed: () => setState(() {
                      _obscurePassword = !_obscurePassword;
                    }),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Passwort eingeben.'
                    : null,
              ),
              const SizedBox(height: StoreSpacing.lg),
              FilledButton(
                key: const Key('login-button'),
                onPressed: widget.controller.isBusy ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: StoreSpacing.sm,
                  ),
                  child: Text(
                    widget.controller.isBusy ? 'Anmeldung läuft …' : 'Anmelden',
                  ),
                ),
              ),
              if (widget.controller.isBusy) ...[
                const SizedBox(height: StoreSpacing.md),
                const LinearProgressIndicator(),
              ],
              if (widget.controller.error case final error?) ...[
                const SizedBox(height: StoreSpacing.md),
                StoreStatusPanel(
                  title: 'Anmeldung nicht möglich',
                  message: error,
                  tone: StoreStatusTone.critical,
                ),
              ],
              if (widget.controller.notice case final notice?) ...[
                const SizedBox(height: StoreSpacing.md),
                StoreStatusPanel(
                  title: widget.controller.noticeTitle ?? 'Hinweis',
                  message: notice,
                  tone: widget.controller.noticePositive
                      ? StoreStatusTone.positive
                      : StoreStatusTone.warning,
                ),
              ],
              const SizedBox(height: StoreSpacing.md),
              Text(
                'Die Sitzung wird auf diesem Gerät nicht dauerhaft gespeichert.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
