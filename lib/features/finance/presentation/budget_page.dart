import 'package:fl_chart/fl_chart.dart';
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

const _incomeColor = Color(0xFF1B8A4B);
const _expenseColor = Color(0xFFD9730D);
const _cadences = {'weekly': 'Weekly', 'monthly': 'Monthly', 'quarterly': 'Quarterly', 'yearly': 'Yearly'};

Map<String, String> _labels(List<String> categories) => {for (final c in categories) c: Fmt.label(c)};

/// Where the money goes: recurring facility costs, one-off spend, payroll and
/// income, per week or month, against the limits the organisation sets.
class BudgetPage extends StatelessWidget {
  const BudgetPage({super.key, required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BudgetCubit(sl(), orgId)..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Budget')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addEntry(context),
            icon: const Icon(Icons.add),
            label: const Text('Add entry'),
          ),
          body: AsyncView<BudgetCubit, BudgetDashboard>(builder: (context, budget, _) => _BudgetView(budget)),
        ),
      ),
    );
  }
}

Map<String, String> _facilityChoices(BudgetDashboard? budget) => {for (final f in budget?.facilities ?? const <FacilityTotal>[]) f.facilityId: f.name};

Future<void> _addEntry(BuildContext context) async {
  final cubit = context.read<BudgetCubit>();
  final facilities = _facilityChoices(cubit.state.data);
  final result = await showFormSheet(
    context,
    title: 'Add an entry',
    description: 'For one-off money in or out. Rent and other repeating costs belong under recurring costs.',
    fields: [
      FieldSpec.choice('category', 'Category', {
        for (final c in expenseCategories) c: 'Spend · ${Fmt.label(c)}',
        for (final c in incomeCategories) c: 'Income · ${Fmt.label(c)}',
      }, initial: 'equipment'),
      const FieldSpec.number('amount', 'Amount', required: true),
      FieldSpec.date('occurred_on', 'Date', initial: DateTime.now(), required: true),
      if (facilities.isNotEmpty) FieldSpec.choice('facility_id', 'Facility', facilities, required: false),
      const FieldSpec.text('note', 'Note', hint: 'Shuttles, court resurfacing, sponsor'),
    ],
  );
  if (result == null) return;
  await cubit.addEntry({...result, 'direction': incomeCategories.contains(result['category']) ? 'income' : 'expense'});
}

Future<void> _editRecurring(BuildContext context, RecurringCost? cost) async {
  final cubit = context.read<BudgetCubit>();
  final facilities = _facilityChoices(cubit.state.data);
  final result = await showFormSheet(
    context,
    title: cost == null ? 'New recurring cost' : 'Edit recurring cost',
    description: 'Counted automatically in every period it falls in.',
    fields: [
      FieldSpec.choice('category', 'Category', _labels(recurringCategories), initial: cost?.category ?? 'rent'),
      FieldSpec.number('amount', 'Amount each time', initial: cost?.amount, required: true),
      FieldSpec.choice('cadence', 'Repeats', _cadences, initial: cost?.cadence ?? 'monthly'),
      FieldSpec.date('starts_on', 'First due', initial: cost?.startsOn ?? DateTime.now(), required: true),
      FieldSpec.date('ends_on', 'Last due', initial: cost?.endsOn, helper: 'Leave empty if it has no end date.'),
      if (facilities.isNotEmpty) FieldSpec.choice('facility_id', 'Facility', facilities, initial: cost?.facilityId, required: false),
      FieldSpec.text('note', 'Note', initial: cost?.note),
      if (cost != null) FieldSpec.toggle('is_active', 'Active', initial: cost.isActive),
    ],
  );
  if (result != null) await cubit.saveRecurring({...result, 'id': ?cost?.id});
}

