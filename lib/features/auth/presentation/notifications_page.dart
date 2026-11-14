import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../core/widgets/async_view.dart';
import '../domain/session.dart';
import 'account_page.dart';
import 'notifications_cubit.dart';
import 'session_cubit.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => NotificationsCubit(sl())..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              TextButton(
                onPressed: () async {
                  final session = context.read<SessionCubit>();
                  await context.read<NotificationsCubit>().markAllRead();
                  await session.refresh();
                },
                child: const Text('Mark all read'),
              ),
            ],
          ),
          body: AsyncView<NotificationsCubit, List<AppNotification>>(builder: (context, items, _) => NotificationList(items)),
        ),
      ),
    );
  }
}
