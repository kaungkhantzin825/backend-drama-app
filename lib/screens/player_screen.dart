import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../core/api_config.dart';
import '../core/api_exception.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/ad_service.dart';
import '../services/library_api.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Opens the swipe feed on [drama].
Future<void> openPlayer(BuildContext context, Drama drama) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PlayerScreen(start: drama)),
  );
}

/// The vertical, TikTok-style feed.
///
/// One page per video: it opens on the video that was tapped, and swiping
/// carries on through every other video in the catalogue. The feed pages
/// through `GET /dramas`, whose items already carry their stream URL.
///
/// Playback reports a heartbeat every ten seconds, which is how watch-time
/// points are earned — the server decides what a heartbeat is worth. Watch
/// time adds up across videos, so the reward ring keeps its progress when the
/// viewer swipes on instead of starting again from zero.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, this.start, this.slug})
      : assert(start != null || slug != null);

  /// The video to open on, when the caller already has it.
  final Drama? start;

  /// Otherwise its slug (e.g. from a notification); it is fetched first.
  final String? slug;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _heartbeatSeconds = 10;

  final _pages = PageController();
  final List<Drama> _videos = [];
  int _index = 0;

  int _nextPage = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  String? _error;

  Timer? _ticker;

  /// Playback on the current video; drives auto-advance and the reported
  /// position.
  int _pageSeconds = 0;

  /// Seconds watched (on any video) that the server has not acknowledged yet.
  int _unreported = 0;
  int _sinceAttempt = 0;
  bool _reporting = false;

  int _earnedThisSession = 0;
  bool _advancing = false;

  /// Set when the viewer taps to pause. A paused video must not earn
  /// watch-time points or auto-advance.
  bool _paused = false;

  /// True while an interstitial covers the player. The active video is marked
  /// inactive meanwhile, so its playback (and audio) stop behind the ad.
  bool _adBreak = false;

  /// Captured up front so the last heartbeat can still be sent from dispose().
  late final LibraryApi _library;

  Drama? get _current =>
      _index >= 0 && _index < _videos.length ? _videos[_index] : null;

  @override
  void initState() {
    super.initState();
    _library = ref.read(libraryApiProvider);

    // First player of the session: start the ring from the server's meter.
    // After the first frame — providers must not change mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final meter = ref.read(watchMeterProvider.notifier);
      final wallet = ref.read(walletProvider).valueOrNull;
      if (!meter.isSynced && wallet != null) meter.sync(wallet.watchReward);
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _boot();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _flush();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() => _error = null);

    if (_videos.isEmpty) {
      final start = widget.start;

      if (start != null) {
        setState(() => _videos.add(start));
      } else {
        try {
          final detail = await ref.read(contentServiceProvider).drama(widget.slug!);
          if (!mounted) return;
          setState(() => _videos.add(detail.drama));
        } on ApiException catch (error) {
          if (mounted) setState(() => _error = error.message);
          return;
        }
      }
    }

    await _loadMore();
  }

  /// The next page of the catalogue, minus anything already in the feed.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;

    try {
      final page = await ref.read(contentServiceProvider).browse(page: _nextPage);
      if (!mounted) return;

      final known = _videos.map((v) => v.id).toSet();

      setState(() {
        _videos.addAll(page.items.where(
          (v) => !known.contains(v.id) && (v.videoUrl?.isNotEmpty ?? false),
        ));
        _nextPage = page.currentPage + 1;
        _hasMore = page.hasMore;
      });
    } on ApiException catch (error) {
      // The feed still works with what it has; only an empty one needs a retry.
      if (mounted && _videos.isEmpty) setState(() => _error = error.message);
    } finally {
      _loadingMore = false;
    }
  }

  void _tick() {
    if (!mounted || _paused || _adBreak) return;

    final video = _current;
    if (video == null || (video.videoUrl?.isEmpty ?? true)) return;

    setState(() => _pageSeconds++);
    _unreported++;
    _sinceAttempt++;
    ref.read(watchMeterProvider.notifier).tick();

    if (_sinceAttempt >= _heartbeatSeconds) {
      _sinceAttempt = 0;
      _reportProgress();
    }

    if (_pageSeconds >= _durationOf(video)) _advance();
  }

  static int _durationOf(Drama video) =>
      video.durationSeconds > 0 ? video.durationSeconds : 180;

  /// Post a heartbeat. The response says what the watch was worth and where
  /// the server's meter stands.
  Future<void> _reportProgress() async {
    final video = _current;
    if (video == null || _unreported <= 0 || _reporting) return;

    final sent = _unreported;
    _reporting = true;

    try {
      final result = await _library.recordProgress(
        dramaId: video.id,
        positionSeconds: _pageSeconds,
        durationSeconds: _durationOf(video),
        watchedSeconds: sent,
      );

      _unreported = _unreported > sent ? _unreported - sent : 0;
      if (!mounted) return;

      await ref.read(walletProvider.notifier).applyLocalWallet(result.wallet);
      ref
          .read(watchMeterProvider.notifier)
          .sync(result.wallet.watchReward, unreportedSeconds: _unreported);

      if (result.pointsAwarded > 0 && mounted) {
        setState(() => _earnedThisSession += result.pointsAwarded);
        showSnack(
          context,
          '+${result.pointsAwarded} ${result.pointsAwarded == 1 ? 'point' : 'points'} for watching',
        );

        // Every completed minute is also an ad break (still subject to the
        // backend's interval and daily caps, so it never stacks up).
        _showAdBreak(placement: 'watch_minute', afterEpisode: false);
      }
    } on ApiException {
      // A dropped heartbeat is not worth interrupting playback — the seconds
      // stay unreported and ride along with the next one.
    } finally {
      _reporting = false;
    }
  }

  /// Hand the last few unreported seconds to the server on the way out, so
  /// the meter is not behind the ring next time.
  void _flush() {
    final video = _current;
    if (video == null || _unreported <= 0) return;

    unawaited(_library
        .recordProgress(
          dramaId: video.id,
          positionSeconds: _pageSeconds,
          durationSeconds: _durationOf(video),
          watchedSeconds: _unreported,
        )
        .then((_) {}, onError: (_) {}));
  }

  void _advance() {
    if (_advancing) return;

    final next = _index + 1;
    if (next >= _videos.length) return;

    _advancing = true;
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _advancing = false;
    });
  }

  void _onPageChanged(int index) {
    final forward = index > _index;

    // Only the per-video counters start over; unreported watch time and the
    // reward ring carry on into the next video.
    setState(() {
      _index = index;
      _pageSeconds = 0;
      _paused = false;
    });

    if (index >= _videos.length - 3) _loadMore();

    // Moving on to the next video is the natural ad break. Going back to
    // rewatch is not, so it never triggers one.
    if (forward) {
      AdService.instance.noteEpisodeFinished();
      _showAdBreak();
    }
  }

  /// Shows an interstitial if one is due under the backend's rules (interval,
  /// session/day caps, and — for swipe breaks — first-after-N-videos) and is
  /// already preloaded. Otherwise does nothing, so playback just carries on.
  ///
  /// Two triggers: each completed watch minute ([afterEpisode] false) and
  /// swiping on to the next video. Both share the interval, so with a 60 s
  /// interval the viewer sees at most one ad per minute.
  void _showAdBreak({String placement = 'episode_break', bool afterEpisode = true}) {
    final ads = AdService.instance;
    final due = afterEpisode ? ads.isEpisodeInterstitialDue : ads.isInterstitialDue;
    if (!due) return;

    setState(() => _adBreak = true);

    unawaited(ads.showEpisodeInterstitialAd(
      placement: placement,
      requireEpisodes: afterEpisode,
      onAdDismissed: () {
        if (mounted) setState(() => _adBreak = false);
      },
    ));
  }

  Future<void> _share(Drama video) async {
    final text = '${video.title} on MyanCash\n${ApiConfig.dramaShareUrl(video.slug)}';

    try {
      await Share.share(text, subject: video.title);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not open the share sheet.', error: true);
    }
  }

  Future<void> _toggleFavorite(Drama video) async {
    try {
      final added = await ref.read(libraryApiProvider).toggleFavorite(video.id);
      ref.invalidate(dramaDetailProvider(video.slug));
      ref.invalidate(favoritesProvider);

      if (mounted) {
        showSnack(context, added ? 'Added to your list.' : 'Removed from your list.');
      }
    } on ApiException catch (error) {
      if (mounted) showSnack(context, error.message, error: true);
    }
  }

  void _explainReward(WatchReward meter, int balance) {
    final points = meter.pointsPerInterval;
    showSnack(
      context,
      meter.capped
          ? "You've reached today's watch reward limit. Come back tomorrow!"
          : 'Every ${_intervalLabel(meter.intervalSeconds)} you watch earns $points '
              '${points == 1 ? 'point' : 'points'}. Balance: $balance.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(sessionProvider).user?.pointsBalance ?? 0;
    final meter = ref.watch(watchMeterProvider);
    final current = _current;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Builder(builder: (context) {
        if (_videos.isEmpty) {
          if (_error != null) return ErrorView(message: _error!, onRetry: _boot);
          return const LoadingView(message: 'Loading video…');
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pages,
              scrollDirection: Axis.vertical,
              itemCount: _videos.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final video = _videos[index];

                return _VideoPage(
                  key: ValueKey(video.id),
                  video: video,
                  isActive: index == _index && !_adBreak,
                  // No ring at all when the admin has switched watch rewards off.
                  reward: index == _index && meter.enabled ? meter : null,
                  earnedThisSession: _earnedThisSession,
                  onShare: () => _share(video),
                  onFavorite: () => _toggleFavorite(video),
                  onPausedChanged: (paused) => _paused = paused,
                  onRewardTap: () => _explainReward(meter, balance),
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopBar(
                title: current?.title ?? '',
                balance: balance,
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        );
      }),
    );
  }
}

String _intervalLabel(int seconds) =>
    seconds >= 60 && seconds % 60 == 0 ? '${seconds ~/ 60} min' : '${seconds}s';

/// One full-screen video: surface, overlays, action rail.
class _VideoPage extends ConsumerStatefulWidget {
  const _VideoPage({
    super.key,
    required this.video,
    required this.isActive,
    required this.reward,
    required this.earnedThisSession,
    required this.onShare,
    required this.onFavorite,
    required this.onPausedChanged,
    required this.onRewardTap,
  });

  final Drama video;
  final bool isActive;

  /// The shared watch meter; null on pages that are not the current one.
  final WatchReward? reward;
  final int earnedThisSession;
  final VoidCallback onShare;
  final VoidCallback onFavorite;
  final ValueChanged<bool> onPausedChanged;
  final VoidCallback onRewardTap;

  @override
  ConsumerState<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends ConsumerState<_VideoPage> {
  VideoPlayerController? _video;
  YoutubePlayerController? _youtube;
  bool _videoReady = false;
  bool _paused = false;

  /// True once YouTube has reported real playback. Until then the poster stays
  /// on top, hiding the iframe's own start-up chrome (big play button, title
  /// bar, spinner).
  bool _youtubeStarted = false;
  StreamSubscription<YoutubePlayerValue>? _youtubeState;

  String? get _url {
    final url = widget.video.videoUrl;
    return url == null || url.isEmpty ? null : url;
  }

  /// TikTok-style: a tap anywhere on the video toggles playback, with no
  /// play/pause icon drawn over it.
  void _togglePause() {
    _paused = !_paused;

    if (_paused) {
      _video?.pause();
      _youtube?.pauseVideo();
    } else {
      _video?.play();
      _youtube?.playVideo();
    }

    widget.onPausedChanged(_paused);
  }

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _startPlayback();
  }

  @override
  void didUpdateWidget(covariant _VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive && !oldWidget.isActive) {
      _startPlayback();
    } else if (!widget.isActive && oldWidget.isActive) {
      _stopPlayback();
    }
  }

  @override
  void dispose() {
    _stopPlayback();
    _youtubeState?.cancel();
    _video?.dispose();
    // Each page owns its own iframe; releasing it here stops a long swipe
    // session from leaving a stack of live YouTube players behind.
    _youtube?.close();
    super.dispose();
  }

  void _startPlayback() {
    final url = _url;
    if (!widget.isActive || url == null) return;

    _paused = false;

    final videoId = _youtubeId(url);

    if (videoId != null) {
      if (_youtube != null) {
        _youtube!.playVideo();
        return;
      }

      _youtube = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showControls: false,
          showFullscreenButton: false,
          playsInline: true,
          loop: true,
          strictRelatedVideos: true,
        ),
      );

      _youtubeState = _youtube!.stream.listen((value) {
        if (!_youtubeStarted &&
            value.playerState == PlayerState.playing &&
            mounted) {
          setState(() => _youtubeStarted = true);
        }
      });

      if (mounted) setState(() {});
      return;
    }

    if (_video != null) {
      _video!.play();
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = controller;

    controller.initialize().then((_) {
      if (!mounted) return;
      controller
        ..setLooping(true)
        ..play();
      setState(() => _videoReady = true);
    }).catchError((_) {
      if (mounted) setState(() => _videoReady = false);
    });
  }

  void _stopPlayback() {
    _video?.pause();
    _youtube?.pauseVideo();
  }

  /// YouTube id from an /embed/ or /watch?v= URL, else null.
  static String? _youtubeId(String? url) {
    if (url == null) return null;

    final embed = RegExp(r'/embed/([A-Za-z0-9_-]{6,})').firstMatch(url);
    if (embed != null) return embed.group(1);

    final watch = RegExp(r'[?&]v=([A-Za-z0-9_-]{6,})').firstMatch(url);
    if (watch != null) return watch.group(1);

    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Fetching the detail records the view and brings the "my list" state.
    final detail = ref.watch(dramaDetailProvider(widget.video.slug));
    final isFavorite = detail.valueOrNull?.isFavorite ?? false;

    final ready = _url != null;
    final reward = widget.reward;

    return Stack(
      fit: StackFit.expand,
      children: [
        _surface(ready),

        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.25, 0.6, 1.0],
              colors: [
                Color(0x99000000),
                Color(0x11000000),
                Color(0x66000000),
                Color(0xF20B0B0F),
              ],
            ),
          ),
        ),

        // Tap-to-pause layer, above the video so taps never reach the YouTube
        // player (which would pause itself and draw its own big play/pause
        // icon). On the web the iframe is also made click-through in
        // web/index.html. Only taps are claimed, so vertical swipes still
        // reach the PageView.
        if (ready)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePause,
            ),
          ),

        if (!ready)
          const Center(
            child: Text(
              'This video is not available yet.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),

        Positioned(
          right: 10,
          bottom: 130,
          child: _ActionRail(
            reward: !ready || reward == null
                ? null
                : _RewardBubble(
                    meter: reward,
                    earned: widget.earnedThisSession,
                    onTap: widget.onRewardTap,
                  ),
            isFavorite: isFavorite,
            onShare: widget.onShare,
            onFavorite: widget.onFavorite,
          ),
        ),

        Positioned(
          left: 16,
          right: 86,
          bottom: 34,
          // The detail has the full synopsis; the feed item only a teaser.
          child: _Caption(video: detail.valueOrNull?.drama ?? widget.video),
        ),
      ],
    );
  }

  Widget _surface(bool ready) {
    final poster = Poster(
      url: widget.video.bannerImage ?? widget.video.coverImage,
      title: widget.video.title,
      radius: 0,
    );

    if (!ready) return poster;

    if (_youtube != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 180,
              height: 320,
              child: YoutubePlayer(
                controller: _youtube!,
                enableFullScreenOnVerticalDrag: false,
                aspectRatio: 9 / 16,
              ),
            ),
          ),
          if (!_youtubeStarted) poster,
        ],
      );
    }

    if (_video != null && _videoReady) {
      final size = _video!.value.size;
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width == 0 ? 1 : size.width,
          height: size.height == 0 ? 1 : size.height,
          child: VideoPlayer(_video!),
        ),
      );
    }

    return poster;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.balance,
    required this.onBack,
  });

  final String title;
  final int balance;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            PointsPill(points: balance, onTap: onBack),
          ],
        ),
      ),
    );
  }
}

