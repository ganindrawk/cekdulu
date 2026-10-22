import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/theme/app_theme.dart';
import 'package:cekdulu/src/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:cekdulu/src/features/admin/presentation/ai_settings_screen.dart';
import 'package:cekdulu/src/features/admin/presentation/credentials_form_screen.dart';
import 'package:cekdulu/src/features/auth/presentation/forgot_password_screen.dart';
import 'package:cekdulu/src/features/auth/presentation/reset_password_screen.dart';
import 'package:cekdulu/src/features/admin/presentation/product_form_screen.dart';
import 'package:cekdulu/src/features/admin/presentation/affiliate_link_form_screen.dart';
import 'package:cekdulu/src/features/admin/presentation/users_screen.dart';
import 'package:cekdulu/src/features/auth/presentation/auth_notifier.dart';
import 'package:cekdulu/src/features/auth/presentation/account_settings_screen.dart';
import 'package:cekdulu/src/features/auth/presentation/login_screen.dart';
import 'package:cekdulu/src/features/auth/presentation/register_screen.dart';
import 'package:cekdulu/src/features/auth/presentation/verify_email_screen.dart';
import 'package:cekdulu/src/features/catalog/presentation/product_detail_screen.dart';
import 'package:cekdulu/src/features/catalog/presentation/product_list_screen.dart';
import 'package:cekdulu/src/features/scan/presentation/scan_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: auth,
    redirect: (context, state) {
      if (!auth.ready) return null;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' ||
          loc == '/register' ||
          loc == '/verify-email' ||
          loc == '/forgot-password' ||
          loc == '/forgot-password/reset';

      if (!auth.isLoggedIn) {
        return isAuthRoute ? null : '/login';
      }
      if (isAuthRoute) {
        // Setelah login: pengguna langsung ke halaman Scan.
        return auth.isAdmin ? '/admin' : '/scan';
      }
      if (loc.startsWith('/admin') && !auth.isAdmin) {
        return '/scan';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) =>
            VerifyEmailScreen(email: state.extra as String?),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
        routes: [
          GoRoute(
            path: 'reset',
            builder: (context, state) =>
                ResetPasswordScreen(email: state.extra as String?),
          ),
        ],
      ),
      // --- Area pengguna: bottom navigation ---
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _UserScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const ProductListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/scan',
                builder: (context, state) => const ScanScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/scan/result',
        builder: (context, state) {
          final data = state.extra! as ScanResultArgs;
          return ScanResultScreen(code: data.code, products: data.products);
        },
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountSettingsScreen(),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) => ProductDetailScreen(
          productId: state.pathParameters['id']!,
        ),
      ),
      // --- Area admin ---
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
        routes: [
          GoRoute(
            path: 'products/new',
            builder: (context, state) => const ProductFormScreen(),
          ),
          GoRoute(
            path: 'products/:id/edit',
            builder: (context, state) => ProductFormScreen(
              productId: state.pathParameters['id'],
            ),
          ),
          GoRoute(
            path: 'credentials',
            builder: (context, state) => const CredentialsFormScreen(),
          ),
          GoRoute(
            path: 'ai-settings',
            builder: (context, state) => const AiSettingsScreen(),
          ),
          GoRoute(
            path: 'affiliate-links',
            builder: (context, state) => const AffiliateLinkFormScreen(),
          ),
          GoRoute(
            path: 'users',
            builder: (context, state) => const UsersScreen(),
          ),
        ],
      ),
    ],
  );
});

class _UserScaffold extends StatelessWidget {
  const _UserScaffold({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Katalog',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
        ],
      ),
    );
  }
}

class CekDuluApp extends ConsumerWidget {
  const CekDuluApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'CekDulu',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
