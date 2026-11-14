import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.isConfigured) {
    runApp(const SetupRequiredApp());
    return;
  }
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
  configureDependencies(Supabase.instance.client);
  runApp(const SidiApp());
}
