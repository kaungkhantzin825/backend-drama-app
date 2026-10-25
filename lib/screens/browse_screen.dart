import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'player_screen.dart';

/// Search and browse the catalogue.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  String _query = '';
  String? _category;
  String _sort = 'latest';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Debounce so a fast typist does not fire a request per keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = BrowseQuery(category: _category, query: _query, sort: _sort);
    final results = ref.watch(browseProvider(key));
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Browse'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _controller,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search titles, tropes, tags…',
                    hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 20),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: AppTheme.textSecondary,
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          ),
                    filled: true,
                    fillColor: AppTheme.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 38,
                child: categories.maybeWhen(
                  data: (list) => ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _Chip(
                          label: 'All',
                          selected: _category == null,
                          onTap: () => setState(() => _category = null),
                        );
                      }
                      final category = list[index - 1];
                      return _Chip(
                        label: category.name,
                        selected: _category == category.slug,
                        onTap: () => setState(
                          () => _category = _category == category.slug ? null : category.slug,
                        ),
                      );
                    },
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
      body: results.when(
        loading: () => const LoadingView(message: 'Searching…'),
        error: (error, _) => ErrorView(
          message: '$error',
          onRetry: () => ref.invalidate(browseProvider(key)),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return EmptyView(
              message: _query.isEmpty
                  ? 'Nothing here yet.'
                  : 'No titles match "$_query".',
              icon: Icons.search_off_rounded,
            );
          }

          return RefreshIndicator(
            color: AppTheme.accent,
            backgroundColor: AppTheme.surface,
            onRefresh: () async => ref.invalidate(browseProvider(key)),
            child: Column(
              children: [
                _SortBar(
                  sort: _sort,
                  total: page.total,
                  onChanged: (value) => setState(() => _sort = value),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.56,
                    ),
                    itemCount: page.items.length,
                    itemBuilder: (context, index) {
                      final drama = page.items[index];
                      return DramaCard(
                        drama: drama,
                        width: double.infinity,
                        onTap: () => openPlayer(context, drama),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppTheme.accent : AppTheme.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.sort, required this.total, required this.onChanged});

  final String sort;
  final int total;
  final ValueChanged<String> onChanged;

  static const _options = {
    'latest': 'Newest',
    'popular': 'Popular',
    'rating': 'Top rated',
    'title': 'A–Z',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Text(
            '$total title${total == 1 ? '' : 's'}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const Spacer(),
          DropdownButton<String>(
            value: sort,
            isDense: true,
            underline: const SizedBox.shrink(),
            dropdownColor: AppTheme.surfaceHigh,
            icon: const Icon(Icons.expand_more_rounded, size: 18, color: AppTheme.textSecondary),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12.5),
            items: _options.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ],
      ),
    );
  }
}
