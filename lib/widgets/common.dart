import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// A poster image that degrades gracefully.
///
/// Catalogue images are served from a CDN that may be slow, blocked or (in
/// development) simply absent. A card must still read as a title, so a failed
/// load falls back to a tinted gradient with the drama's initials rather than
/// a broken-image icon.
class Poster extends StatelessWidget {
  const Poster({
    super.key,
    this.url,
    required this.title,
    this.width,
    this.height,
    this.radius = 14,
  });

  final String? url;
  final String title;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url == null || url!.isEmpty
            ? _Fallback(title: title)
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _Fallback(title: title),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const ColoredBox(
                    color: AppTheme.surfaceHigh,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final hue = (title.hashCode % 360).abs().toDouble();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.35, 0.28).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.30, 0.12).toColor(),
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            _initials(title),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String value) {
    final words = value.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }
}

/// The gold points counter shown in headers.
class PointsPill extends StatelessWidget {
  const PointsPill({
    super.key,
    required this.points,
    this.onTap,
    this.compact = false,
  });

  final int points;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 6 : 8),
          decoration: BoxDecoration(
            color: AppTheme.gold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt_rounded, size: 16, color: AppTheme.gold),
              const SizedBox(width: 4),
              Text(
                Fmt.points(points),
                style: TextStyle(
                  color: AppTheme.gold,
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rail heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action!, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(message!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// A failure state with a retry affordance.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppTheme.textSecondary),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 160,
                child: FilledButton(onPressed: onRetry, child: const Text('Try again')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.icon = Icons.movie_filter_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// A portrait drama card for rails and grids.
class DramaCard extends StatelessWidget {
  const DramaCard({
    super.key,
    required this.drama,
    required this.onTap,
    this.width = 124,
  });

  final Drama drama;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Poster(
                  url: drama.coverImage,
                  title: drama.title,
                  width: width,
                  height: width * 1.45,
                ),
                if (drama.rating != null)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _Badge(
                      icon: Icons.star_rounded,
                      label: drama.rating!.toStringAsFixed(1),
                      color: AppTheme.gold,
                    ),
                  ),
                if (drama.durationLabel.isNotEmpty)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _Badge(
                      icon: Icons.play_arrow_rounded,
                      label: drama.durationLabel,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              drama.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${Fmt.compact(drama.viewCount)} views',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a transient message above the current screen.
void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.accentDark : AppTheme.surfaceHigh,
        duration: const Duration(seconds: 3),
      ),
    );
}
