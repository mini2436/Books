import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/admin/admin_book_detail_screen.dart';
import '../features/admin/admin_center_screen.dart';
import '../features/annotations/annotation_center_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/bookshelf/bookshelf_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/reader/reader_screen.dart';
import 'app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authController = ref.read(authControllerProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authController,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (authController.isBootstrapping) {
        return location == '/splash'
            ? null
            : _routeWithNext('/splash', state.uri.toString());
      }

      if (!authController.isAuthenticated) {
        if (location == '/login') {
          return null;
        }
        final next =
            state.uri.queryParameters['next'] ??
            (location == '/splash' ? null : state.uri.toString());
        return next == null ? '/login' : _routeWithNext('/login', next);
      }

      if (location == '/login' || location == '/splash') {
        return _safeNextRoute(state.uri.queryParameters['next']) ?? '/shelf';
      }

      if (location.startsWith('/admin') &&
          !(authController.user?.canAccessAdmin ?? false)) {
        return '/profile';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        navigatorContainerBuilder: AppShell.buildBranchContainer,
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/shelf',
                builder: (context, state) => const BookshelfScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/annotations',
                builder: (context, state) => const AnnotationCenterScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin',
                builder: (context, state) => const AdminCenterScreen(),
                routes: [
                  GoRoute(
                    path: 'books/:bookId',
                    builder: (context, state) {
                      final bookId = int.tryParse(
                        state.pathParameters['bookId'] ?? '',
                      );
                      return AdminBookDetailScreen(bookId: bookId ?? 0);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const BookshelfSearchScreen(),
      ),
      GoRoute(
        path: '/reader/:bookId',
        builder: (context, state) {
          final bookId = int.tryParse(state.pathParameters['bookId'] ?? '');
          return ReaderScreen(
            bookId: bookId,
            initialAnchor: state.uri.queryParameters['anchor'],
          );
        },
      ),
    ],
  );
});

String _routeWithNext(String route, String next) =>
    Uri(path: route, queryParameters: {'next': next}).toString();

String? _safeNextRoute(String? next) {
  if (next == null ||
      !next.startsWith('/') ||
      next.startsWith('/login') ||
      next.startsWith('/splash')) {
    return null;
  }
  return next;
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
