import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/inventory/inventory_list_screen.dart';
import 'features/inventory/item_form_screen.dart';
import 'features/sync/sync_controller.dart';

/// Tells the router to re-check its redirect whenever the user signs in or out.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    _subscription = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter _buildRouter() {
  return GoRouter(
    refreshListenable: AppConfig.hasSupabase ? _AuthRefresh() : null,
    redirect: (context, state) {
      if (!AppConfig.hasSupabase) return null; // local-only mode: no sign-in
      final signedIn = Supabase.instance.client.auth.currentSession != null;
      final atSignIn = state.matchedLocation == '/signin';
      if (!signedIn && !atSignIn) return '/signin';
      if (signedIn && atSignIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const InventoryListScreen()),
      GoRoute(path: '/item/new', builder: (context, state) => const ItemFormScreen()),
      GoRoute(
        path: '/item/:id',
        builder: (context, state) =>
            ItemFormScreen(itemId: state.pathParameters['id']),
      ),
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
      GoRoute(path: '/signin', builder: (context, state) => const SignInScreen()),
    ],
  );
}

class StocktakeApp extends ConsumerStatefulWidget {
  const StocktakeApp({super.key});

  @override
  ConsumerState<StocktakeApp> createState() => _StocktakeAppState();
}

class _StocktakeAppState extends ConsumerState<StocktakeApp> {
  late final GoRouter _router = _buildRouter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncControllerProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Stocktake',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
