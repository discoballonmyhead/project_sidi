import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../domain/membership.dart';
import 'journey_widgets.dart';
import 'membership_cubits.dart';

/// The continuous performance report of a membership.
/// Members read it; with [coachView] the organisation's coaches write to it.
class JourneyPage extends StatelessWidget {
  const JourneyPage({super.key, required this.membershipId, this.coachView = false});
  final String membershipId;
  final bool coachView;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => JourneyCubit(sl(), membershipId, coachView: coachView)..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(coachView ? 'Member progress' : 'My journey')),
          floatingActionButton: coachView ? _CoachActions(context.read<JourneyCubit>()) : null,
          body: AsyncView<JourneyCubit, Journey>(builder: (context, journey, _) => _JourneyView(journey, coachView: coachView)),
        ),
      ),
    );
  }
}

class _JourneyView extends StatelessWidget {
  const _JourneyView(this.journey, {required this.coachView});
  final Journey journey;
  final bool coachView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membership = journey.membership;
    final sport = context.read<CatalogCubit>().state.data?.sportName(membership.sportCode);
    return ContentWidth(
      child: ListView(
        padding: pagePadding.copyWith(bottom: 96),
        children: [
          Row(
            children: [
              SportAvatar(membership.sportCode, size: 52),
              Gap.md,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coachView ? membership.memberName : membership.planName,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      [
                        coachView ? membership.planName : membership.orgName,
                        if (sport != null && sport.isNotEmpty) sport,
                        if (membership.coachName != null) 'Coach ${membership.coachName}',
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              StatusChip(membership.status),
            ],
          ),
          Gap.lg,
          AttendanceCard(journey.attendance),
          const SectionHeader('Performance'),
          if (journey.metrics.isEmpty)
            _Hint(coachView ? 'Record the first measurements to start the trend lines.' : 'Your coach has not recorded any measurements yet.')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 240).floor().clamp(1, 3);
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: ((constraints.maxWidth - (columns - 1) * 10) / columns) / 172,
                  children: [for (final metric in journey.metrics) MetricCard(metric)],
                );
              },
            ),
          const SectionHeader('Coach reports'),
          if (journey.reports.isEmpty)
            _Hint(coachView ? 'Publish a report to summarise this period for the member.' : 'Reports from your coach will appear here.')
          else
            for (final report in journey.reports) Padding(padding: const EdgeInsets.only(bottom: 10), child: ReportCard(report)),
          const SectionHeader('Sessions'),
          if (journey.sessions.isEmpty)
            const _Hint('No sessions logged yet.')
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(children: [for (final session in journey.sessions) SessionTile(session)]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );
}

class _CoachActions extends StatelessWidget {
  const _CoachActions(this.cubit);
  final JourneyCubit cubit;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, -8),
      builder: (context, controller, _) => FloatingActionButton.extended(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.add),
        label: const Text('Record'),
      ),
      menuChildren: [
        MenuItemButton(leadingIcon: const Icon(Icons.event_available_outlined), onPressed: () => _session(context), child: const Text('Log a session')),
        MenuItemButton(leadingIcon: const Icon(Icons.speed_outlined), onPressed: () => _metrics(context), child: const Text('Record measurements')),
        MenuItemButton(leadingIcon: const Icon(Icons.description_outlined), onPressed: () => _report(context), child: const Text('Publish a report')),
        MenuItemButton(leadingIcon: const Icon(Icons.add_chart_outlined), onPressed: () => _metric(context), child: const Text('Add a custom metric')),
      ],
    );
  }

  Future<void> _session(BuildContext context) async {
    final result = await showFormSheet(
      context,
      title: 'Log a session',
      fields: [
        FieldSpec.date('held_on', 'Date', initial: DateTime.now(), required: true),
        const FieldSpec.choice('attendance', 'Attendance', {'present': 'Present', 'absent': 'Absent', 'excused': 'Excused'}, initial: 'present'),
        const FieldSpec.integer('minutes', 'Length (minutes)', initial: 60, required: true),
        const FieldSpec.text('focus', 'Focus', hint: 'Footwork, net play, batting against spin'),
        const FieldSpec.multiline('notes', 'Notes'),
      ],
    );
    if (result != null) await cubit.logSession(result);
  }

  Future<void> _metrics(BuildContext context) async {
    final metrics = cubit.state.data?.availableMetrics ?? const [];
    if (metrics.isEmpty) {
      cubit.say('No metrics defined for this sport. Add a custom metric first.', isError: true);
      return;
    }
    final result = await showFormSheet(
      context,
      title: 'Record measurements',
      description: 'Fill in what you measured today; leave the rest empty.',
      fields: [
        FieldSpec.date('on', 'Measured on', initial: DateTime.now(), required: true),
        for (final metric in metrics) FieldSpec.number(metric.id, metric.unit.isEmpty ? metric.name : '${metric.name} (${metric.unit})'),
      ],
    );
    if (result == null) return;
    final values = {
      for (final metric in metrics)
        if (result[metric.id] is num) metric.id: result[metric.id] as num,
    };
    if (values.isEmpty) {
      cubit.say('Enter at least one measurement.', isError: true);
      return;
    }
    await cubit.recordMetrics(values, on: DateTime.tryParse(result['on'] as String? ?? ''));
  }

  Future<void> _report(BuildContext context) async {
    final now = DateTime.now();
    final result = await showFormSheet(
      context,
      title: 'Progress report',
      description: 'The member is notified and sees this in their journey.',
      submitLabel: 'Publish',
      fields: [
        FieldSpec.date('period_start', 'From', initial: DateTime(now.year, now.month - 1, now.day), required: true),
        FieldSpec.date('period_end', 'To', initial: now, required: true),
        const FieldSpec.integer('rating', 'Overall rating (1-10)'),
        const FieldSpec.multiline('summary', 'Summary', required: true),
        const FieldSpec.multiline('strengths', 'Strengths'),
        const FieldSpec.multiline('focus_areas', 'Focus next'),
      ],
    );
    if (result != null) await cubit.publishReport(result);
  }

  Future<void> _metric(BuildContext context) async {
    final catalog = context.read<CatalogCubit>().state.data;
    final sport = cubit.state.data?.membership.sportCode;
    final result = await showFormSheet(
      context,
      title: 'Custom metric',
      fields: [
        const FieldSpec.text('name', 'Name', required: true, hint: 'Backhand clear distance'),
        const FieldSpec.text('unit', 'Unit', hint: 'm, s, %, reps'),
        FieldSpec.choice('sport_code', 'Sport', {for (final s in catalog?.sports ?? const []) s.code: s.name}, initial: sport),
        const FieldSpec.toggle('higher_is_better', 'Higher is better', initial: true),
      ],
    );
    if (result != null) await cubit.defineMetric(result);
  }
}

