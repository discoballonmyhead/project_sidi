import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../domain/finance.dart';
import 'finance_cubits.dart';

class PayrollPage extends StatelessWidget {
  const PayrollPage({super.key, required this.orgId, required this.currency});
  final String orgId;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PayrollRunsCubit(sl(), orgId)..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Payroll')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('New pay run'),
          ),
          body: AsyncView<PayrollRunsCubit, List<PayrollRun>>(
            builder: (context, runs, _) => runs.isEmpty
                ? const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No pay runs yet',
                    message: 'A pay run lists what each employee is owed for a period. Approve it, pay it, and it lands in your budget.',
                  )
                : ContentWidth(
                    child: ListView.separated(
                      padding: pagePadding.copyWith(bottom: 96),
                      itemCount: runs.length,
                      separatorBuilder: (_, _) => Gap.sm,
                      itemBuilder: (context, index) {
                        final run = runs[index];
                        return Card(
                          child: ListTile(
                            title: Text(Fmt.range(run.periodStart, run.periodEnd), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${run.headcount} employee${run.headcount == 1 ? '' : 's'}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(Fmt.money(run.total, currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    StatusChip(run.status),
                                  ],
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                            onTap: () async {
                              final cubit = context.read<PayrollRunsCubit>();
                              await context.push('/manage/$orgId/payroll/${run.id}');
                              await cubit.load();
                            },
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

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<PayrollRunsCubit>();
    final router = GoRouter.of(context);
    final now = DateTime.now();
    final result = await showFormSheet(
      context,
      title: 'New pay run',
      description: 'Salaries are pro-rated for the period. Hourly staff are filled in on the next screen.',
      submitLabel: 'Create draft',
      fields: [
        FieldSpec.date('from', 'Period start', initial: DateTime(now.year, now.month), required: true),
        FieldSpec.date('to', 'Period end', initial: DateTime(now.year, now.month + 1, 0), required: true),
      ],
    );
    if (result == null) return;
    final id = await cubit.create(DateTime.parse(result['from'] as String), DateTime.parse(result['to'] as String));
    if (id != null) {
      await router.push('/manage/$orgId/payroll/$id');
      await cubit.load();
    }
  }
}

class PayrollRunPage extends StatelessWidget {
  const PayrollRunPage({super.key, required this.runId});
  final String runId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PayrollRunCubit(sl(), runId)..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Pay run')),
        body: AsyncView<PayrollRunCubit, PayrollRun>(
          refreshable: false,
          builder: (context, run, state) => _RunView(run, busy: state.busy),
        ),
      ),
    );
  }
}

class _RunView extends StatelessWidget {
  const _RunView(this.run, {required this.busy});
  final PayrollRun run;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<PayrollRunCubit>();
    final draft = run.status == 'draft';
    return ContentWidth(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: pagePadding,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(Fmt.range(run.periodStart, run.periodEnd), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          Text(
                            run.status == 'paid' ? 'Paid ${Fmt.dayYear(run.paidAt)}' : '${run.headcount} employees',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(run.status),
                  ],
                ),
                Gap.lg,
                if (run.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: EmptyState(icon: Icons.badge_outlined, title: 'No active employees in this period'),
                  ),
                for (final item in run.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Text(item.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            item.jobTitle,
                            if (item.payBasis == 'hourly') '${Fmt.number(item.hours)} h × ${Fmt.money(item.payRate, run.currency)}',
                            if (item.bonus > 0) '+${Fmt.money(item.bonus, run.currency)} bonus',
                            if (item.deductions > 0) '-${Fmt.money(item.deductions, run.currency)} deductions',
                            if (item.note != null) item.note,
                          ].whereType<String>().join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(Fmt.money(item.netAmount, run.currency), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            if (draft) ...[Gap.sm, const Icon(Icons.edit_outlined, size: 18)],
                          ],
                        ),
                        onTap: draft ? () => _editItem(context, item) : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Material(
            elevation: 8,
            color: theme.colorScheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Total', style: theme.textTheme.labelMedium),
                          Text(Fmt.money(run.total, run.currency), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    if (draft) ...[
                      IconButton(
                        tooltip: 'Delete draft',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: busy
                            ? null
                            : () async {
                                final navigator = Navigator.of(context);
                                if (await confirm(context, title: 'Delete this draft?', confirmLabel: 'Delete', destructive: true)) {
                                  if (await cubit.delete()) navigator.pop();
                                }
                              },
                      ),
                      Gap.sm,
                      FilledButton(onPressed: busy ? null : () => cubit.setStatus('approved'), child: const Text('Approve')),
                    ] else if (run.status == 'approved') ...[
                      TextButton(onPressed: busy ? null : () => cubit.setStatus('draft'), child: const Text('Back to draft')),
                      Gap.sm,
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                final ok = await confirm(
                                  context,
                                  title: 'Mark as paid?',
                                  message: '${Fmt.money(run.total, run.currency)} is booked as a payroll expense today. This cannot be undone.',
                                  confirmLabel: 'Mark as paid',
                                );
                                if (ok) await cubit.setStatus('paid');
                              },
                        child: const Text('Mark as paid'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editItem(BuildContext context, PayrollItem item) async {
    final cubit = context.read<PayrollRunCubit>();
    final hourly = item.payBasis == 'hourly';
    final result = await showFormSheet(
      context,
      title: item.fullName,
      fields: [
        if (hourly)
          FieldSpec.number('hours', 'Hours worked', initial: item.hours, required: true, helper: 'Paid at ${Fmt.number(item.payRate)} per hour.')
        else
          FieldSpec.number('base_amount', 'Base pay for the period', initial: item.baseAmount, required: true),
        FieldSpec.number('bonus', 'Bonus', initial: item.bonus),
        FieldSpec.number('deductions', 'Deductions', initial: item.deductions),
        FieldSpec.text('note', 'Note', initial: item.note),
      ],
    );
    if (result == null) return;
    await cubit.updateItem(item, {
      for (final entry in result.entries)
        // Empty amounts mean zero; an empty note clears it.
        entry.key: entry.value ?? (entry.key == 'note' ? null : 0),
    });
  }
}
