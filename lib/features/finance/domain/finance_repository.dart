import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import 'finance.dart';

abstract interface class FinanceRepository {
  Future<Result<List<Employee>>> employees(String orgId);
  Future<Result<void>> saveEmployee(String orgId, Json employee);

  Future<Result<List<PayrollRun>>> payrollRuns(String orgId);
  Future<Result<PayrollRun>> payrollRun(String runId);
  Future<Result<String>> createPayrollRun(String orgId, DateTime from, DateTime to);
  Future<Result<void>> updatePayrollItem(String itemId, Json patch);
  Future<Result<void>> setPayrollStatus(String runId, String status);
  Future<Result<void>> deletePayrollRun(String runId);

  Future<Result<BudgetDashboard>> budget(String orgId, {required DateTime from, required DateTime to, required String bucket});
  Future<Result<void>> addLedgerEntry(String orgId, Json entry);
  Future<Result<void>> deleteLedgerEntry(String entryId);
  Future<Result<void>> saveRecurringCost(String orgId, Json cost);
  Future<Result<void>> deleteRecurringCost(String costId);
  Future<Result<void>> setBudgetLimit(String orgId, String category, num? monthlyLimit);
}
