class Employee {
  const Employee({
    required this.id,
    required this.fullName,
    required this.jobTitle,
    required this.employmentType,
    required this.payBasis,
    required this.payRate,
    this.facilityId,
    this.facilityName,
    this.linkedName,
    required this.joinedOn,
    required this.isActive,
    required this.paidTotal,
  });

  final String id;
  final String fullName;
  final String jobTitle;
  final String employmentType;

  /// `hourly`, `weekly` or `monthly`.
  final String payBasis;
  final double payRate;
  final String? facilityId;
  final String? facilityName;
  final String? linkedName;
  final DateTime joinedOn;
  final bool isActive;
  final double paidTotal;
}

class PayrollItem {
  const PayrollItem({
    required this.id,
    required this.fullName,
    required this.jobTitle,
    required this.payBasis,
    required this.payRate,
    required this.hours,
    required this.baseAmount,
    required this.bonus,
    required this.deductions,
    required this.netAmount,
    this.note,
  });

  final String id;
  final String fullName;
  final String jobTitle;
  final String payBasis;
  final double payRate;
  final double hours;
  final double baseAmount;
  final double bonus;
  final double deductions;
  final double netAmount;
  final String? note;
}

class PayrollRun {
  const PayrollRun({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.total,
    required this.headcount,
    this.paidAt,
    this.currency = 'INR',
    this.items = const [],
  });

  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;

  /// `draft`, `approved` or `paid`.
  final String status;
  final double total;
  final int headcount;
  final DateTime? paidAt;
  final String currency;
  final List<PayrollItem> items;
}

class BudgetBucket {
  const BudgetBucket({required this.start, required this.income, required this.expense});
  final DateTime start;
  final double income;
  final double expense;
}

class CategoryTotal {
  const CategoryTotal({required this.direction, required this.category, required this.amount, this.monthlyLimit, this.periodLimit});
  final String direction;
  final String category;
  final double amount;
  final double? monthlyLimit;
  final double? periodLimit;

  /// Share of the period's budget used, when a limit is set.
  double? get usage => (periodLimit == null || periodLimit == 0) ? null : amount / periodLimit!;
}

class FacilityTotal {
  const FacilityTotal({required this.facilityId, required this.name, required this.tenure, required this.income, required this.expense});
  final String facilityId;
  final String name;
  final String tenure;
  final double income;
  final double expense;
}

class RecurringCost {
  const RecurringCost({
    required this.id,
    required this.category,
    required this.amount,
    required this.cadence,
    required this.startsOn,
    this.endsOn,
    this.note,
    required this.isActive,
    this.facilityId,
    this.facilityName,
  });

  final String id;
  final String category;
  final double amount;
  final String cadence;
  final DateTime startsOn;
  final DateTime? endsOn;
  final String? note;
  final bool isActive;
  final String? facilityId;
  final String? facilityName;
}

class LedgerLine {
  const LedgerLine({
    required this.id,
    required this.occurredOn,
    required this.direction,
    required this.category,
    required this.amount,
    this.note,
    required this.recurring,
    this.facilityName,
    required this.source,
  });

  final String id;
  final DateTime occurredOn;
  final String direction;
  final String category;
  final double amount;
  final String? note;
  final bool recurring;
  final String? facilityName;

  /// `manual`, `payment`, `payroll` or `recurring`. Only manual lines can be deleted.
  final String source;
}

class BudgetDashboard {
  const BudgetDashboard({
    required this.from,
    required this.to,
    required this.bucket,
    required this.currency,
    required this.income,
    required this.expense,
    required this.recurringExpense,
    required this.series,
    required this.categories,
    required this.facilities,
    required this.recurring,
    required this.entries,
  });

  final DateTime from;
  final DateTime to;
  final String bucket;
  final String currency;
  final double income;
  final double expense;
  final double recurringExpense;
  final List<BudgetBucket> series;
  final List<CategoryTotal> categories;
  final List<FacilityTotal> facilities;
  final List<RecurringCost> recurring;
  final List<LedgerLine> entries;

  double get net => income - expense;
  List<CategoryTotal> get expenseCategories => categories.where((c) => c.direction == 'expense').toList();
  List<CategoryTotal> get incomeCategories => categories.where((c) => c.direction == 'income').toList();
}

/// Categories offered when booking money by hand.
const expenseCategories = [
  'rent', 'mortgage', 'utilities', 'maintenance', 'equipment', 'marketing', 'tournament_costs', 'insurance', 'taxes', 'other',
];
const incomeCategories = ['bookings', 'memberships', 'tournaments', 'sponsorship', 'other_income'];
const recurringCategories = ['rent', 'mortgage', 'utilities', 'maintenance', 'equipment', 'marketing', 'insurance', 'taxes', 'other'];
