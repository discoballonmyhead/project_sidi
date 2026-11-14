import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../domain/finance.dart';
import 'finance_cubits.dart';

const employmentTypes = {'full_time': 'Full-time', 'part_time': 'Part-time', 'contract': 'Contract'};
const payBases = {'monthly': 'Monthly salary', 'weekly': 'Weekly wage', 'hourly': 'Hourly rate'};

/// Employees on the payroll: coaches, front desk, ground staff.
class StaffPage extends StatelessWidget {
  const StaffPage({super.key, required this.orgId, required this.currency});
  final String orgId;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => EmployeesCubit(sl(), orgId)..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Staff')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Add employee'),
          ),
          body: AsyncView<EmployeesCubit, List<Employee>>(
            builder: (context, employees, _) => employees.isEmpty
                ? const EmptyState(
                    icon: Icons.badge_outlined,
                    title: 'No employees yet',
                    message: 'Add the people you pay. Each pay run starts from their salary or hourly rate.',
                  )
                : ContentWidth(
                    child: ListView.separated(
                      padding: pagePadding.copyWith(bottom: 96),
                      itemCount: employees.length,
                      separatorBuilder: (_, _) => Gap.sm,
                      itemBuilder: (context, index) {
                        final employee = employees[index];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text(employee.fullName.characters.first.toUpperCase())),
                            title: Text(employee.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              [
                                employee.jobTitle,
                                employmentTypes[employee.employmentType],
                                if (!employee.isActive) 'Left',
                                if (employee.paidTotal > 0) 'paid ${Fmt.money(employee.paidTotal, currency)} to date',
                              ].whereType<String>().join(' · '),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(Fmt.money(employee.payRate, currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(switch (employee.payBasis) {
                                  'hourly' => 'per hour',
                                  'weekly' => 'per week',
                                  _ => 'per month',
                                }, style: Theme.of(context).textTheme.labelSmall),
                              ],
                            ),
                            onTap: () => _edit(context, employee),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Employee? employee) async {
    final cubit = context.read<EmployeesCubit>();
    final result = await showFormSheet(
      context,
      title: employee == null ? 'New employee' : 'Edit employee',
      fields: [
        FieldSpec.text('full_name', 'Full name', initial: employee?.fullName, required: true),
        FieldSpec.text('job_title', 'Job title', initial: employee?.jobTitle, hint: 'Head coach, front desk'),
        FieldSpec.choice('employment_type', 'Employment', employmentTypes, initial: employee?.employmentType ?? 'full_time'),
        FieldSpec.choice('pay_basis', 'Paid by', payBases, initial: employee?.payBasis ?? 'monthly'),
        FieldSpec.number('pay_rate', 'Rate', initial: employee?.payRate, required: true, helper: 'Per month, week or hour, matching the choice above.'),
        FieldSpec.date('joined_on', 'Joined on', initial: employee?.joinedOn ?? DateTime.now(), required: true),
        if (employee != null) FieldSpec.toggle('is_active', 'Currently employed', initial: employee.isActive),
      ],
    );
    if (result != null) await cubit.save({...result, 'id': ?employee?.id});
  }
}
