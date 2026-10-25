import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/common.dart';
import 'lucky_wheel_screen.dart';
import 'notifications_screen.dart';
import 'player_screen.dart';
import 'wallet_screen.dart';

/// The home feed: one hero, then the featured / trending / latest rails.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider);
    final balance = ref.watch(sessionProvider).user?.pointsBalance ?? 0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: AppTheme.accent,
        backgroundColor: AppTheme.surface,
        onRefresh: () async {
          ref.invalidate(homeFeedProvider);
          ref.invalidate(walletProvider);
          await ref.read(homeFeedProvider.future);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppTheme.background.withValues(alpha: 0.92),
              title: const _Brand(),
              actions: [
                IconButton(
                  tooltip: 'Lucky wheel',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LuckyWheelScreen()),
                  ),
                  icon: const Icon(
                    Icons.casino_rounded,
                    color: AppTheme.gold,
                    size: 22,
                  ),
                ),
                const _NotificationBell(),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: PointsPill(
                    points: balance,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WalletScreen()),
                    ),
                  ),
                ),
              ],
            ),
            ...switch (feed) {
              AsyncData(:final value) => _rails(context, ref, value),
              AsyncError(:final error) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorView(
                      message: '$error',
                      onRetry: () => ref.invalidate(homeFeedProvider),
                    ),
                  ),
                ],
              _ => [
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: LoadingView(message: 'Loading your feed…'),
                  ),
                ],
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _rails(BuildContext context, WidgetRef ref, HomeFeed feed) {
    final hero = feed.featured.isNotEmpty
        ? feed.featured.first
        : (feed.latest.isNotEmpty ? feed.latest.first : null);

    return [
      if (hero != null) SliverToBoxAdapter(child: _Hero(drama: hero)),

      if (feed.categories.isNotEmpty)
        SliverToBoxAdapter(child: _CategoryStrip(categories: feed.categories)),

      const SliverToBoxAdapter(child: _ContinueRail()),

      if (feed.featured.length > 1)
        SliverToBoxAdapter(
          child: _Rail(
            title: 'Featured',
            dramas: feed.featured.skip(1).toList(),
          ),
        ),

      if (feed.trending.isNotEmpty)
        SliverToBoxAdapter(
          child: _Rail(title: 'Trending now', dramas: feed.trending),
        ),

      // One native ad in the feed. It collapses to zero height while loading
      // and when no fill arrives, so the rails below never jump.
      const SliverToBoxAdapter(child: NativeAdCard()),

      if (feed.latest.isNotEmpty)
        SliverToBoxAdapter(
          child: _Rail(title: 'Just added', dramas: feed.latest),
        ),

      if (feed.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(message: 'No dramas are published yet. Check back soon.'),
        ),

      const SliverToBoxAdapter(child: SizedBox(height: 28)),
    ];
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
        ),
        const SizedBox(width: 9),
        const Text(
          'DramaLoop',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

/// A tall, full-bleed hero for the top title.
class _Hero extends StatelessWidget {
  const _Hero({required this.drama});

  final Drama drama;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openPlayer(context, drama),
        child: SizedBox(
          height: 400,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Poster(url: drama.bannerImage ?? drama.coverImage, title: drama.title, radius: 18),
              // Bottom scrim so the copy stays legible over any artwork.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.35, 1.0],
                    colors: [
                      Colors.transparent,
                      AppTheme.background.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'FEATURED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      drama.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (drama.tagline != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        drama.tagline!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => openPlayer(context, drama),
                            icon: const Icon(Icons.play_arrow_rounded, size: 22),
                            label: const Text('Watch now'),
                          ),
                        ),
                        if (drama.durationLabel.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          _Meta(
                            icon: Icons.schedule_rounded,
                            label: drama.durationLabel,
                          ),
                        ],
                      ],
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
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.textPrimary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Text(
              category.name,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.title, required this.dramas});

  final String title;
  final List<Drama> dramas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        SizedBox(
          height: 246,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: dramas.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final drama = dramas[index];
              return DramaCard(
                drama: drama,
                onTap: () => openPlayer(context, drama),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Bell with an unread badge. The count is fetched separately from the inbox so
/// the header never waits on a full page of notifications.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return IconButton(
      tooltip: 'Notifications',
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
        // Coming back from the inbox, the badge may have been cleared.
        ref.invalidate(unreadNotificationCountProvider);
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.notifications_none_rounded,
            color: AppTheme.textPrimary,
            size: 23,
          ),
          if (unread > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Continue watching" — one card per drama the viewer has started.
///
/// Hidden entirely when there is nothing in progress, so a new account sees a
/// clean feed rather than an empty heading.
class _ContinueRail extends ConsumerWidget {
  const _ContinueRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watching = ref.watch(continueWatchingProvider);
    final items = watching.valueOrNull ?? const <WatchProgressItem>[];

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 22, 16, 10),
          child: Text(
            'Continue watching',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final drama = item.drama;

              if (drama == null) return const SizedBox.shrink();

              return GestureDetector(
                onTap: () => openPlayer(context, drama),
                child: SizedBox(
                  width: 118,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          SizedBox(
                            height: 132,
                            child: Poster(
                              url: drama.coverImage,
                              title: drama.title,
                              radius: 10,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(10),
                              ),
                              child: LinearProgressIndicator(
                                value: (item.percent / 100).clamp(0.0, 1.0),
                                minHeight: 3.5,
                                backgroundColor: Colors.black45,
                                valueColor:
                                    const AlwaysStoppedAnimation(AppTheme.accent),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        drama.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
