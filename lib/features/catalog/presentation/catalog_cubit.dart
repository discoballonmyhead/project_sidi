import '../../../core/bloc/async_cubit.dart';
import '../../../core/error/result.dart';
import '../domain/catalog.dart';
import '../domain/catalog_repository.dart';

/// Reference data for the whole app. Provided at the root and loaded once.
class CatalogCubit extends AsyncCubit<Catalog> {
  CatalogCubit(this._repository);
  final CatalogRepository _repository;

  @override
  Future<Result<Catalog>> fetch() => _repository.load();
}
