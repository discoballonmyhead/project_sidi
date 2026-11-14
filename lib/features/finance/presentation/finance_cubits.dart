import '../../../core/bloc/async_cubit.dart';
import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../domain/finance.dart';
import '../domain/finance_repository.dart';

class EmployeesCubit extends AsyncCubit<List<Employee>> {
  EmployeesCubit(this._repository, this.orgId);
  final FinanceRepository _repository;
  final String orgId;

  @override
  Future<Result<List<Employee>>> fetch() => _repository.employees(orgId);

  Future<bool> save(Json employee) => act(() => _repository.saveEmployee(orgId, employee), success: 'Saved.');
}

class PayrollRunsCubit extends AsyncCubit<List<PayrollRun>> {
  PayrollRunsCubit(this._repository, this.orgId);
  final FinanceRepository _repository;
  final String orgId;

  @override
  Future<Result<List<PayrollRun>>> fetch() => _repository.payrollRuns(orgId);

  /// Opens a draft run and returns its id, or null when it failed.
  Future<String?> create(DateTime from, DateTime to) async {
    String? id;
    await act(() async {
      final result = await _repository.createPayrollRun(orgId, from, to);
      id = result.valueOrNull;
      return result;
    });
    return id;
  }
}

/// One pay run: draft → approved → paid.
class PayrollRunCubit extends AsyncCubit<PayrollRun> {
  PayrollRunCubit(this._repository, this.runId);
  final FinanceRepository _repository;
  final String runId;

  @override
  Future<Result<PayrollRun>> fetch() => _repository.payrollRun(runId);

  Future<bool> updateItem(PayrollItem item, Json patch) => act(() => _repository.updatePayrollItem(item.id, patch));

  Future<bool> setStatus(String status) => act(
    () => _repository.setPayrollStatus(runId, status),
    success: switch (status) {
      'approved' => 'Run approved.',
      'paid' => 'Marked as paid and booked to the budget.',
      _ => 'Back to draft.',
    },
  );

  Future<bool> delete() => act(() => _repository.deletePayrollRun(runId), reload: false);
}

enum BudgetRange {
  thisMonth('This month'),
  last3Months('3 months'),
  last6Months('6 months'),
  thisYear('This year');

  const BudgetRange(this.label);
  final String label;

  (DateTime, DateTime) window(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      BudgetRange.thisMonth => (DateTime(now.year, now.month), today),
      BudgetRange.last3Months => (DateTime(now.year, now.month - 2), today),
      BudgetRange.last6Months => (DateTime(now.year, now.month - 5), today),
      BudgetRange.thisYear => (DateTime(now.year), today),
    };
  }
}

/// Income, spend and budget usage for a period, bucketed by week or month.
class BudgetCubit extends AsyncCubit<BudgetDashboard> {
  BudgetCubit(this._repository, this.orgId);
  final FinanceRepository _repository;
  final String orgId;

  BudgetRange range = BudgetRange.last3Months;
  String bucket = 'month';

  @override
  Future<Result<BudgetDashboard>> fetch() {
    final (from, to) = range.window(DateTime.now());
    return _repository.budget(orgId, from: from, to: to, bucket: bucket);
  }

  Future<void> show({BudgetRange? range, String? bucket}) {
    this.range = range ?? this.range;
    this.bucket = bucket ?? this.bucket;
    // A single month reads better week by week.
    if (range == BudgetRange.thisMonth) this.bucket = 'week';
    return load();
  }

  Future<bool> addEntry(Json entry) => act(() => _repository.addLedgerEntry(orgId, entry), success: 'Entry added.');
  Future<bool> deleteEntry(LedgerLine line) => act(() => _repository.deleteLedgerEntry(line.id), success: 'Entry removed.');
  Future<bool> saveRecurring(Json cost) => act(() => _repository.saveRecurringCost(orgId, cost), success: 'Recurring cost saved.');
  Future<bool> deleteRecurring(RecurringCost cost) =>
      act(() => _repository.deleteRecurringCost(cost.id), success: 'Recurring cost removed.');
  Future<bool> setLimit(String category, num? monthlyLimit) => act(
    () => _repository.setBudgetLimit(orgId, category, monthlyLimit),
    success: monthlyLimit == null ? 'Budget removed.' : 'Budget set.',
  );
}
