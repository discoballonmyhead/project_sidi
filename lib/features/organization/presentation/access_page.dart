import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../domain/organization.dart';
import 'organization_cubits.dart';

/// Verification and feature access: what the organisation holds, what it can
/// ask the platform for, and the state of every request it has filed.
class AccessPage extends StatelessWidget {
  const AccessPage({super.key, required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrgAccessCubit(sl(), orgId)..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Access & verification')),
        body: AsyncView<OrgAccessCubit, OrgAccess>(builder: (context, access, _) => _AccessView(access)),
      ),
    );
  }
}

class _AccessView extends StatelessWidget {
  const _AccessView(this.access);
  final OrgAccess access;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<OrgAccessCubit>();
    return ContentWidth(
      child: ListView(
        padding: pagePadding,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        access.isVerified ? Icons.verified_rounded : Icons.verified_outlined,
                        color: access.isVerified ? const Color(0xFF1976D2) : theme.colorScheme.outline,
                        size: 28,
                      ),
                      Gap.md,
                      Expanded(
                        child: Text(
                          access.isVerified ? 'Verified organisation' : 'Not verified yet',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (access.verificationPending) const StatusChip('pending', label: 'In review'),
                    ],
                  ),
                  Gap.sm,
                  Text(
                    access.isVerified
                        ? 'Customers see the verified badge on your page and tournaments.'
                        : 'Verification confirms who runs this organisation. It shows a badge to customers and is '
                              'required before you can charge tournament entry fees.',
                  ),
                  if (!access.isVerified && !access.verificationPending && access.status == 'approved') ...[
                    Gap.md,
                    FilledButton.tonal(onPressed: () => _verify(context, cubit), child: const Text('Apply for verification')),
                  ],
                ],
              ),
            ),
          ),
          const SectionHeader('Features'),
          Card(
            child: Column(
              children: [
                for (final (index, feature) in access.features.indexed) ...[
                  if (index > 0) const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(feature.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${feature.description}'
                      '${feature.requiresVerified && !feature.enabled ? '\nRequires a verified organisation.' : ''}',
                    ),
                    isThreeLine: feature.requiresVerified && !feature.enabled,
                    trailing: feature.enabled
                        ? const StatusChip('enabled', label: 'On')
                        : feature.pending
                        ? const StatusChip('pending', label: 'Requested')
                        : access.status != 'approved'
                        ? const StatusChip('info', label: 'After approval')
                        : FilledButton.tonal(
                            onPressed: feature.requiresVerified && !access.isVerified ? null : () => _request(context, cubit, feature),
                            child: const Text('Request'),
                          ),
                  ),
                ],
              ],
            ),
          ),
          if (access.requests.isNotEmpty) ...[
            const SectionHeader('Requests'),
            for (final request in access.requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    title: Text(request.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [
                        'Sent ${Fmt.dayYear(request.createdAt)}',
                        if (request.decisionNote != null) '"${request.decisionNote}"',
                      ].join('\n'),
                    ),
                    isThreeLine: request.decisionNote != null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusChip(request.status),
                        if (request.status == 'pending' && request.kind != 'org_approval')
                          IconButton(tooltip: 'Withdraw', icon: const Icon(Icons.close), onPressed: () => cubit.withdraw(request)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _verify(BuildContext context, OrgAccessCubit cubit) async {
    final result = await showFormSheet(
      context,
      title: 'Apply for verification',
      description: 'Tell us how we can confirm this organisation is real and that you run it.',
      submitLabel: 'Send request',
      fields: const [
        FieldSpec.multiline(
          'message',
          'Details',
          required: true,
          hint: 'Registration number, registered address, website, federation affiliation',
        ),
        FieldSpec.multiline('documents', 'Links to documents', helper: 'One link per line: registration certificate, licence, website.'),
      ],
    );
    if (result == null) return;
    final documents = (result['documents'] as String? ?? '').split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    await cubit.requestVerification(result['message'] as String, documents);
  }

  Future<void> _request(BuildContext context, OrgAccessCubit cubit, FeatureState feature) async {
    final result = await showFormSheet(
      context,
      title: 'Request ${feature.name}',
      description: feature.description,
      submitLabel: 'Send request',
      fields: const [FieldSpec.multiline('message', 'Why do you need it?', hint: 'What you plan to run, roughly how often and how big')],
    );
    if (result != null) await cubit.requestFeature(feature, result['message'] as String?);
  }
}
