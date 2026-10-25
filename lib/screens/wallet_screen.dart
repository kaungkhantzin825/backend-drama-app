import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/ad_service.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'withdraw_sheet.dart';

/// The rewards hub: balance, cash value, daily check-in, ad bonus and history.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Rewards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: AppTheme.textSecondary,
            onPressed: () {
              ref.invalidate(walletProvider);
              ref.invalidate(ledgerProvider);
            },
          ),
        ],
      ),
      body: wallet.when(
        loading: () => const LoadingView(message: 'Loading your wallet…'),
        error: (error, _) => ErrorView(
          message: '$error',
          onRetry: () => ref.invalidate(walletProvider),
        ),
        data: (value) => RefreshIndicator(
          color: AppTheme.accent,
          backgroundColor: AppTheme.surface,
          onRefresh: () async {
            ref.invalidate(walletProvider);
            ref.invalidate(ledgerProvider);
            await ref.read(walletProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              _BalanceCard(wallet: value),
              const SizedBox(height: 16),
              _EarnCard(wallet: value),
              const SizedBox(height: 12),
              _WithdrawCard(wallet: value),
              const SizedBox(height: 24),
              const SectionHeader(title: 'Recent activity'),
              const _LedgerList(),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1216), Color(0xFF15151C)],
        ),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'POINTS BALANCE',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Fmt.points(wallet.pointsBalance),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.bolt_rounded, size: 22, color: AppTheme.gold),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '≈ ${Fmt.cash(wallet.cashValue, currency: wallet.currency)} cash value',
            style: const TextStyle(color: AppTheme.gold, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Earned',
                  value: Fmt.points(wallet.totalEarned),
                  color: AppTheme.success,
                ),
              ),
              Container(width: 1, height: 32, color: AppTheme.divider),
              Expanded(
                child: _Stat(
                  label: 'Spent',
                  value: Fmt.points(wallet.totalSpent),
                  color: AppTheme.textPrimary,
                ),
              ),
              Container(width: 1, height: 32, color: AppTheme.divider),
              Expanded(
                child: _Stat(
                  label: 'Per \$1',
                  value: '${Fmt.points(wallet.pointsPerUnit)}p',
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5)),
      ],
    );
  }
}

/// Daily check-in plus the rewarded-ad slot.
class _EarnCard extends ConsumerStatefulWidget {
  const _EarnCard({required this.wallet});

  final Wallet wallet;

  @override
  ConsumerState<_EarnCard> createState() => _EarnCardState();
}

class _EarnCardState extends ConsumerState<_EarnCard> {
  bool _checkingIn = false;
  bool _watchingAd = false;

  Future<void> _checkIn() async {
    setState(() => _checkingIn = true);

    try {
      final points = await ref.read(walletProvider.notifier).checkIn();
      if (!mounted) return;
      showSnack(context, 'Checked in — +$points points.');
      ref.invalidate(ledgerProvider);
    } on ApiException catch (error) {
      if (!mounted) return;
      showSnack(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  Future<void> _watchAd() async {
    setState(() => _watchingAd = true);

    try {
      // Play the ad first; the reward is claimed only once the SDK reports a
      // completed view.
      final outcome = await AdService.instance.showRewarded(placement: 'wallet');

      if (!mounted) return;

      switch (outcome) {
        case RewardedOutcome.unavailable:
          showSnack(
            context,
            'No ad available right now. Try again in a moment.',
            error: true,
          );
          return;
        case RewardedOutcome.dismissed:
          showSnack(context, 'Watch the whole ad to earn points.');
          return;
        case RewardedOutcome.earned:
          break;
      }

      final points = await ref
          .read(walletProvider.notifier)
          .claimAdReward(placement: 'rewarded_video');

      if (!mounted) return;
      showSnack(context, 'Ad reward — +$points points.');
      ref.invalidate(ledgerProvider);
    } on ApiException catch (error) {
      if (!mounted) return;
      showSnack(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _watchingAd = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = widget.wallet;
    final adAvailable = wallet.adsRemainingToday > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          _EarnRow(
            icon: Icons.calendar_month_rounded,
            title: 'Daily check-in',
            subtitle: wallet.checkInAvailable
                ? 'Claim ${wallet.checkInPoints} points today'
                : 'Already claimed — come back tomorrow',
            action: wallet.checkInAvailable ? 'Claim' : 'Done',
            busy: _checkingIn,
            enabled: wallet.checkInAvailable,
            onTap: _checkIn,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(),
          ),
          _EarnRow(
            icon: Icons.smart_display_rounded,
            title: 'Watch an ad',
            subtitle: adAvailable
                ? '+${wallet.adRewardPoints} points · ${wallet.adsRemainingToday} left today'
                : 'Daily ad limit reached',
            action: 'Watch',
            busy: _watchingAd,
            enabled: adAvailable,
            onTap: _watchAd,
          ),
        ],
      ),
    );
  }
}

class _EarnRow extends StatelessWidget {
  const _EarnRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 20, color: AppTheme.gold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 34,
          child: FilledButton(
            onPressed: enabled && !busy ? onTap : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(74, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              backgroundColor: enabled ? AppTheme.accent : AppTheme.surfaceHigh,
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(action),
          ),
        ),
      ],
    );
  }
}

class _WithdrawCard extends StatelessWidget {
  const _WithdrawCard({required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: 8),
              const Text(
                'Cash out',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Min ${Fmt.points(wallet.minWithdrawalPoints)}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: wallet.withdrawalProgress,
              minHeight: 6,
              backgroundColor: AppTheme.surfaceHigh,
              valueColor: AlwaysStoppedAnimation(
                wallet.canWithdraw ? AppTheme.success : AppTheme.gold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            wallet.canWithdraw
                ? 'You can withdraw ${Fmt.cash(wallet.cashValue, currency: wallet.currency)} now.'
                : '${Fmt.points(wallet.pointsToWithdrawal)} points to go before you can cash out.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: wallet.canWithdraw
                  ? () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: AppTheme.surface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (_) => WithdrawSheet(wallet: wallet),
                      )
                  : null,
              child: const Text('Request withdrawal'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerList extends ConsumerWidget {
  const _LedgerList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);

    return ledger.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: LoadingView(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ErrorView(
          message: '$error',
          onRetry: () => ref.invalidate(ledgerProvider),
        ),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: EmptyView(
              message: 'No activity yet. Claim your daily check-in to start earning.',
              icon: Icons.receipt_long_outlined,
            ),
          );
        }

        return Column(
          children: page.items.map((entry) => _LedgerRow(entry: entry)).toList(),
        );
      },
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final credit = entry.isCredit;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: (credit ? AppTheme.success : AppTheme.accent).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              credit ? Icons.add_rounded : Icons.remove_rounded,
              size: 17,
              color: credit ? AppTheme.success : AppTheme.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.typeLabel} · ${Fmt.relative(entry.createdAt)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${credit ? '+' : ''}${Fmt.points(entry.delta)}',
                style: TextStyle(
                  color: credit ? AppTheme.success : AppTheme.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                Fmt.points(entry.balanceAfter),
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
