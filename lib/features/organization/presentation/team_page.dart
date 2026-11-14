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

const teamRoles = {
  'manager': 'Manager · everything except ownership',
  'coach': 'Coach · members, sessions and reports',
  'staff': 'Staff · front desk and payments',
};

class TeamPage extends StatelessWidget {
  const TeamPage({super.key, required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TeamCubit(sl(), orgId)..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Team access')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _add(context),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Add person'),
          ),
          body: AsyncView<TeamCubit, List<TeamMember>>(
            builder: (context, team, _) => ContentWidth(
              child: ListView(
                padding: pagePadding.copyWith(bottom: 96),
                children: [
                  Text(
                    'People listed here can operate this organisation in the app. Payroll staff who do not use the app are kept under Staff.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  Gap.md,
                  Card(
                    child: Column(
                      children: [
                        for (final (index, member) in team.indexed) ...[
                          if (index > 0) const Divider(indent: 72),
                          ListTile(
                            leading: CircleAvatar(child: Text(member.displayName.characters.first.toUpperCase())),
                            title: Text(member.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([Fmt.label(member.role), if (member.username != null) '@${member.username}'].join(' · ')),
                            trailing: member.role == 'owner'
                                ? null
                                : PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      final cubit = context.read<TeamCubit>();
                                      if (value == 'remove') {
                                        if (await confirm(context, title: 'Remove ${member.displayName}?', confirmLabel: 'Remove', destructive: true)) {
                                          await cubit.remove(member);
                                        }
                                      } else if (member.username != null) {
                                        await cubit.setMember('@${member.username}', value);
                                      } else {
                                        cubit.say('This person needs a username before their role can be changed.', isError: true);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      for (final role in teamRoles.keys)
                                        if (role != member.role) PopupMenuItem(value: role, child: Text('Make ${Fmt.label(role).toLowerCase()}')),
                                      const PopupMenuItem(value: 'remove', child: Text('Remove from team')),
                                    ],
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final cubit = context.read<TeamCubit>();
    final result = await showFormSheet(
      context,
      title: 'Add a person',
      description: 'They need a Sidi account first.',
      submitLabel: 'Add',
      fields: const [
        FieldSpec.text('handle', 'Username or e-mail', required: true, hint: '@asha or asha@example.com'),
        FieldSpec.choice('role', 'Role', teamRoles, initial: 'coach'),
      ],
    );
    if (result != null) await cubit.setMember(result['handle'] as String, result['role'] as String);
  }
}
