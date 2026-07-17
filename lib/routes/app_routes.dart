import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../presentation/active_session_screen/active_session_screen.dart';
import '../presentation/email_reports_screen/email_reports_screen.dart';
import '../presentation/gate_management_screen/gate_management_screen.dart';
import '../presentation/login_screen/login_screen.dart';
import '../presentation/manual_entry_screen/manual_entry_screen.dart';
import '../presentation/po_tracker_screen/po_tracker_screen.dart';
import '../presentation/privacy_policy_screen/privacy_policy_screen.dart';
import '../presentation/tracks_screen/tracks_screen.dart';
import '../presentation/session_history_screen/project_selection_screen.dart';
import '../presentation/settings_screen/settings_screen.dart';
import '../presentation/splash_screen/splash_screen.dart';
import '../services/engineer_auth_service.dart';
import '../widgets/app_scaffold.dart';
import '../presentation/monthly_invoices_screen/monthly_invoices_screen.dart';
import '../presentation/admin_screen/admin_screen.dart';
import '../presentation/project_updates_screen/project_updates_screen.dart';
import '../presentation/tyre_trends_screen/tyre_trends_screen.dart';
import '../presentation/instrumentation_screen/instrumentation_screen.dart';

class AppRoutes {
  static const String initial = '/';
  static const String splash = '/';
  static const String login = '/login';
  static const String projectSelection = '/project-selection';
  static const String activeSession = '/active-session-screen';
  static const String sessionHistory = '/session-history-screen';
  static const String gateManagement = '/gate-management-screen';
  static const String poTracker = '/po-tracker-screen';
  static const String emailReports = '/email-reports-screen';
  static const String manualEntry = '/manual-entry-screen';
  static const String privacyPolicy = '/privacy-policy';
  static const String settings = '/settings-screen';
  static const String monthlyInvoices = '/monthly-invoices-screen';
  static const String admin = '/admin-screen';
  static const String projectUpdates = '/project-updates-screen';
  static const String tyreTrends = '/tyre-trends-screen';
  static const String instrumentation = '/instrumentation-screen';
}


final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.initial,
  redirect: (context, state) {
    final isLoggedIn = EngineerAuthService.instance.isSignedIn;
    final isSplash = state.matchedLocation == AppRoutes.splash;
    final isLogin = state.matchedLocation == AppRoutes.login;

    // Allow splash to always show first
    if (isSplash) return null;

    // If not logged in and not on login, redirect to login
    if (!isLoggedIn && !isLogin) return AppRoutes.login;

    // If logged in and on login, redirect to app
    // if (isLoggedIn && isLogin) {
    //   return kIsWeb ? AppRoutes.projectSelection : AppRoutes.activeSession;
    // }

    return null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.initial,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const SplashScreen(),
        transitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: child,
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.login,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const LoginScreen(),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.privacyPolicy,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const PrivacyPolicyScreen(),
        transitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    ),

    GoRoute(
      path: AppRoutes.poTracker,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const PoTrackerScreen(),
        transitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.emailReports,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const EmailReportsScreen(),
        transitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppScaffold(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.activeSession,
              builder: (context, state) => const ActiveSessionScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.sessionHistory,
              builder: (context, state) => const TracksScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.gateManagement,
              builder: (context, state) => const GateManagementScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.manualEntry,
              builder: (context, state) => const ManualEntryScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.monthlyInvoices,
              builder: (context, state) => const MonthlyInvoicesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.admin,
              builder: (context, state) => const AdminScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.projectUpdates,
              builder: (context, state) => const ProjectUpdatesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.tyreTrends,
              builder: (context, state) => const TyreTrendsScreen(),
            ),
          ],
        ),
        // Branch 9: Instrumentation
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.instrumentation,
              builder: (context, state) => const InstrumentationScreen(),
            ),
          ],
        ),
        // Branch 10: Project Selection
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.projectSelection,
              builder: (context, state) => const ProjectSelectionScreen(),
            ),
          ],
        ),
      ],
    ),

  ],
);
