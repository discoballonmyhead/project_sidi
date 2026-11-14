import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/rpc.dart';
import '../features/admin/data/admin_repository_impl.dart';
import '../features/admin/domain/admin_repository.dart';
import '../features/auth/data/auth_repository_impl.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/booking/data/booking_repository_impl.dart';
import '../features/booking/domain/booking_repository.dart';
import '../features/catalog/data/catalog_repository_impl.dart';
import '../features/catalog/domain/catalog_repository.dart';
import '../features/discover/data/discover_repository_impl.dart';
import '../features/discover/domain/discover_repository.dart';
import '../features/finance/data/finance_repository_impl.dart';
import '../features/finance/domain/finance_repository.dart';
import '../features/membership/data/membership_repository_impl.dart';
import '../features/membership/domain/membership_repository.dart';
import '../features/organization/data/organization_repository_impl.dart';
import '../features/organization/domain/organization_repository.dart';
import '../features/tournaments/data/tournament_repository_impl.dart';
import '../features/tournaments/domain/tournament_repository.dart';

/// Service locator. Only the composition root and `BlocProvider.create`
/// callbacks read from it; cubits receive their repositories by constructor.
final sl = GetIt.instance;

void configureDependencies(SupabaseClient client) {
  sl
    ..registerSingleton<SupabaseClient>(client)
    ..registerLazySingleton<Rpc>(() => SupabaseRpc(sl()))
    ..registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(sl(), sl()))
    ..registerLazySingleton<CatalogRepository>(() => CatalogRepositoryImpl(sl()))
    ..registerLazySingleton<DiscoverRepository>(() => DiscoverRepositoryImpl(sl()))
    ..registerLazySingleton<BookingRepository>(() => BookingRepositoryImpl(sl()))
    ..registerLazySingleton<MembershipRepository>(() => MembershipRepositoryImpl(sl()))
    ..registerLazySingleton<OrganizationRepository>(() => OrganizationRepositoryImpl(sl()))
    ..registerLazySingleton<FinanceRepository>(() => FinanceRepositoryImpl(sl()))
    ..registerLazySingleton<TournamentRepository>(() => TournamentRepositoryImpl(sl(), sl()))
    ..registerLazySingleton<AdminRepository>(() => AdminRepositoryImpl(sl()));
}