/// Circular "watch to earn" indicator, driven by the shared watch meter.
class _RewardBubble extends StatelessWidget {
  const _RewardBubble({
    required this.meter,
    required this.earned,
    required this.onTap,
  });

  final WatchReward meter;
  final int earned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final interval = meter.intervalSeconds > 0 ? meter.intervalSeconds : 60;
    final progress = meter.capped ? 1.0 : meter.seconds / interval;

    final label = meter.capped
        ? 'Max'
        : earned > 0
            ? '+$earned'
            : _intervalLabel(interval);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        height: 62,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 62,
              height: 62,
              child: CircularProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                strokeWidth: 3.5,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(
                  meter.capped ? Colors.white38 : AppTheme.gold,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.savings_rounded, color: AppTheme.gold, size: 17),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRail extends StatelessWidget {
  const _ActionRail({
    this.reward,
    required this.isFavorite,
    required this.onShare,
    required this.onFavorite,
  });

  /// The watch-to-earn bubble. Part of the rail so it can never overlap the
  /// buttons below it.
  final Widget? reward;
  final bool isFavorite;
  final VoidCallback onShare;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (reward != null) ...[
          reward!,
          const SizedBox(height: 20),
        ],
        _RailButton(icon: Icons.share_rounded, label: 'Share', onTap: onShare),
        const SizedBox(height: 18),
        _RailButton(
          icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          label: isFavorite ? 'Saved' : 'Save',
          tint: isFavorite ? AppTheme.accent : Colors.white,
          onTap: onFavorite,
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: tint, size: 21),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.video});

  final Drama video;

  @override
  Widget build(BuildContext context) {
    final category = video.category?.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (category != null && category.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  category,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              '${Fmt.compact(video.viewCount)} views',
              style: const TextStyle(color: Colors.white60, fontSize: 10.5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          video.synopsis ?? video.tagline ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11.5,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
