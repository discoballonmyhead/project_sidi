import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/session_cubit.dart';
import '../features/catalog/presentation/catalog_cubit.dart';
import 'di.dart';
import 'router.dart';
import 'theme.dart';

/// Composition root of the widget tree: the two app-wide cubits (who is
/// signed in, and the reference catalogue) and the router that reacts to them.
class SidiApp extends StatefulWidget {
  const SidiApp({super.key});

  @override
  State<SidiApp> createState() => _SidiAppState();
}

class _SidiAppState extends State<SidiApp> {
  late final SessionCubit _session = SessionCubit(sl())..start();
  late final CatalogCubit _catalog = CatalogCubit(sl())..load();
  late final GoRouter _router = buildRouter(_session);

  @override
  void dispose() {
    _router.dispose();
    _session.close();
    _catalog.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [BlocProvider.value(value: _session), BlocProvider.value(value: _catalog)],
      child: BlocListener<SessionCubit, SessionState>(
        // The catalogue may have failed to load before sign-in (offline start).
        listenWhen: (previous, current) => previous.status != current.status && current.status == SessionStatus.signedIn,
        listener: (_, _) {
          if (!_catalog.state.hasData) _catalog.load();
        },
        child: MaterialApp.router(
          title: 'Sidi',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          routerConfig: _router,
        ),
      ),
    );
  }
}

/// Shown when the app was built without its backend configuration.
class SetupRequiredApp extends StatelessWidget {
  const SetupRequiredApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sidi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.settings_ethernet_rounded, size: 48),
                SizedBox(height: 16),
                Text('Backend not configured', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text(
                  'Run the app with your Supabase project details:\n\n'
                  'flutter run \\\n'
                  '  --dart-define=SUPABASE_URL=https://<project>.supabase.co \\\n'
                  '  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
