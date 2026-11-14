import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../../catalog/domain/catalog.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../organization/domain/organization.dart';
import '../domain/admin.dart';
import 'admin_cubits.dart';

/// The admin console: a self-contained app inside the app for platform
/// staff. Moderators work the queues; admins also manage roles and features.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AdminOverviewCubit(sl())..load()),
        BlocProvider(create: (_) => AdminRequestsCubit(sl())..load()),
        BlocProvider(create: (_) => AdminOrgsCubit(sl())..load()),
        BlocProvider(create: (_) => AdminReportsCubit(sl())..load()),
        BlocProvider(create: (_) => AdminUsersCubit(sl())..load()),
        BlocProvider(create: (_) => AdminAuditCubit(sl())..load()),
      ],
      child: DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Admin console'),
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Requests'),
                Tab(text: 'Organisations'),
                Tab(text: 'Reports'),
                Tab(text: 'People'),
                Tab(text: 'Audit log'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [_OverviewTab(), _RequestsTab(), _OrgsTab(), _ReportsTab(), _UsersTab(), _AuditTab()],
          ),
        ),
      ),
    );
  }
}

/// Asks for the note that goes back to the organisation.
Future<String?> _askNote(BuildContext context, {required String title, required String label, bool required = true, String? description}) async {
  final result = await showFormSheet(
    context,
    title: title,
    description: description,
    submitLabel: 'Confirm',
    fields: [FieldSpec.multiline('note', label, required: required)],
  );
  if (result == null) return null;
  return result['note'] as String? ?? '';
}

// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) {
    return AsyncView<AdminOverviewCubit, AdminOverview>(
      builder: (context, o, _) {
        void go(int tab) => DefaultTabController.of(context).animateTo(tab);
        return ContentWidth(
          child: ListView(
            padding: pagePadding,
            children: [
              Text(
                'Signed in as ${o.isAdmin ? 'admin' : 'moderator'}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SectionHeader('Waiting for you'),
              TileGrid(
                children: [
                  StatTile(label: 'New organisations', value: '${o.pendingApprovals}', icon: Icons.domain_add_outlined, onTap: () => go(1)),
                  StatTile(label: 'Verifications', value: '${o.pendingVerifications}', icon: Icons.verified_outlined, onTap: () => go(1)),
                  StatTile(label: 'Feature requests', value: '${o.pendingFeatures}', icon: Icons.extension_outlined, onTap: () => go(1)),
                  StatTile(
                    label: 'Open reports',
                    value: '${o.openReports}',
                    icon: Icons.flag_outlined,
                    color: o.openReports > 0 ? Theme.of(context).colorScheme.error : null,
                    onTap: () => go(3),
                  ),
                ],
              ),
              const SectionHeader('Platform'),
              TileGrid(
                children: [
                  StatTile(label: 'Organisations', value: '${o.orgApproved} / ${o.orgTotal}', icon: Icons.apartment_outlined, onTap: () => go(2)),
                  StatTile(label: 'Verified', value: '${o.orgVerified}', icon: Icons.verified_rounded),
                  StatTile(label: 'Suspended', value: '${o.orgSuspended}', icon: Icons.block_outlined),
                  StatTile(label: 'People', value: '${o.users}', icon: Icons.people_alt_outlined, onTap: () => go(4)),
                  StatTile(label: 'Tournaments running', value: '${o.tournamentsLive}', icon: Icons.emoji_events_outlined),
                  StatTile(label: 'Bookings, 7 days', value: '${o.bookings7d}', icon: Icons.event_available_outlined),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  static const _kinds = {null: 'All', 'org_approval': 'New organisations', 'org_verification': 'Verification', 'feature_access': 'Features'};

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminRequestsCubit>();
    return AsyncView<AdminRequestsCubit, List<AccessRequest>>(
      refreshable: false,
      builder: (context, requests, _) => ContentWidth(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [ButtonSegment(value: true, label: Text('Queue')), ButtonSegment(value: false, label: Text('History'))],
                      selected: {cubit.status == 'pending'},
                      onSelectionChanged: (s) => cubit.filter(status: () => s.first ? 'pending' : null),
                    ),
                  ),
                  for (final kind in _kinds.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(kind.value), selected: cubit.kind == kind.key, onSelected: (_) => cubit.filter(kind: () => kind.key)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: cubit.load,
                child: requests.isEmpty
                    ? EmptyState(
                        icon: Icons.inbox_outlined,
                        title: cubit.status == 'pending' ? 'The queue is empty' : 'Nothing decided yet',
                      )
                    : ListView.separated(
                        padding: pagePadding,
                        itemCount: requests.length,
                        separatorBuilder: (_, _) => Gap.md,
                        itemBuilder: (context, index) => _RequestCard(requests[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.request);
  final AccessRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<AdminRequestsCubit>();
    final overview = context.read<AdminOverviewCubit>();
    final catalog = context.read<CatalogCubit>().state.data;
    final pending = request.status == 'pending';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(switch (request.kind) {
                  'org_approval' => Icons.domain_add_outlined,
                  'org_verification' => Icons.verified_outlined,
                  _ => Icons.extension_outlined,
                }, color: theme.colorScheme.primary),
                Gap.sm,
                Expanded(child: Text(request.title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary))),
                if (!pending) StatusChip(request.status),
              ],
            ),
            Gap.sm,
            Row(
              children: [
                Flexible(child: Text(request.orgName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                if (request.orgIsVerified) ...[Gap.xs, const VerifiedBadge()],
              ],
            ),
            Text(
              [
                request.orgCity,
                request.orgSports.map((s) => catalog?.sportName(s) ?? s).join(', '),
                'by ${request.requesterName}',
                Fmt.dayYear(request.createdAt),
              ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (request.message != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(request.message!)),
            for (final document in request.documents)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 16),
                    Gap.sm,
                    Expanded(child: SelectableText(document, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
            if (!pending && (request.decisionNote != null || request.decidedByName != null))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  [
                    if (request.decidedByName != null) 'Decided by ${request.decidedByName}',
                    if (request.decisionNote != null) '"${request.decisionNote}"',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (pending) ...[
              Gap.md,
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      final note = await _askNote(
                        context,
                        title: 'Reject this request?',
                        label: 'Reason',
                        description: 'The organisation sees this note.',
                      );
                      if (note == null) return;
                      if (await cubit.decide(request, approve: false, note: note)) await overview.load();
                    },
                    child: const Text('Reject'),
                  ),
                  Gap.sm,
                  FilledButton(
                    onPressed: () async {
                      final note = await _askNote(context, title: 'Approve ${request.orgName}?', label: 'Note (optional)', required: false);
                      if (note == null) return;
                      if (await cubit.decide(request, approve: true, note: note.isEmpty ? null : note)) await overview.load();
                    },
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SearchField extends StatefulWidget {
  const _SearchField({required this.hint, required this.onSearch});
  final String hint;
  final ValueChanged<String> onSearch;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: TextField(
      decoration: InputDecoration(hintText: widget.hint, prefixIcon: const Icon(Icons.search)),
      onChanged: (text) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350), () => widget.onSearch(text));
      },
    ),
  );
}

class _OrgsTab extends StatelessWidget {
  const _OrgsTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminOrgsCubit>();
    return ContentWidth(
      child: Column(
        children: [
          _SearchField(hint: 'Search organisations', onSearch: (text) => cubit.search(query: text)),
          Expanded(
            child: AsyncView<AdminOrgsCubit, List<AdminOrg>>(
              builder: (context, orgs, _) => orgs.isEmpty
                  ? const EmptyState(icon: Icons.apartment_outlined, title: 'No organisations found')
                  : ListView.separated(
                      padding: pagePadding,
                      itemCount: orgs.length,
                      separatorBuilder: (_, _) => Gap.sm,
                      itemBuilder: (context, index) => _OrgTile(orgs[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrgTile extends StatelessWidget {
  const _OrgTile(this.org);
  final AdminOrg org;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminOrgsCubit>();
    final features = context.read<CatalogCubit>().state.data?.features ?? const <FeatureDef>[];
    final isAdmin = context.select<AdminOverviewCubit, bool>((c) => c.state.data?.isAdmin ?? false);
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: Row(
          children: [
            Flexible(child: Text(org.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (org.isVerified) ...[Gap.xs, const VerifiedBadge()],
          ],
        ),
        subtitle: Text([org.city, 'owner ${org.ownerName}', if (org.openReports > 0) '${org.openReports} open reports'].whereType<String>().join(' · ')),
        trailing: StatusChip(org.status),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (org.contactEmail != null) Text(org.contactEmail!, style: Theme.of(context).textTheme.bodySmall),
          Gap.sm,
          Text('Features', style: Theme.of(context).textTheme.labelLarge),
          Gap.xs,
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final feature in features)
                FilterChip(
                  label: Text(feature.name),
                  selected: org.features.contains(feature.key),
                  // Only admins flip features directly; moderators use the queue.
                  onSelected: isAdmin ? (on) => cubit.setFeature(org, feature.key, enabled: on) : null,
                ),
            ],
          ),
          Gap.md,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: () => context.push('/org/${org.id}'), child: const Text('Open page')),
              if (org.status == 'approved')
                OutlinedButton(
                  onPressed: () async {
                    final note = await _askNote(context, title: 'Suspend ${org.name}?', label: 'Reason', description: 'It is hidden and cannot take bookings.');
                    if (note != null) await cubit.moderate(org, 'suspend', note: note);
                  },
                  child: const Text('Suspend'),
                ),
              if (org.status == 'suspended' || org.status == 'rejected')
                OutlinedButton(onPressed: () => cubit.moderate(org, 'reinstate'), child: const Text('Reinstate')),
              if (org.status == 'approved' && !org.isVerified)
                OutlinedButton(onPressed: () => cubit.moderate(org, 'verify'), child: const Text('Mark verified')),
              if (org.isVerified)
                OutlinedButton(
                  onPressed: () async {
                    final note = await _askNote(context, title: 'Remove verification?', label: 'Reason');
                    if (note != null) await cubit.moderate(org, 'unverify', note: note);
                  },
                  child: const Text('Remove verification'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminReportsCubit>();
    return AsyncView<AdminReportsCubit, List<ContentReport>>(
      refreshable: false,
      builder: (context, reports, _) => ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  for (final filter in const {'open': 'Open', 'actioned': 'Actioned', 'dismissed': 'Dismissed'}.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(filter.value), selected: cubit.status == filter.key, onSelected: (_) => cubit.filter(filter.key)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: cubit.load,
                child: reports.isEmpty
                    ? const EmptyState(icon: Icons.flag_outlined, title: 'No reports here')
                    : ListView.separated(
                        padding: pagePadding,
                        itemCount: reports.length,
                        separatorBuilder: (_, _) => Gap.md,
                        itemBuilder: (context, index) => _ReportCard(reports[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard(this.report);
  final ContentReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<AdminReportsCubit>();
    final canTakeDown = report.targetType != 'user';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${Fmt.label(report.targetType)} · ${report.targetName ?? 'removed'}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (report.status != 'open') StatusChip(report.status == 'actioned' ? 'approved' : 'info', label: Fmt.label(report.status)),
              ],
            ),
            Text('Reported by ${report.reporterName} · ${Fmt.dayYear(report.createdAt)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Gap.sm,
            Text(report.reason),
            if (report.resolution != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Resolution: ${report.resolution}', style: theme.textTheme.bodySmall)),
            if (report.status == 'open') ...[
              Gap.md,
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (report.targetType != 'user')
                    OutlinedButton(
                      onPressed: () => context.push(report.targetType == 'tournament' ? '/tournament/${report.targetId}' : '/org/${report.targetId}'),
                      child: const Text('Open'),
                    ),
                  TextButton(onPressed: () => cubit.resolve(report, actioned: false), child: const Text('Dismiss')),
                  if (canTakeDown)
                    FilledButton.tonal(
                      onPressed: () async {
                        final note = await _askNote(
                          context,
                          title: report.targetType == 'tournament' ? 'Cancel this tournament?' : 'Suspend this organisation?',
                          label: 'Reason',
                          description: 'The organisation is told why.',
                        );
                        if (note != null) await cubit.takeDown(report, note);
                      },
                      child: Text(report.targetType == 'tournament' ? 'Cancel tournament' : 'Suspend organisation'),
                    )
                  else
                    FilledButton.tonal(onPressed: () => cubit.resolve(report, actioned: true), child: const Text('Mark actioned')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminUsersCubit>();
    final isAdmin = context.select<AdminOverviewCubit, bool>((c) => c.state.data?.isAdmin ?? false);
    return ContentWidth(
      child: Column(
        children: [
          _SearchField(hint: 'Search by name, username or e-mail', onSearch: cubit.search),
          Expanded(
            child: AsyncView<AdminUsersCubit, List<AdminUser>>(
              builder: (context, users, _) => users.isEmpty
                  ? const EmptyState(icon: Icons.person_search_outlined, title: 'Nobody found')
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: users.length,
                      separatorBuilder: (_, _) => const Divider(indent: 72),
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return ListTile(
                          leading: CircleAvatar(child: Text(user.displayName.characters.first.toUpperCase())),
                          title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [user.email, if (user.username != null) '@${user.username}', if (user.orgCount > 0) '${user.orgCount} org${user.orgCount == 1 ? '' : 's'}']
                                .whereType<String>()
                                .join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (user.platformRole != null) StatusChip('approved', label: Fmt.label(user.platformRole!)),
                              if (isAdmin)
                                PopupMenuButton<String>(
                                  onSelected: (value) => cubit.setRole(user, value == 'none' ? null : value),
                                  itemBuilder: (_) => [
                                    if (user.platformRole != 'moderator') const PopupMenuItem(value: 'moderator', child: Text('Make moderator')),
                                    if (user.platformRole != 'admin') const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                                    if (user.platformRole != null) const PopupMenuItem(value: 'none', child: Text('Remove staff role')),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditTab extends StatelessWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context) {
    return AsyncView<AdminAuditCubit, List<AuditEntry>>(
      builder: (context, entries, _) => entries.isEmpty
          ? const EmptyState(icon: Icons.history_rounded, title: 'Nothing logged yet')
          : ContentWidth(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 32),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final details = entry.data.entries.where((e) => e.value != null).map((e) => '${e.key}: ${e.value}').join(' · ');
                  return ListTile(
                    dense: true,
                    title: Text(entry.action, style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                    subtitle: Text([entry.actorName ?? 'system', Fmt.dayTime(entry.createdAt), if (details.isNotEmpty) details].join(' · ')),
                  );
                },
              ),
            ),
    );
  }
}
