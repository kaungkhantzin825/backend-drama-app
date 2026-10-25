import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'player_screen.dart';

/// Everything the viewer has saved or started watching.
///
/// Two tabs over one screen: "My list" is the favourites grid, "History" is a
/// reverse-chronological run of videos. Both read from the same library API
/// that the player writes to, so a title appears here the moment it is saved.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('My library'),
          bottom: const TabBar(
            labelColor: AppTheme.textPrimary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.accent,
            tabs: [
              Tab(text: 'My list'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _FavoritesTab(),
            _HistoryTab(),
          ],
        ),
      ),
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);

    return favorites.when(
      loading: () => const LoadingView(message: 'Loading your list…'),
      error: (error, _) => ErrorView(
        message: '$error',
        onRetry: () => ref.invalidate(favoritesProvider),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const EmptyView(
            message: 'Nothing saved yet. Tap Save on a drama to keep it here.',
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 132,
            mainAxisSpacing: 18,
            crossAxisSpacing: 12,
            childAspectRatio: 0.52,
          ),
          itemCount: page.items.length,
          itemBuilder: (context, index) {
            final drama = page.items[index];

            return GestureDetector(
              onLongPress: () => _remove(context, ref, drama),
              child: DramaCard(
                drama: drama,
                width: 132,
                onTap: () => openPlayer(context, drama),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, Drama drama) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        title: const Text(
          'Remove from your list?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          drama.title,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(libraryApiProvider).toggleFavorite(drama.id);
      ref.invalidate(favoritesProvider);
      if (context.mounted) showSnack(context, 'Removed from your list.');
    } on ApiException catch (error) {
      if (context.mounted) showSnack(context, error.message, error: true);
    }
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    return history.when(
      loading: () => const LoadingView(message: 'Loading your history…'),
      error: (error, _) => ErrorView(
        message: '$error',
        onRetry: () => ref.invalidate(historyProvider),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const EmptyView(
            message: 'You have not watched anything yet.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          itemCount: page.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _HistoryRow(item: page.items[index]),
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final WatchProgressItem item;

  @override
  Widget build(BuildContext context) {
    final drama = item.drama;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        if (drama == null || drama.slug.isEmpty) return;

        openPlayer(context, drama);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              height: 84,
              child: Poster(
                url: drama?.coverImage,
                title: drama?.title ?? 'Video',
                radius: 9,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drama?.title ?? 'Drama',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    drama?.tagline ?? drama?.category?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (item.percent / 100).clamp(0.0, 1.0),
                      minHeight: 3.5,
                      backgroundColor: AppTheme.divider,
                      valueColor: AlwaysStoppedAnimation(
                        item.isCompleted ? AppTheme.success : AppTheme.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.isCompleted
                        ? 'Finished'
                        : '${Fmt.duration(item.positionSeconds)} · ${item.percent}%',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              item.isCompleted
                  ? Icons.check_circle_rounded
                  : Icons.play_circle_fill_rounded,
              color: item.isCompleted ? AppTheme.success : AppTheme.accent,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}
