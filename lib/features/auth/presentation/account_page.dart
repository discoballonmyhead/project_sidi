import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/bloc/submit_cubit.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../organization/presentation/org_forms.dart';
import '../../organization/presentation/organization_cubits.dart';
import '../domain/session.dart';
import 'session_cubit.dart';

/// "Account" tab: profile, the organisations the user runs, and the doors to
/// the manage section and the admin console.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrgCreateCubit(sl()),
      child: BlocListener<OrgCreateCubit, SubmitState<String>>(
        listener: (context, state) async {
          if (state.status == SubmitStatus.failed) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.failure!.message)));
          } else if (state.status == SubmitStatus.done) {
            final router = GoRouter.of(context);
            await context.read<SessionCubit>().refresh();
            router.push('/manage/${state.value}');
          }
        },
        child: const _AccountView(),
      ),
    );
  }
}

Future<void> _createOrg(BuildContext context) async {
  final cubit = context.read<OrgCreateCubit>();
  final catalog = context.read<CatalogCubit>().state.data;
  if (catalog == null) return;
  final org = await showOrgCreateForm(context, catalog);
  if (org != null) await cubit.create(org);
}

class _AccountView extends StatelessWidget {
  const _AccountView();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>();
    final me = session.state.me;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: (me?.unreadNotifications ?? 0) > 0,
              label: Text('${me?.unreadNotifications ?? 0}'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      body: me == null
          ? session.state.failure == null
                ? const Center(child: CircularProgressIndicator())
                : ErrorView(failure: session.state.failure!, onRetry: session.refresh)
          : RefreshIndicator(
              onRefresh: session.refresh,
              child: ContentWidth(
                child: ListView(
                  padding: pagePadding,
                  children: [
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          radius: 26,
                          child: Text(me.profile.displayName.characters.first.toUpperCase(), style: const TextStyle(fontSize: 22)),
                        ),
                        title: Text(me.profile.displayName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [if (me.profile.username != null) '@${me.profile.username}', me.email, me.profile.city].whereType<String>().join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Edit profile',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editProfile(context, me),
                        ),
                      ),
                    ),
                    if (me.isStaff) ...[
                      Gap.md,
                      Card(
                        color: theme.colorScheme.tertiaryContainer,
                        child: ListTile(
                          leading: Icon(Icons.admin_panel_settings_outlined, color: theme.colorScheme.onTertiaryContainer),
                          title: const Text('Admin console', style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('Approvals, verification, feature access and moderation'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => context.push('/admin'),
                        ),
                      ),
                    ],
                    SectionHeader(
                      'My organisations',
                      trailing: TextButton.icon(
                        onPressed: () => _createOrg(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Create'),
                      ),
                    ),
                    if (me.organizations.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Run a club, academy or sports centre?', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              const Text(
                                'Create an organisation to take bookings, coach members, run payroll and budgets, '
                                'and host tournaments. New organisations are reviewed before they go live.',
                              ),
                              Gap.md,
                              FilledButton.tonal(onPressed: () => _createOrg(context), child: const Text('Create an organisation')),
                            ],
                          ),
                        ),
                      )
                    else
                      for (final org in me.organizations)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Text(org.name.characters.first.toUpperCase())),
                              title: Row(
                                children: [
                                  Flexible(child: Text(org.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  if (org.isVerified) ...[Gap.xs, const VerifiedBadge()],
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  Text('${org.role[0].toUpperCase()}${org.role.substring(1)}'),
                                  if (org.status != 'approved') ...[Gap.sm, StatusChip(org.status)],
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => context.push('/manage/${org.id}'),
                            ),
                          ),
                        ),
                    const SectionHeader('Activity'),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.emoji_events_outlined),
                            title: const Text('My tournament entries'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => context.push('/entries'),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(Icons.logout_rounded),
                            title: const Text('Sign out'),
                            onTap: () async {
                              if (await confirm(context, title: 'Sign out?', confirmLabel: 'Sign out')) await session.signOut();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _editProfile(BuildContext context, Me me) async {
    final session = context.read<SessionCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showFormSheet(
      context,
      title: 'Edit profile',
      fields: [
        FieldSpec.text('display_name', 'Name', initial: me.profile.displayName, required: true),
        FieldSpec.text(
          'username',
          'Username',
          initial: me.profile.username,
          helper: '3-24 lowercase letters, digits or underscores. Organisations use it to add you to a team.',
        ),
        FieldSpec.text('phone', 'Phone', initial: me.profile.phone),
        FieldSpec.text('city', 'City', initial: me.profile.city),
        FieldSpec.multiline('bio', 'About you', initial: me.profile.bio),
      ],
    );
    if (result == null) return;
    final failure = await session.updateProfile(result);
    if (failure != null) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

/// Shared rendering of a notification list.
class NotificationList extends StatelessWidget {
  const NotificationList(this.items, {super.key});
  final List<AppNotification> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return const EmptyState(icon: Icons.notifications_none_rounded, title: 'You are all caught up');
    }
    return ContentWidth(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          final item = items[index];
          final unread = item.readAt == null;
          return ListTile(
            leading: Icon(Icons.circle, size: 10, color: unread ? theme.colorScheme.primary : Colors.transparent),
            title: Text(item.title, style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text([item.body, _ago(item.createdAt)].whereType<String>().join(' · ')),
          );
        },
      ),
    );
  }

  static String _ago(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}
