import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_page.dart';
import '../features/auth/presentation/account_page.dart';
import '../features/auth/presentation/notifications_page.dart';
import '../features/auth/presentation/session_cubit.dart';
import '../features/auth/presentation/sign_in_page.dart';
import '../features/booking/presentation/book_resource_page.dart';
import '../features/booking/presentation/desk_page.dart';
import '../features/booking/presentation/facilities_page.dart';
import '../features/booking/presentation/my_bookings_page.dart';
import '../features/booking/presentation/payments_page.dart';
import '../features/discover/presentation/discover_page.dart';
import '../features/discover/presentation/org_profile_page.dart';
import '../features/finance/presentation/budget_page.dart';
import '../features/finance/presentation/payroll_pages.dart';
import '../features/finance/presentation/staff_page.dart';
import '../features/membership/presentation/journey_home_page.dart';
import '../features/membership/presentation/journey_page.dart';
import '../features/membership/presentation/members_page.dart';
import '../features/membership/presentation/plans_page.dart';
import '../features/organization/presentation/access_page.dart';
import '../features/organization/presentation/manage_home_page.dart';
import '../features/organization/presentation/team_page.dart';
import '../features/tournaments/presentation/event_page.dart';
import '../features/tournaments/presentation/org_tournaments_page.dart';
import '../features/tournaments/presentation/tournament_page.dart';
import '../features/tournaments/presentation/tournaments_page.dart';
import 'home_shell.dart';

/// Routes, and the one rule that guards them: who you are decides where you
/// may be. Authorisation proper lives in the backend; this only keeps people
/// out of screens that would show them nothing but errors.
///
/// Pages that take an id are keyed by it: without the key, opening a second
/// tournament over the first would keep the first one's cubit and data.
GoRouter buildRouter(SessionCubit session) {
  String currencyOf(BuildContext context, String orgId) =>
      context.read<SessionCubit>().state.me?.organizations.where((o) => o.id == orgId).firstOrNull?.currency ?? 'INR';

  return GoRouter(
    initialLocation: '/discover',
    refreshListenable: _StreamListenable(session.stream),
    redirect: (context, state) {
      final status = session.state.status;
      final location = state.matchedLocation;
      if (status == SessionStatus.unknown) return location == '/splash' ? null : '/splash';
      if (status == SessionStatus.signedOut) return location == '/signin' ? null : '/signin';
      if (location == '/signin' || location == '/splash') return '/discover';
      if (location.startsWith('/admin') && !(session.state.me?.isStaff ?? false)) return '/account';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/signin', builder: (_, _) => const SignInPage()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/discover', builder: (_, _) => const DiscoverPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/bookings', builder: (_, _) => const MyBookingsPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/tournaments', builder: (_, _) => const TournamentsPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/journey', builder: (_, _) => const JourneyHomePage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, _) => const AccountPage())]),
        ],
      ),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsPage()),
      GoRoute(path: '/entries', builder: (_, _) => const MyEntriesPage()),
      GoRoute(path: '/org/:orgId', builder: (_, state) => OrgProfilePage(key: ValueKey(state.pathParameters['orgId']), orgId: state.pathParameters['orgId']!)),
      GoRoute(path: '/book/:resourceId', builder: (_, state) => BookResourcePage(key: ValueKey(state.pathParameters['resourceId']), resourceId: state.pathParameters['resourceId']!)),
      GoRoute(path: '/journey/:membershipId', builder: (_, state) => JourneyPage(key: ValueKey(state.pathParameters['membershipId']), membershipId: state.pathParameters['membershipId']!)),
      GoRoute(path: '/tournament/:id', builder: (_, state) => TournamentPage(key: ValueKey(state.pathParameters['id']), tournamentId: state.pathParameters['id']!)),
      GoRoute(path: '/event/:id', builder: (_, state) => EventPage(key: ValueKey(state.pathParameters['id']), eventId: state.pathParameters['id']!)),
      GoRoute(path: '/admin', builder: (_, _) => const AdminPage()),
      GoRoute(
        path: '/manage/:orgId',
        builder: (_, state) => ManageHomePage(key: ValueKey(state.pathParameters['orgId']), orgId: state.pathParameters['orgId']!),
        routes: [
          GoRoute(path: 'desk', builder: (_, state) => DeskPage(orgId: state.pathParameters['orgId']!)),
          GoRoute(path: 'payments', builder: (_, state) => PaymentsPage(orgId: state.pathParameters['orgId']!)),
          GoRoute(path: 'facilities', builder: (_, state) => FacilitiesPage(orgId: state.pathParameters['orgId']!)),
          GoRoute(
            path: 'plans',
            builder: (context, state) =>
                PlansPage(orgId: state.pathParameters['orgId']!, currency: currencyOf(context, state.pathParameters['orgId']!)),
          ),
          GoRoute(
            path: 'members',
            builder: (_, state) => MembersPage(orgId: state.pathParameters['orgId']!),
            routes: [
              GoRoute(
                path: ':membershipId',
                builder: (_, state) => JourneyPage(key: ValueKey(state.pathParameters['membershipId']), membershipId: state.pathParameters['membershipId']!, coachView: true),
              ),
            ],
          ),
          GoRoute(path: 'team', builder: (_, state) => TeamPage(orgId: state.pathParameters['orgId']!)),
          GoRoute(path: 'access', builder: (_, state) => AccessPage(orgId: state.pathParameters['orgId']!)),
          GoRoute(path: 'tournaments', builder: (_, state) => OrgTournamentsPage(orgId: state.pathParameters['orgId']!)),
          GoRoute(
            path: 'staff',
            builder: (context, state) =>
                StaffPage(orgId: state.pathParameters['orgId']!, currency: currencyOf(context, state.pathParameters['orgId']!)),
          ),
          GoRoute(
            path: 'payroll',
            builder: (context, state) =>
                PayrollPage(orgId: state.pathParameters['orgId']!, currency: currencyOf(context, state.pathParameters['orgId']!)),
            routes: [GoRoute(path: ':runId', builder: (_, state) => PayrollRunPage(key: ValueKey(state.pathParameters['runId']), runId: state.pathParameters['runId']!))],
          ),
          GoRoute(path: 'budget', builder: (_, state) => BudgetPage(orgId: state.pathParameters['orgId']!)),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('That page does not exist.'),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: () => context.go('/discover'), child: const Text('Go home')),
          ],
        ),
      ),
    ),
  );
}

/// Lets go_router re-run its redirect whenever the session changes.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
