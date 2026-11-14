import '../../../core/error/result.dart';
import 'catalog.dart';

abstract interface class CatalogRepository {
  Future<Result<Catalog>> load();
}
