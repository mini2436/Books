import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/annotations/annotation_center_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/bookshelf/bookshelf_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/reader/reader_screen.dart';
import 'app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authController = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authController,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (authController.isBootstrapping) {
        return location == '/splash' ? null : '/splash';
      }

      if (!authController.isAuthenticated) {
        return location == '/login' ? null : '/login';
      }

      if (location == '/login' || location == '/splash') {
        return '/shelf';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
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
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
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

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