class _BudgetView extends StatelessWidget {
  const _BudgetView(this.budget);
  final BudgetDashboard budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<BudgetCubit>();
    final currency = budget.currency;
    return ContentWidth(
      child: ListView(
        padding: pagePadding.copyWith(bottom: 96),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SegmentedButton<BudgetRange>(
                  showSelectedIcon: false,
                  segments: [for (final range in BudgetRange.values) ButtonSegment(value: range, label: Text(range.label))],
                  selected: {cubit.range},
                  onSelectionChanged: (selection) => cubit.show(range: selection.first),
                ),
                Gap.md,
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'week', label: Text('Weekly')), ButtonSegment(value: 'month', label: Text('Monthly'))],
                  selected: {cubit.bucket},
                  onSelectionChanged: (selection) => cubit.show(bucket: selection.first),
                ),
              ],
            ),
          ),
          Gap.lg,
          TileGrid(
            minTileWidth: 170,
            children: [
              StatTile(label: 'Income', value: Fmt.money(budget.income, currency), icon: Icons.south_west_rounded, color: _incomeColor),
              StatTile(label: 'Spend', value: Fmt.money(budget.expense, currency), icon: Icons.north_east_rounded, color: _expenseColor),
              StatTile(
                label: 'Net',
                value: Fmt.money(budget.net, currency),
                icon: Icons.account_balance_wallet_outlined,
                color: budget.net < 0 ? theme.colorScheme.error : _incomeColor,
              ),
              StatTile(label: 'Fixed costs', value: Fmt.money(budget.recurringExpense, currency), icon: Icons.autorenew_rounded),
            ],
          ),
          SectionHeader(cubit.bucket == 'week' ? 'Week by week' : 'Month by month'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
              child: Column(
                children: [
                  SizedBox(height: 200, child: _FlowChart(budget)),
                  Gap.sm,
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [_Legend(_incomeColor, 'Income'), SizedBox(width: 16), _Legend(_expenseColor, 'Spend')],
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader('Spend by category'),
          if (budget.expenseCategories.isEmpty)
            const _Muted('No spend in this period.')
          else
            Card(
              child: Column(
                children: [
                  for (final (index, category) in budget.expenseCategories.indexed) ...[
                    if (index > 0) const Divider(indent: 16, endIndent: 16),
                    _CategoryRow(category: category, currency: currency, total: budget.expense),
                  ],
                ],
              ),
            ),
          if (budget.incomeCategories.isNotEmpty) ...[
            const SectionHeader('Income by source'),
            Card(
              child: Column(
                children: [
                  for (final (index, category) in budget.incomeCategories.indexed) ...[
                    if (index > 0) const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      dense: true,
                      title: Text(Fmt.label(category.category)),
                      trailing: Text(Fmt.money(category.amount, currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (budget.facilities.isNotEmpty) ...[
            const SectionHeader('By facility'),
            for (final facility in budget.facilities)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(facility.tenure == 'owned' ? Icons.home_work_outlined : Icons.key_outlined),
                    title: Text(facility.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${Fmt.label(facility.tenure)} · costs ${Fmt.money(facility.expense, currency)} · earned ${Fmt.money(facility.income, currency)}'),
                    trailing: Text(
                      Fmt.money(facility.income - facility.expense, currency),
                      style: TextStyle(fontWeight: FontWeight.w700, color: facility.income - facility.expense < 0 ? theme.colorScheme.error : _incomeColor),
                    ),
                  ),
                ),
              ),
          ],
          SectionHeader(
            'Recurring costs',
            trailing: TextButton.icon(onPressed: () => _editRecurring(context, null), icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
          ),
          if (budget.recurring.isEmpty)
            const _Muted('Add rent, loan repayments, utilities and other costs that repeat.')
          else
            Card(
              child: Column(
                children: [
                  for (final (index, cost) in budget.recurring.indexed) ...[
                    if (index > 0) const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      title: Text(
                        '${Fmt.label(cost.category)}${cost.facilityName == null ? '' : ' · ${cost.facilityName}'}',
                        style: TextStyle(fontWeight: FontWeight.w600, decoration: cost.isActive ? null : TextDecoration.lineThrough),
                      ),
                      subtitle: Text(
                        [
                          _cadences[cost.cadence],
                          'from ${Fmt.dayYear(cost.startsOn)}',
                          if (cost.endsOn != null) 'until ${Fmt.dayYear(cost.endsOn)}',
                          if (cost.note != null) cost.note,
                        ].whereType<String>().join(' · '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(Fmt.money(cost.amount, currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                          PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                await _editRecurring(context, cost);
                              } else if (await confirm(context, title: 'Remove this recurring cost?', confirmLabel: 'Remove', destructive: true)) {
                                await cubit.deleteRecurring(cost);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Remove')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SectionHeader('Entries'),
          if (budget.entries.isEmpty)
            const _Muted('Nothing booked in this period.')
          else
            Card(
              child: Column(
                children: [
                  for (final (index, line) in budget.entries.take(60).indexed) ...[
                    if (index > 0) const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      dense: true,
                      leading: Icon(
                        line.direction == 'income' ? Icons.south_west_rounded : Icons.north_east_rounded,
                        color: line.direction == 'income' ? _incomeColor : _expenseColor,
                        size: 20,
                      ),
                      title: Text('${Fmt.label(line.category)}${line.note == null ? '' : ' · ${line.note}'}'),
                      subtitle: Text(
                        [
                          Fmt.dayYear(line.occurredOn),
                          line.facilityName,
                          if (line.source != 'manual') Fmt.label(line.source),
                        ].whereType<String>().join(' · '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${line.direction == 'income' ? '+' : '-'}${Fmt.money(line.amount, currency)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (line.source == 'manual')
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () async {
                                if (await confirm(context, title: 'Remove this entry?', confirmLabel: 'Remove', destructive: true)) {
                                  await cubit.deleteEntry(line);
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

/// A category's spend, with a bar against its budget when one is set.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.currency, required this.total});
  final CategoryTotal category;
  final String currency;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = category.usage;
    final over = usage != null && usage > 1;
    return InkWell(
      onTap: () => _setLimit(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(Fmt.label(category.category), style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(Fmt.money(category.amount, currency), style: TextStyle(fontWeight: FontWeight.w700, color: over ? theme.colorScheme.error : null)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: (usage ?? (total == 0 ? 0 : category.amount / total)).clamp(0, 1).toDouble(),
                color: over ? theme.colorScheme.error : (usage == null ? theme.colorScheme.outline : _expenseColor),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              usage == null
                  ? '${total == 0 ? 0 : (category.amount / total * 100).round()}% of spend · tap to set a budget'
                  : '${(usage * 100).round()}% of the ${Fmt.money(category.periodLimit!, currency)} budget for this period'
                        ' (${Fmt.money(category.monthlyLimit!, currency)} a month)',
              style: theme.textTheme.labelSmall?.copyWith(color: over ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setLimit(BuildContext context) async {
    final cubit = context.read<BudgetCubit>();
    final result = await showFormSheet(
      context,
      title: '${Fmt.label(category.category)} budget',
      description: 'A monthly limit for this category. Leave empty to remove it.',
      fields: [FieldSpec.number('limit', 'Monthly limit', initial: category.monthlyLimit)],
    );
    if (result != null) await cubit.setLimit(category.category, result['limit'] as num?);
  }
}

class _FlowChart extends StatelessWidget {
  const _FlowChart(this.budget);
  final BudgetDashboard budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = budget.series;
    final peak = series.fold<double>(0, (max, b) => [max, b.income, b.expense].reduce((a, b) => a > b ? a : b));
    final top = peak == 0 ? 100.0 : peak * 1.15;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    // Thin the x labels so they never collide.
    final step = (series.length / 8).ceil().clamp(1, 100);
    return BarChart(
      BarChartData(
        maxY: top,
        barGroups: [
          for (final (index, bucket) in series.indexed)
            BarChartGroupData(
              x: index,
              barsSpace: 3,
              barRods: [
                BarChartRodData(toY: bucket.income, color: _incomeColor, width: series.length > 14 ? 5 : 10, borderRadius: BorderRadius.circular(3)),
                BarChartRodData(toY: bucket.expense, color: _expenseColor, width: series.length > 14 ? 5 : 10, borderRadius: BorderRadius.circular(3)),
              ],
            ),
        ],
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: top / 4,
          getDrawingHorizontalLine: (_) => FlLine(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: top / 4,
              getTitlesWidget: (value, meta) =>
                  value >= top ? const SizedBox.shrink() : SideTitleWidget(meta: meta, child: Text(Fmt.compact(value), style: labelStyle)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= series.length || index % step != 0) return const SizedBox.shrink();
                final start = series[index].start;
                final text = budget.bucket == 'week' ? '${start.day}/${start.month}' : Fmt.month(start).substring(0, 3);
                return SideTitleWidget(meta: meta, child: Text(text, style: labelStyle));
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
              '${rodIndex == 0 ? 'Income' : 'Spend'}\n${Fmt.money(rod.toY, budget.currency)}',
              TextStyle(color: theme.colorScheme.onInverseSurface, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
