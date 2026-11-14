import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/json.dart';
import '../domain/finance.dart';
import '../domain/finance_repository.dart';

PayrollRun _runFromJson(Json r) => PayrollRun(
  id: r.str('id'),
  periodStart: r.dayOrNull('period_start') ?? DateTime.now(),
  periodEnd: r.dayOrNull('period_end') ?? DateTime.now(),
  status: r.str('status'),
  total: r.number('total'),
  headcount: r.integer('headcount'),
  paidAt: r.dateOrNull('paid_at'),
  currency: r.str('currency', 'INR'),
  items: r.list(
    'items',
    (i) => PayrollItem(
      id: i.str('id'),
      fullName: i.str('full_name'),
      jobTitle: i.str('job_title'),
      payBasis: i.str('pay_basis'),
      payRate: i.number('pay_rate'),
      hours: i.number('hours'),
      baseAmount: i.number('base_amount'),
      bonus: i.number('bonus'),
      deductions: i.number('deductions'),
      netAmount: i.number('net_amount'),
      note: i.strOrNull('note'),
    ),
  ),
);

BudgetDashboard budgetFromJson(dynamic json) {
  final map = asJson(json);
  final totals = map.obj('totals');
  return BudgetDashboard(
    from: map.dayOrNull('from') ?? DateTime.now(),
    to: map.dayOrNull('to') ?? DateTime.now(),
    bucket: map.str('bucket', 'month'),
    currency: map.str('currency', 'INR'),
    income: totals.number('income'),
    expense: totals.number('expense'),
    recurringExpense: totals.number('recurring_expense'),
    series: map.list(
      'series',
      (b) => BudgetBucket(
        start: b.dayOrNull('bucket_start') ?? DateTime.now(),
        income: b.number('income'),
        expense: b.number('expense'),
      ),
    ),
    categories: map.list(
      'categories',
      (c) => CategoryTotal(
        direction: c.str('direction'),
        category: c.str('category'),
        amount: c.number('amount'),
        monthlyLimit: c.numberOrNull('monthly_limit'),
        periodLimit: c.numberOrNull('period_limit'),
      ),
    ),
    facilities: map.list(
      'facilities',
      (f) => FacilityTotal(
        facilityId: f.str('facility_id'),
        name: f.str('name'),
        tenure: f.str('tenure'),
        income: f.number('income'),
        expense: f.number('expense'),
      ),
    ),
    recurring: map.list(
      'recurring',
      (c) => RecurringCost(
        id: c.str('id'),
        category: c.str('category'),
        amount: c.number('amount'),
        cadence: c.str('cadence'),
        startsOn: c.dayOrNull('starts_on') ?? DateTime.now(),
        endsOn: c.dayOrNull('ends_on'),
        note: c.strOrNull('note'),
        isActive: c.flag('is_active', true),
        facilityId: c.strOrNull('facility_id'),
        facilityName: c.strOrNull('facility_name'),
      ),
    ),
    entries: map.list(
      'entries',
      (e) => LedgerLine(
        id: e.str('id'),
        occurredOn: e.dayOrNull('occurred_on') ?? DateTime.now(),
        direction: e.str('direction'),
        category: e.str('category'),
        amount: e.number('amount'),
        note: e.strOrNull('note'),
        recurring: e.flag('recurring'),
        facilityName: e.strOrNull('facility_name'),
        source: e.str('source', 'manual'),
      ),
    ),
  );
}

class FinanceRepositoryImpl implements FinanceRepository {
  FinanceRepositoryImpl(this._rpc);
  final Rpc _rpc;

  @override
  Future<Result<List<Employee>>> employees(String orgId) => _rpc.call(
    'org_employees',
    params: {'p_org_id': orgId},
    parse: (json) => parseList(
      json,
      (e) => Employee(
        id: e.str('id'),
        fullName: e.str('full_name'),
        jobTitle: e.str('job_title'),
        employmentType: e.str('employment_type'),
        payBasis: e.str('pay_basis'),
        payRate: e.number('pay_rate'),
        facilityId: e.strOrNull('facility_id'),
        facilityName: e.strOrNull('facility_name'),
        linkedName: e.strOrNull('linked_name'),
        joinedOn: e.dayOrNull('joined_on') ?? DateTime.now(),
        isActive: e.flag('is_active', true),
        paidTotal: e.number('paid_total'),
      ),
    ),
  );

  @override
  Future<Result<void>> saveEmployee(String orgId, Json employee) =>
      _rpc.run('org_employee_save', params: {'p_org_id': orgId, 'p_employee': employee});

  @override
  Future<Result<List<PayrollRun>>> payrollRuns(String orgId) =>
      _rpc.call('org_payroll_runs', params: {'p_org_id': orgId}, parse: (json) => parseList(json, _runFromJson));

  @override
  Future<Result<PayrollRun>> payrollRun(String runId) =>
      _rpc.call('org_payroll_run', params: {'p_run_id': runId}, parse: (json) => _runFromJson(asJson(json)));

  @override
  Future<Result<String>> createPayrollRun(String orgId, DateTime from, DateTime to) => _rpc.call(
    'org_payroll_run_create',
    params: {'p_org_id': orgId, 'p_from': isoDay(from), 'p_to': isoDay(to)},
    parse: (json) => asJson(json).str('id'),
  );

  @override
  Future<Result<void>> updatePayrollItem(String itemId, Json patch) =>
      _rpc.run('org_payroll_item_update', params: {'p_item_id': itemId, 'p_patch': patch});

  @override
  Future<Result<void>> setPayrollStatus(String runId, String status) =>
      _rpc.run('org_payroll_run_set_status', params: {'p_run_id': runId, 'p_status': status});

  @override
  Future<Result<void>> deletePayrollRun(String runId) => _rpc.run('org_payroll_run_delete', params: {'p_run_id': runId});

  @override
  Future<Result<BudgetDashboard>> budget(String orgId, {required DateTime from, required DateTime to, required String bucket}) =>
      _rpc.call(
        'org_budget_dashboard',
        params: {'p_org_id': orgId, 'p_from': isoDay(from), 'p_to': isoDay(to), 'p_bucket': bucket},
        parse: budgetFromJson,
      );

  @override
  Future<Result<void>> addLedgerEntry(String orgId, Json entry) =>
      _rpc.run('org_ledger_add', params: {'p_org_id': orgId, 'p_entry': entry});

  @override
  Future<Result<void>> deleteLedgerEntry(String entryId) => _rpc.run('org_ledger_delete', params: {'p_entry_id': entryId});

  @override
  Future<Result<void>> saveRecurringCost(String orgId, Json cost) =>
      _rpc.run('org_recurring_save', params: {'p_org_id': orgId, 'p_cost': cost});

  @override
  Future<Result<void>> deleteRecurringCost(String costId) => _rpc.run('org_recurring_delete', params: {'p_cost_id': costId});

  @override
  Future<Result<void>> setBudgetLimit(String orgId, String category, num? monthlyLimit) => _rpc.run(
    'org_budget_limit_set',
    params: {'p_org_id': orgId, 'p_category': category, 'p_monthly_limit': monthlyLimit},
  );
}
