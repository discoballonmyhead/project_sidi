import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/async_cubit.dart';
import '../error/failure.dart';

/// Renders an [AsyncCubit]: spinner while loading, an error with retry when
/// loading failed, [builder] once there is data. Notices become snack bars.
class AsyncView<C extends AsyncCubit<T>, T> extends StatelessWidget {
  const AsyncView({super.key, required this.builder, this.refreshable = true});

  final Widget Function(BuildContext context, T data, AsyncState<T> state) builder;

  /// Wraps the content in pull-to-refresh. The content must be scrollable.
  final bool refreshable;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<C, AsyncState<T>>(
      listenWhen: (previous, current) => previous.notice != current.notice && current.notice != null,
      listener: (context, state) => showNotice(context, state.notice!),
      builder: (context, state) {
        final data = state.data;
        if (data != null) {
          final content = builder(context, data, state);
          final body = refreshable
              ? RefreshIndicator(onRefresh: context.read<C>().load, child: content)
              : content;
          return Stack(
            children: [
              body,
              if (state.busy) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
            ],
          );
        }
        if (state.status == AsyncStatus.failure) {
          return ErrorView(failure: state.failure ?? const Failure.unexpected(), onRetry: context.read<C>().load);
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

void showNotice(BuildContext context, Notice notice) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(notice.text, style: TextStyle(color: notice.isError ? scheme.onErrorContainer : null)),
        backgroundColor: notice.isError ? scheme.errorContainer : null,
      ),
    );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: failure.code == 'network' ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: failure.code == 'network' ? 'You are offline' : 'Could not load this',
      message: failure.message,
      action: onRetry == null ? null : FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
