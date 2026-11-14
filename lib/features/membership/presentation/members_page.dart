import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../../organization/domain/organization.dart';
import '../domain/membership.dart';
import 'membership_cubits.dart';

/// Membership requests, members and mentees of an organisation.
class MembersPage extends StatelessWidget {
  const MembersPage({super.key, required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MembersCubit(sl(), sl(), orgId)..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Members & mentees')),
        body: AsyncView<MembersCubit, MembersData>(
          builder: (context, data, _) {
            if (data.memberships.isEmpty) {
              return const EmptyState(
                icon: Icons.groups_2_outlined,
                title: 'No members yet',
                message: 'People who join one of your plans appear here for approval.',
              );
            }
            final pending = data.memberships.where((m) => m.status == 'pending').toList();
            final live = data.memberships.where((m) => m.status == 'active' || m.status == 'paused').toList();
            final past = data.memberships.where((m) => !const {'pending', 'active', 'paused'}.contains(m.status)).toList();
            return ContentWidth(
              child: ListView(
                padding: pagePadding,
                children: [
                  if (pending.isNotEmpty) ...[
                    const SectionHeader('Waiting for approval'),
                    for (final m in pending) _MemberTile(m, team: data.team, orgId: orgId),
                  ],
                  if (live.isNotEmpty) ...[
                    const SectionHeader('Members'),
                    for (final m in live) _MemberTile(m, team: data.team, orgId: orgId),
                  ],
                  if (past.isNotEmpty) ...[
                    const SectionHeader('Past'),
                    for (final m in past) _MemberTile(m, team: data.team, orgId: orgId),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile(this.membership, {required this.team, required this.orgId});
  final Membership membership;
  final List<TeamMember> team;
  final String orgId;

  Map<String, String> get _coaches => {for (final member in team) member.userId: '${member.displayName} · ${Fmt.label(member.role)}'};

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MembersCubit>();
    final pending = membership.status == 'pending';
    final live = membership.status == 'active' || membership.status == 'paused';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(child: Text(membership.memberName.characters.first.toUpperCase())),
                title: Text(membership.memberName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  [
                    membership.planName,
                    if (membership.coachName != null) 'Coach ${membership.coachName}',
                    if (membership.lastSessionOn != null) 'last session ${Fmt.day(membership.lastSessionOn)}',
                    if (membership.paymentStatus == 'pending') 'fee due',
                    if (pending && membership.note != null) '"${membership.note}"',
                  ].join(' · '),
                ),
                trailing: pending
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusChip(membership.status),
                          if (live)
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'coach') {
                                  final result = await showFormSheet(
                                    context,
                                    title: 'Coach for ${membership.memberName}',
                                    fields: [FieldSpec.choice('coach_id', 'Coach', _coaches, initial: membership.coachId, required: false)],
                                  );
                                  if (result != null) await cubit.update(membership, result);
                                } else {
                                  await cubit.update(membership, {'status': value});
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'coach', child: Text('Assign coach')),
                                if (membership.status == 'active') const PopupMenuItem(value: 'paused', child: Text('Pause')),
                                if (membership.status == 'paused') const PopupMenuItem(value: 'active', child: Text('Resume')),
                                const PopupMenuItem(value: 'cancelled', child: Text('End membership')),
                              ],
                            ),
                        ],
                      ),
                onTap: live && membership.tracksPerformance ? () => context.push('/manage/$orgId/members/${membership.id}') : null,
              ),
              if (pending)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => cubit.decide(membership, approve: false), child: const Text('Decline')),
                      Gap.sm,
                      FilledButton.tonal(
                        onPressed: () async {
                          if (!membership.tracksPerformance) {
                            await cubit.decide(membership, approve: true);
                            return;
                          }
                          final result = await showFormSheet(
                            context,
                            title: 'Accept ${membership.memberName}',
                            description: 'Pick the coach who will log sessions and write progress reports.',
                            submitLabel: 'Accept',
                            fields: [FieldSpec.choice('coach_id', 'Coach', _coaches, required: false)],
                          );
                          if (result != null) await cubit.decide(membership, approve: true, coachId: result['coach_id'] as String?);
                        },
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                ),
              if (live && membership.tracksPerformance)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => context.push('/manage/$orgId/members/${membership.id}'),
                      icon: const Icon(Icons.insights_rounded, size: 18),
                      label: const Text('Progress & reports'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
