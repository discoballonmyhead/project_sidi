import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../core/bloc/submit_cubit.dart';
import '../domain/auth_repository.dart';

class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(create: (_) => SubmitCubit<bool>(), child: const _SignInView());
  }
}

class _SignInView extends StatefulWidget {
  const _SignInView();

  @override
  State<_SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<_SignInView> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final auth = sl<AuthRepository>();
    context.read<SubmitCubit<bool>>().submit(() async {
      if (_creating) {
        return auth.signUp(email: _email.text, password: _password.text, displayName: _name.text);
      }
      final result = await auth.signIn(email: _email.text, password: _password.text);
      return result.map((_) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: BlocConsumer<SubmitCubit<bool>, SubmitState<bool>>(
                listener: (context, state) {
                  if (state.status == SubmitStatus.done && state.value == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Check your inbox to confirm your e-mail, then sign in.')),
                    );
                    setState(() => _creating = false);
                  }
                },
                builder: (context, state) => Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.sports_score_rounded, size: 56, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text('Sidi', textAlign: TextAlign.center, style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        'Book courts, train with a coach, play tournaments.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 32),
                      if (_creating) ...[
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Your name'),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          validator: (value) => (value ?? '').trim().isEmpty ? 'Enter your name' : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'E-mail'),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        validator: (value) => (value ?? '').contains('@') ? null : 'Enter a valid e-mail',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                        autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (value) => (value ?? '').length < 6 ? 'At least 6 characters' : null,
                      ),
                      if (state.failure != null) ...[
                        const SizedBox(height: 12),
                        Text(state.failure!.message, style: TextStyle(color: theme.colorScheme.error)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: state.isBusy ? null : _submit,
                        child: state.isBusy
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_creating ? 'Create account' : 'Sign in'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: state.isBusy ? null : () => setState(() => _creating = !_creating),
                        child: Text(_creating ? 'I already have an account' : 'Create an account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
