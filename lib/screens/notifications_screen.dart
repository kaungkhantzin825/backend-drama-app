import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'player_screen.dart';
import 'wallet_screen.dart';

/// The in-app inbox.
///
/// Notifications are produced by the server when something happens to the
/// account — a payout moves through review, a reward lands. The client only
/// reads them and clears the unread markers.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => _markAllRead(context, ref),
            child: const Text(
              'Mark all read',
              style: TextStyle(color: AppTheme.gold, fontSize: 13),
            ),
          ),
        ],
      ),
      body: inbox.when(
        loading: () => const LoadingView(message: 'Loading your inbox…'),
        error: (error, _) => ErrorView(
          message: '$error',
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return const EmptyView(
              icon: Icons.notifications_none_rounded,
              message: 'Nothing here yet. Rewards and payout updates land here.',
            );
          }

          return RefreshIndicator(
            color: AppTheme.accent,
            backgroundColor: AppTheme.surfaceHigh,
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: page.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = page.items[index];

                return _NotificationTile(
                  notification: item,
                  onTap: () => _open(context, ref, item),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Mark read, then send the viewer where the notification points.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) async {
    if (!notification.isRead) {
      try {
        await ref.read(notificationApiProvider).markRead(notification.id);
        ref.invalidate(notificationsProvider);
        ref.invalidate(unreadNotificationCountProvider);
      } on ApiException catch (error) {
        if (context.mounted) showSnack(context, error.message, error: true);
        return;
      }
    }

    if (!context.mounted) return;

    final data = notification.data ?? const <String, dynamic>{};
    final slug = data['drama_slug'] as String?;

    switch (notification.route) {
      case 'wallet':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WalletScreen()),
        );
      case 'drama' || 'player' when slug != null:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlayerScreen(slug: slug)),
        );
      default:
        // Nothing to open — the body already said everything.
        break;
    }
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    try {
      final updated = await ref.read(notificationApiProvider).markAllRead();
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadNotificationCountProvider);

      if (context.mounted) {
        showSnack(
          context,
          updated == 0 ? 'You are already caught up.' : '$updated marked as read.',
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) showSnack(context, error.message, error: true);
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;

    return Material(
      color: unread ? AppTheme.surfaceHigh : AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _tint(notification.type).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  _icon(notification.type),
                  size: 19,
                  color: _tint(notification.type),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14.5,
                              fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(left: 8, top: 2),
                            decoration: const BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (notification.body != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        notification.body!,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      Fmt.relative(notification.createdAt),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
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

  static IconData _icon(String type) {
    return switch (type) {
      'withdrawal_paid' => Icons.payments_rounded,
      'withdrawal_approved' => Icons.verified_rounded,
      'withdrawal_rejected' => Icons.undo_rounded,
      'reward_granted' => Icons.bolt_rounded,
      'episode_unlocked' => Icons.lock_open_rounded,
      'new_episode' => Icons.play_circle_outline_rounded,
      _ => Icons.info_outline_rounded,
    };
  }

  static Color _tint(String type) {
    return switch (type) {
      'withdrawal_paid' || 'withdrawal_approved' => AppTheme.success,
      'withdrawal_rejected' => AppTheme.accent,
      'reward_granted' => AppTheme.gold,
      _ => AppTheme.textSecondary,
    };
  }
}
