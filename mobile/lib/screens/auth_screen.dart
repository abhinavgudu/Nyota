import 'package:flutter/material.dart';

import '../services/nyota_service.dart';
import '../theme.dart';
import 'home_shell.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    NyotaService.client.auth.onAuthStateChange.listen((state) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = NyotaService.isSignedIn;
    return signedIn ? const HomeShell() : const AuthScreen();
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isSignUp = false;
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isSignUp) {
        await NyotaService.signUp(_emailCtrl.text.trim(), _passwordCtrl.text, _nameCtrl.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account created. Please sign in.')),
          );
          setState(() => _isSignUp = false);
        }
      } else {
        await NyotaService.signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
      }
      if (mounted) setState(() {});
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('Invalid login credentials')) return 'Wrong email or password.';
    if (s.contains('already registered')) return 'This email is already registered. Please sign in.';
    if (s.contains('at least 6')) return 'Password must be at least 6 characters.';
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: NyotaColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: NyotaColors.royalPurple.withValues(alpha: 0.12),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Image.asset(
                          'assets/logo.png',
                          width: 280,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      _isSignUpLabel,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: NyotaColors.ink),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Digital Guest & Gift Manager',
                      style: TextStyle(color: NyotaColors.muted),
                    ),
                    const SizedBox(height: 28),
                    if (_isSignUp) ...[
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'At least 6 characters' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!,
                          style: const TextStyle(color: NyotaColors.danger),
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_isSignUp ? 'Create Account' : 'Sign In'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(_isSignUp
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _isSignUpLabel = 'Nyota';
