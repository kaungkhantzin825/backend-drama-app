import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'ad_test_screen.dart';
import 'feedback_screen.dart';
import 'library_screen.dart';
import 'wallet_screen.dart';

/// Account, payout history and app information.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final wallet = ref.watch(walletProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.accent.withValues(alpha: 0.16),
                  backgroundImage: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                      ? NetworkImage(user.avatarUrl!)
                      : null,
                  child: user?.avatarUrl == null || user!.avatarUrl!.isEmpty
                      ? Text(
                          user?.initials ?? '?',
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? 'Viewer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user?.email ?? (user?.isGuest ?? true ? 'Guest account' : 'Signed in'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                PointsPill(
                  points: wallet?.pointsBalance ?? user?.pointsBalance ?? 0,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WalletScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Withdrawals'),
          const _WithdrawalHistory(),
          const SizedBox(height: 24),
          _SettingsCard(
            children: [
              _SettingRow(
                icon: Icons.bookmark_border_rounded,
                label: 'My list',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LibraryScreen()),
                ),
              ),
              const Divider(),
              _SettingRow(
                icon: Icons.history_rounded,
                label: 'Watch history',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LibraryScreen(initialTab: 1),
                  ),
                ),
              ),
              const Divider(),
              _SettingRow(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Rewards & cash out',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WalletScreen()),
                ),
              ),
              const Divider(),
              _SettingRow(
                icon: Icons.feedback_outlined,
                label: 'Send feedback',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FeedbackScreen()),
                ),
              ),
              const Divider(),
              _SettingRow(
                icon: Icons.info_outline_rounded,
                label: 'About MyanCash',
                trailing: const Text(
                  'v1.0.0',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'MyanCash',
                  applicationVersion: '1.0.0',
                  applicationLegalese: 'Short dramas, one minute at a time.',
                ),
              ),
              // Staff tapping live ads is invalid traffic, so release builds
              // (what users install) never show the bench.
              if (!kReleaseMode) ...[
                const Divider(),
                _SettingRow(
                  icon: Icons.bug_report_outlined,
                  label: 'Ad test bench',
                  trailing: const Text(
                    'TEST',
                    style: TextStyle(
                      color: AppTheme.gold,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdTestScreen()),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: AppTheme.surfaceHigh,
                  title: const Text('Sign out?', style: TextStyle(color: AppTheme.textPrimary)),
                  content: const Text(
                    'You will be signed in again as a guest on this device. Your points stay with the account.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Sign out', style: TextStyle(color: AppTheme.accent)),
                    ),
                  ],
                ),
              );

              if (confirmed != true) return;
              await ref.read(sessionProvider.notifier).signOutAndRestart();
              ref.invalidate(walletProvider);
              ref.invalidate(ledgerProvider);
              ref.invalidate(withdrawalsProvider);
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _WithdrawalHistory extends ConsumerWidget {
  const _WithdrawalHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final withdrawals = ref.watch(withdrawalsProvider);

    return withdrawals.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: LoadingView(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ErrorView(
          message: '$error',
          onRetry: () => ref.invalidate(withdrawalsProvider),
        ),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: const Text(
              'No withdrawals yet. Reach 5,000 points to cash out.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4),
            ),
          );
        }

        return Column(
          children: page.items.map((item) => _WithdrawalRow(item: item)).toList(),
        );
      },
    );
  }
}

class _WithdrawalRow extends StatelessWidget {
  const _WithdrawalRow({required this.item});

  final Withdrawal item;

  Color get _statusColor => switch (item.status) {
        'paid' => AppTheme.success,
        'rejected' => AppTheme.accent,
        'approved' => AppTheme.gold,
        _ => AppTheme.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${Fmt.cash(double.tryParse(item.amount) ?? 0, currency: item.currency)} · ${item.methodName ?? _methodLabel(item.method)}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${Fmt.points(item.pointsAmount)} pts · ${Fmt.relative(item.createdAt)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                ),
                if (item.adminNote != null && item.adminNote!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.adminNote!,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              item.statusLabel,
              style: TextStyle(color: _statusColor, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _methodLabel(String method) => switch (method) {
        'paypal' => 'PayPal',
        'bank' => 'Bank transfer',
        'giftcard' => 'Gift card',
        _ => method,
      };
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
              ),
            ),
            if (trailing != null) trailing!,
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
