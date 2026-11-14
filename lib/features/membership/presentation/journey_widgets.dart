import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../domain/membership.dart';

class AttendanceCard extends StatelessWidget {
  const AttendanceCard(this.attendance, {super.key});
  final Attendance attendance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hours = attendance.minutes / 60;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 76,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: attendance.sessions == 0 ? 0 : attendance.rate,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                  Center(
                    child: Text(
                      attendance.sessions == 0 ? '-' : '${(attendance.rate * 100).round()}%',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            Gap.lg,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attendance', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    attendance.sessions == 0
                        ? 'No sessions logged yet.'
                        : '${attendance.present} of ${attendance.present + attendance.absent} sessions attended'
                              '${attendance.excused > 0 ? ' · ${attendance.excused} excused' : ''}',
                  ),
                  if (attendance.sessions > 0)
                    Text(
                      '${Fmt.number(hours)} h on court · ${attendance.last30Days} sessions in the last 30 days',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One metric: latest value, change since the first measurement, and trend.
class MetricCard extends StatelessWidget {
  const MetricCard(this.metric, {super.key});
  final MetricSeries metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trendColor = metric.improved
        ? const Color(0xFF1B8A4B)
        : metric.declined
        ? theme.colorScheme.error
        : theme.colorScheme.outline;
    final single = metric.points.length < 2;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(metric.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(Fmt.number(metric.latest), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 4),
                Text(metric.unit, style: theme.textTheme.bodySmall),
                const Spacer(),
                if (!single)
                  Row(
                    children: [
                      Icon(
                        metric.change == 0
                            ? Icons.trending_flat_rounded
                            : metric.change > 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 18,
                        color: trendColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${metric.change > 0 ? '+' : ''}${Fmt.number(metric.changePct)}%',
                        style: theme.textTheme.labelMedium?.copyWith(color: trendColor, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: single
                  ? Align(
                      alignment: Alignment.bottomLeft,
                      child: Text('First measurement', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (final (index, point) in metric.points.indexed) FlSpot(index.toDouble(), point.value),
                            ],
                            isCurved: true,
                            preventCurveOverShooting: true,
                            color: trendColor,
                            barWidth: 2.5,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: trendColor.withValues(alpha: 0.12)),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              single
                  ? Fmt.dayYear(metric.points.first.on)
                  : 'Started at ${Fmt.number(metric.first)} · best ${Fmt.number(metric.best)}',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportCard extends StatelessWidget {
  const ReportCard(this.report, {super.key});
  final ProgressReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget block(String title, String? text) => text == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
                Text(text),
              ],
            ),
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Fmt.range(report.periodStart, report.periodEnd),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (report.coachName != null)
                        Text('Coach ${report.coachName}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (report.rating != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      '${report.rating}/10',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
              ],
            ),
            Gap.md,
            Text(report.summary),
            block('Strengths', report.strengths),
            block('Focus next', report.focusAreas),
          ],
        ),
      ),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile(this.session, {super.key});
  final TrainingSession session;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(switch (session.attendance) {
        'present' => Icons.check_circle_rounded,
        'excused' => Icons.remove_circle_outline_rounded,
        _ => Icons.cancel_rounded,
      }, color: StatusChip.colorOf(session.attendance == 'present' ? 'active' : session.attendance == 'excused' ? 'pending' : 'cancelled', Theme.of(context).colorScheme)),
      title: Text(session.focus ?? Fmt.label(session.attendance)),
      subtitle: Text('${Fmt.dayYear(session.heldOn)} · ${session.minutes} min${session.notes == null ? '' : ' · ${session.notes}'}'),
    );
  }
}
