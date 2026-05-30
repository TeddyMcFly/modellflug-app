import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/services/auth_service.dart';
import '../../shared/utils/centered_snack_bar.dart';

const _loginIntroLogoAsset = 'homepage/assets/login_logo12.png';
const _loginNavy = Color(0xFF06172E);

enum _AuthMode { signIn, register }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _loading = false;
  bool _obscurePassword = true;

  bool get _isRegistering => _mode == _AuthMode.register;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _loginNavy,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100;

          return ColoredBox(
            color: _loginNavy,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: wide ? 1040 : 460,
                    ),
                    child: wide
                        ? IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 590,
                                  child: _AuthIntro(),
                                ),
                                const SizedBox(width: 30),
                                SizedBox(width: 420, child: _buildFormCard()),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _AuthIntro(compact: true),
                              const SizedBox(height: 8),
                              _buildFormCard(),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_person_rounded,
                color: Color(0xFF0A84FF),
                size: 36,
              ),
              const SizedBox(height: 10),
              Text(
                _isRegistering ? 'Konto erstellen' : 'Anmelden',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF06172E),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isRegistering
                    ? 'Lege dein Modellflug-Konto an.'
                    : 'Melde dich mit deinem Modellflug-Konto an.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<_AuthMode>(
                segments: const [
                  ButtonSegment(
                    value: _AuthMode.signIn,
                    icon: Icon(Icons.login_rounded),
                    label: Text('Anmelden'),
                  ),
                  ButtonSegment(
                    value: _AuthMode.register,
                    icon: Icon(Icons.person_add_alt_1_rounded),
                    label: Text('Neu'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _loading
                    ? null
                    : (value) => setState(() => _mode = value.first),
              ),
              const SizedBox(height: 14),
              if (_isRegistering) ...[
                TextFormField(
                  controller: _name,
                  enabled: !_loading,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                  validator: (value) {
                    if (!_isRegistering) {
                      return null;
                    }
                    return value == null || value.trim().isEmpty
                        ? 'Bitte gib deinen Namen ein.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _email,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'E-Mail',
                  prefixIcon: Icon(Icons.mail_rounded),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty || !email.contains('@')) {
                    return 'Bitte gib deine E-Mail-Adresse ein.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                enabled: !_loading,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Passwort anzeigen'
                        : 'Passwort verbergen',
                    onPressed: _loading
                        ? null
                        : () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
                ),
                validator: (value) {
                  if ((value ?? '').length < 6) {
                    return 'Mindestens 6 Zeichen.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isRegistering
                            ? Icons.person_add_alt_1_rounded
                            : Icons.login_rounded,
                      ),
                label: Text(_isRegistering ? 'Konto erstellen' : 'Anmelden'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _loading ? null : _resetPassword,
                icon: const Icon(Icons.help_rounded),
                label: const Text('Passwort vergessen'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _loading = true);
    try {
      final auth = ref.read(authControllerProvider);
      if (_isRegistering) {
        await auth.register(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
        );
      } else {
        await auth.signIn(
          email: _email.text,
          password: _password.text,
        );
      }
      if (mounted) {
        context.go(_safeRedirectTarget(context) ?? '/dashboard');
      }
    } on Object catch (error) {
      _showMessage(authErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showMessage('Bitte gib zuerst deine E-Mail-Adresse ein.');
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider).sendPasswordResetEmail(email);
      _showMessage('Firebase hat dir eine E-Mail zum Zuruecksetzen geschickt.');
    } on Object catch (error) {
      _showMessage(authErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    showCenteredSnackBar(context, message);
  }

  String? _safeRedirectTarget(BuildContext context) {
    final from = GoRouterState.of(context).uri.queryParameters['from'];
    if (from == null || from.isEmpty || from == '/login') {
      return null;
    }
    if (!from.startsWith('/') || from.startsWith('//')) {
      return null;
    }
    return from;
  }
}

class _AuthIntro extends StatelessWidget {
  final bool compact;

  const _AuthIntro({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final introContent = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Modellflug-Heaven',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 36 : 46,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Faszination Modellflug - Alles in einer App',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFBFDBFE),
            fontSize: compact ? 15 : 18,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: compact ? 24 : 34),
        _AuthIntroLogo(compact: compact),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment:
          compact ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        introContent,
      ],
    );
  }
}

class _AuthIntroLogo extends StatelessWidget {
  final bool compact;

  const _AuthIntroLogo({required this.compact});

  @override
  Widget build(BuildContext context) {
    final logoHeight = compact ? 170.0 : 250.0;

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 430 : 680),
        child: SizedBox(
          width: double.infinity,
          height: logoHeight,
          child: ClipRect(
            child: Image.asset(
              _loginIntroLogoAsset,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              semanticLabel: 'Modellflug-Heaven Logo',
            ),
          ),
        ),
      ),
    );
  }
}
