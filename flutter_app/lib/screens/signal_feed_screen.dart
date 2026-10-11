import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/cubits.dart';
import '../models/models.dart';
import '../utils/app_theme.dart';
import '../utils/stat_shimmer_card.dart';
import '../widgets/live_price_text.dart';
import '../widgets/stock_icon.dart';

// ── Symbol normalizer ─────────────────────────────────────────────────────────
// Strips exchange prefix so 'NSE:RELIANCE' → 'RELIANCE' for the price server.
String _priceSymbol(String raw) {
  final idx = raw.indexOf(':');
  return idx >= 0 ? raw.substring(idx + 1) : raw;
}

// ── Constants ─────────────────────────────────────────────────────────────────

// const _categories = ['All', 'Stocks', 'Futures', 'Options', 'Commodity'];
// const _categoryValues = [null, 'stocks', 'futures', 'options', 'commodity'];
//
// const _stockTypes = ['All', 'Intraday', 'Short Term', 'Mid Term', 'Long Term'];
// const _stockTypeValues = [null, 'intraday', 'short_term', 'medium_term', 'long_term'];
//
// const _fnoTypes = ['All', 'Intraday', 'Short Term'];
// const _fnoTypeValues = [null, 'intraday', 'short_term'];
//
// const _commodityTypes = ['All', 'Intraday', 'Short Term', 'Mid Term'];
// const _commodityTypeValues = [null, 'intraday', 'short_term', 'medium_term'];


// ── Category chip config ──────────────────────────────────────────────────────
// Each entry: (label, filterValue(s), emoji icon)
// filterValue is a List so F&O can query both 'futures' and 'options' at once.

class _CategoryChip {
  const _CategoryChip({
    required this.label,
    required this.values, // null = All
    required this.emoji,
  });
  final String label;
  final List<String>? values; // null means no category filter
  final String emoji;
}

// To re-enable the "All" category chip, uncomment the first line below
// and change _categoryIndex default back to 0 in initState.
// _CategoryChip(label: 'All', values: null, emoji: '🌐'),
const _chips = <_CategoryChip>[
  _CategoryChip(label: 'Stocks',    values: ['stocks'],                 emoji: '📈'),
  _CategoryChip(label: 'F&O',       values: ['futures', 'options'],     emoji: '📊'),
  _CategoryChip(label: 'Commodity', values: ['commodity'],              emoji: '🥇'),
  _CategoryChip(label: 'Forex',     values: ['forex'],                  emoji: '💱'),
];

// ── Type sub-filter chips ─────────────────────────────────────────────────────

class _TypeChip {
  const _TypeChip({required this.label, required this.value, required this.emoji});
  final String label;
  final String? value;   // null = All
  final String emoji;
}

const _stockTypeChips = <_TypeChip>[
  _TypeChip(label: 'All',        value: null,           emoji: '🔍'),
  _TypeChip(label: 'Intraday',   value: 'intraday',     emoji: '⚡'),
  _TypeChip(label: 'Short Term', value: 'short_term',   emoji: '📅'),
  _TypeChip(label: 'Mid Term',   value: 'medium_term',  emoji: '🗓️'),
  _TypeChip(label: 'Long Term',  value: 'long_term',    emoji: '🏦'),
];

const _fnoTypeChips = <_TypeChip>[
  _TypeChip(label: 'All',        value: null,           emoji: '🔍'),
  _TypeChip(label: 'Intraday',   value: 'intraday',     emoji: '⚡'),
  _TypeChip(label: 'Short Term', value: 'short_term',   emoji: '📅'),
];

const _commodityTypeChips = <_TypeChip>[
  _TypeChip(label: 'All',        value: null,           emoji: '🔍'),
  _TypeChip(label: 'Intraday',   value: 'intraday',     emoji: '⚡'),
  _TypeChip(label: 'Short Term', value: 'short_term',   emoji: '📅'),
  _TypeChip(label: 'Mid Term',   value: 'medium_term',  emoji: '🗓️'),
];

// Keep plain string lists for backward-compat with _typeValuesFor
const _stockTypes      = ['All', 'Intraday', 'Short Term', 'Mid Term', 'Long Term'];
const _stockTypeValues = <String?>[null, 'intraday', 'short_term', 'medium_term', 'long_term'];

const _fnoTypes      = ['All', 'Intraday', 'Short Term'];
const _fnoTypeValues = <String?>[null, 'intraday', 'short_term'];

const _commodityTypes      = ['All', 'Intraday', 'Short Term', 'Mid Term'];
const _commodityTypeValues = <String?>[null, 'intraday', 'short_term', 'medium_term'];

List<_TypeChip> _typeChipsFor(List<String>? values) {
  if (values == null) return _stockTypeChips;
  if (values.contains('futures') || values.contains('options')) return _fnoTypeChips;
  if (values.contains('commodity')) return _commodityTypeChips;
  if (values.contains('forex')) return _fnoTypeChips;
  return _stockTypeChips;
}

List<String> _typesFor(List<String>? values) {
  return _typeChipsFor(values).map((c) => c.label).toList();
}

List<String?> _typeValuesFor(List<String>? values) {
  return _typeChipsFor(values).map((c) => c.value).toList();
}

// ── Screen ────────────────────────────────────────────────────────────────────

class RecommendationFeedScreen extends StatefulWidget {
  final String? initialCategory; // e.g. 'stocks', 'futures', 'options', 'commodity'
  final String? initialType;     // e.g. 'long_term', 'intraday', 'short_term'

  const RecommendationFeedScreen({
    super.key,
    this.initialCategory,
    this.initialType,
  });

  @override
  State<RecommendationFeedScreen> createState() =>
      _RecommendationFeedScreenState();
}

class _RecommendationFeedScreenState extends State<RecommendationFeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();

  int _categoryIndex = 0;
  int _typeIndex = 0;
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    // Apply initial filters if provided from home dashboard grid buttons
    if (widget.initialCategory != null) {
      final ci = _chips.indexWhere(
        (c) => c.values != null && c.values!.contains(widget.initialCategory),
      );
      if (ci >= 0) _categoryIndex = ci;
    }
    if (widget.initialType != null) {
      final types = _typeValuesFor(_chips[_categoryIndex].values);
      final ti = types.indexOf(widget.initialType);
      if (ti >= 0) _typeIndex = ti;
    }
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load(refresh: true);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _typeIndex = 0;
    _load(refresh: true);
  }

  String get _status => _tabController.index == 0 ? 'live' : 'closed';

  // Returns the list of category values for the active chip (null = all)
  List<String>? get _selectedCategories => _chips[_categoryIndex].values;
  String? get _selectedType => _typeValuesFor(_selectedCategories)[_typeIndex];

  List<String> get _activePlanIds {
    final subState = context.read<SubscriptionCubit>().state;
    if (subState is SubscriptionLoaded) {
      return subState.subscriptions
          .where((s) => s.isEffectivelyActive)
          .map((s) => s.planId)
          .toList();
    }
    // Subscription not loaded yet — return empty list.
    // The BlocListener below will re-load once subscriptions arrive.
    return [];
  }

  /// Returns true if the user has any active subscription.
  bool get _hasAnySubscription {
    final subState = context.read<SubscriptionCubit>().state;
    if (subState is SubscriptionLoaded) {
      return subState.subscriptions.any((s) => s.isEffectivelyActive);
    }
    return false;
  }

  void _load({bool refresh = false}) {
    final cats = _selectedCategories;
    context.read<FeedCubit>().load(
      activePlanIds: _activePlanIds,
      status: _status,
      // pass single or multi category depending on chip selection
      category: cats != null && cats.length == 1 ? cats.first : null,
      categories: cats != null && cats.length > 1 ? cats : null,
      type: _selectedType,
      searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      refresh: refresh,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _buildAppBar(),
      body: BlocListener<SubscriptionCubit, SubscriptionState>(
        listener: (context, subState) {
          // Re-load whenever subscriptions finish loading so the feed uses
          // the correct plan IDs (the initial load may have fired with empty IDs).
          if (subState is SubscriptionLoaded) {
            _load(refresh: true);
          }
        },
        child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFF8FAFF),
              Color(0xFFEFF2FF),
              Color(0xFFF5F7FB),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            _buildCategoryChips(),
            const SizedBox(height: 10),
            _buildTypeChips(),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                controller: _tabController,
                children: [
                  _FeedList(
                    isLive: true,
                    activePlanIds: _activePlanIds,
                  ),
                  _FeedList(
                    isLive: false,
                    activePlanIds: _activePlanIds,
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

  PreferredSizeWidget _buildAppBar() {
    // When opened from home grid with filters, suppress the auto back button
    final isFiltered = widget.initialCategory != null;

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 12,
      automaticallyImplyLeading: false,
      leading: isFiltered
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF111827)),
              onPressed: () => Navigator.pop(context),
            )
          : null,

      title: Row(
        children: [
          // 🔥 LOGO
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFFF1F3F7),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/small_logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),

          const SizedBox(width: 14),

          // 🔥 BIGGER TAB BAR
          Expanded(
            child: Container(
              height: 44, // 🔥 increased height
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F7),
                borderRadius: BorderRadius.circular(24), // 🔥 more rounded
              ),
              child: TabBar(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),

                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20), // 🔥 bigger bubble
                ),

                indicatorPadding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 2,
                ),

                dividerColor: Colors.transparent,

                // 🔥 more breathing space
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),

                labelStyle: const TextStyle(
                  fontSize: 13, // 🔥 slightly bigger text
                  fontWeight: FontWeight.w700,
                ),

                tabs: const [
                  Tab(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flash_on, size: 16, color: Colors.green),
                          SizedBox(width: 6),
                          Text(
                            'Live',
                            style: TextStyle(color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 16, color: Colors.red),
                          SizedBox(width: 6),
                          Text(
                            'Closed',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'Search stocks...',
        border: InputBorder.none,
        hintStyle: TextStyle(color: Colors.grey.shade500),
      ),
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Color(0xFF111827),
      ),
      onChanged: (v) {
        setState(() => _searchQuery = v);
        _load(refresh: true);
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search stocks (e.g. TCS, RELIANCE)',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: InputBorder.none,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onChanged: (v) {
            setState(() => _searchQuery = v);
            _load(refresh: true);
          },
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _chips.length,
        itemBuilder: (context, i) {
          final chip = _chips[i];
          final isSelected = _categoryIndex == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() { _categoryIndex = i; _typeIndex = 0; });
                _load(refresh: true);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? Colors.transparent
                        : const Color(0xFFE5E7EB),
                    width: 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chip.emoji,
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      chip.label,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF4B5563),
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTypeChips() {
    final chips = _typeChipsFor(_selectedCategories);
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        itemBuilder: (context, i) {
          final chip = chips[i];
          final isSelected = _typeIndex == i;
          return GestureDetector(
            onTap: () {
              setState(() => _typeIndex = i);
              _load(refresh: true);
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chip.emoji,
                        style: TextStyle(
                          fontSize: isSelected ? 14 : 13,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        chip.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                          color: isSelected
                              ? AuroraColors.violet
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 3,
                    width: isSelected ? 24 : 0,
                    decoration: BoxDecoration(
                      color: AuroraColors.violet,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  // Widget _buildTypeChips() {
  //   final types = _typesFor(_selectedCategory);
  //
  //   return Container(
  //     height: 30,
  //     decoration: BoxDecoration(
  //       // color: Colors.white,
  //
  //       // 🔻 Bottom border only
  //       border: Border(
  //         bottom: BorderSide(
  //           color: Colors.grey.shade400,
  //           width: 0.6,
  //         ),
  //       ),
  //
  //       // ✨ Soft shadow (lift effect)
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black.withOpacity(0.06),
  //           blurRadius: 8,
  //           offset: const Offset(0, 3),
  //         ),
  //       ],
  //     ),
  //
  //     child: ListView.builder(
  //       scrollDirection: Axis.horizontal,
  //       padding: const EdgeInsets.symmetric(horizontal: 16),
  //       itemCount: types.length,
  //       itemBuilder: (context, i) {
  //         final selected = _typeIndex == i;
  //
  //         return Padding(
  //           padding: const EdgeInsets.only(right: 12),
  //           child: InkWell(
  //             borderRadius: BorderRadius.circular(18),
  //             onTap: () {
  //               setState(() => _typeIndex = i);
  //               _load(refresh: true);
  //             },
  //             child: Row(
  //               mainAxisSize: MainAxisSize.min,
  //               children: [
  //                 // 🔘 Radio Circle
  //                 AnimatedContainer(
  //                   duration: const Duration(milliseconds: 200),
  //                   width: 16,
  //                   height: 16,
  //                   decoration: BoxDecoration(
  //                     shape: BoxShape.circle,
  //                     border: Border.all(
  //                       width: 2,
  //                       color: selected
  //                           ? AuroraColors.violet
  //                           : Colors.grey.shade400,
  //                     ),
  //                   ),
  //                   child: Center(
  //                     child: AnimatedContainer(
  //                       duration: const Duration(milliseconds: 200),
  //                       width: selected ? 8 : 0,
  //                       height: selected ? 8 : 0,
  //                       decoration: const BoxDecoration(
  //                         shape: BoxShape.circle,
  //                         color: AuroraColors.violet,
  //                       ),
  //                     ),
  //                   ),
  //                 ),
  //
  //                 const SizedBox(width: 6),
  //
  //                 // 📝 Label
  //                 AnimatedDefaultTextStyle(
  //                   duration: const Duration(milliseconds: 200),
  //                   style: TextStyle(
  //                     fontSize: 11,
  //                     fontWeight:
  //                     selected ? FontWeight.w700 : FontWeight.w500,
  //                     color: selected
  //                         ? const Color(0xFF111827)
  //                         : const Color(0xFF6B7280),
  //                   ),
  //                   child: Text(types[i]),
  //                 ),
  //               ],
  //             ),
  //           ),
  //         );
  //       },
  //     ),
  //   );
  // }
}

// ── Feed List ─────────────────────────────────────────────────────────────────

class _FeedList extends StatefulWidget {
  const _FeedList({
    required this.isLive,
    required this.activePlanIds,
  });

  final bool isLive;
  final List<String> activePlanIds;

  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Connect live price service when the feed is first shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LivePriceCubit>().connect();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  void _loadMore() {
    context.read<FeedCubit>().loadMore(activePlanIds: widget.activePlanIds);
  }

  Future<void> _onRefresh() async {
    final cubit = context.read<FeedCubit>();
    await cubit.load(
      activePlanIds: widget.activePlanIds,
      status: widget.isLive ? 'live' : 'closed',
      category: cubit.state.category,
      categories: cubit.state.categories, // ← preserve multi-category (F&O)
      type: cubit.state.type,
      searchQuery: cubit.state.searchQuery,
      refresh: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FeedCubit, FeedCubitState>(
      listener: (context, state) {
        // Subscribe to live prices for all live trade symbols whenever items load
        if (widget.isLive && state.items.isNotEmpty) {
          final symbols = state.items
              .map((r) => _priceSymbol(r.stock.symbol))
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          context.read<LivePriceCubit>().subscribe(symbols);
        }
      },
      buildWhen: (prev, curr) => true,
      builder: (context, state) {
        if (state.isLoading && state.items.isEmpty) {
          return const FeedShimmer();
        }

        if (state.error != null && state.items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    final cubit = context.read<FeedCubit>();
                    cubit.load(
                      activePlanIds: widget.activePlanIds,
                      status: widget.isLive ? 'live' : 'closed',
                      category: cubit.state.category,
                      categories: cubit.state.categories,
                      type: cubit.state.type,
                      searchQuery: cubit.state.searchQuery,
                      refresh: true,
                    );
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (state.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        widget.isLive
                            ? 'No live calls found'
                            : 'No closed calls found',
                        style: const TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pull down to refresh',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _onRefresh,
          color: AuroraColors.violet,
          backgroundColor: Colors.white,
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: state.items.length + (state.hasMore ? 1 : 0),
            itemBuilder: (context, i) {
              // Last item slot: loading indicator while fetching next page.
              if (i == state.items.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: state.isLoading
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AuroraColors.violet,
                            ),
                          ),
                        )
                      : const TradeCardShimmer(),
                );
              }

              final rec = state.items[i];
              // Access logic:
              // 1. Closed tab — always accessible
              // 2. Live tab — accessible if user has a plan that matches trade's plan_ids
              // 3. If trade has no plan_ids assigned — accessible to anyone with any active sub
              final hasAccess = !widget.isLive ||
                  rec.planIds.isEmpty ||  // no plan restriction = visible to all subscribers
                  rec.planIds.any((p) => widget.activePlanIds.contains(p));
              final isBlurred = !hasAccess;

              if (!widget.isLive) {
                return _ClosedTradeCard(
                  rec: rec,
                  onExit: () => context.push('/recommendation/${rec.id}'),
                  onDetails: () => context.push('/recommendation/${rec.id}'),
                );
              }

              return _TradeCard(
                recommendation: rec,
                isBlurred: isBlurred,
                onTap: isBlurred
                    ? () => context.push('/plans')
                    : () => context.push('/recommendation/${rec.id}',
                        extra: {
                          "name": rec.stock.name,
                          "symbol": rec.stock.symbol,
                        }),
              );
            },
          ),
        );
      },
    );
  }
}




class _TradeCard extends StatelessWidget {
  const _TradeCard({
    required this.recommendation,
    required this.isBlurred,
    required this.onTap,
  });

  final Recommendation recommendation;
  final bool isBlurred;
  final VoidCallback onTap;


  Color _badgeColor(String badge) {
    switch (badge.toLowerCase()) {
      case "hot":
        return Colors.red;
      case "new":
        return Colors.orange;
      case "premium":
        return AuroraColors.violet;
      default:
        return Colors.grey;
    }
  }

  Color _typeBgColor(String type) {
    switch (type.toLowerCase()) {
      case "short":
        return Colors.green.shade50;
      case "mid":
        return Colors.blue.shade50;
      case "long":
        return Colors.purple.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  Color _typeTextColor(String type) {
    switch (type.toLowerCase()) {
      case "short":
        return Colors.green;
      case "mid":
        return Colors.blue;
      case "long":
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  static String _date(DateTime dt) =>
      "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year.toString().substring(2)}";

   void _showNotesDialog(BuildContext context, String notes) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        elevation: 24, // High elevation for depth
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          // Overlapping design: Use ClipRRect to ensure internal colors don't bleed
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🏷️ Header Section (Brand Solid)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  color: const Color(0xFF1A1A1A), // Deep carbon for "Solid" feel
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.description_rounded, color: Colors.black, size: 20),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        'Trade Notes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // 📝 Content Section
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F6F8), // Solid soft grey
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          notes.isNotEmpty ? notes : "No notes recorded for this trade.",
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF2D3139),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ⚡ The Punchy Action
                      SizedBox(
                        width: 120,
                        child: _SolidPunchButton(
                          icon: Icons.check_circle_outline_rounded,
                          label: "GOT IT",
                          color: AuroraColors.violet,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _SolidPunchButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withOpacity(0.2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),

            // 🎨 Pure Solid Fill (No transparency)
            color: color,

            // 🏗️ The "Solid" Weight: Sharp, directional shadow
            // This makes the button look like it's sitting ON the UI, not in it.
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 6), // Pushes the button "up"
              ),
              // Inner highlight for a 3D "molded" look
              BoxShadow(
                color: Colors.white.withOpacity(0.2),
                blurRadius: 0,
                offset: const Offset(0, -2),
                spreadRadius: -1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: Colors.white, // Contrast is key for "punch"
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900, // Maximum weight
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rec = recommendation;
    final symbol = _priceSymbol(rec.stock.symbol);

    return BlocBuilder<LivePriceCubit, LivePriceState>(
      buildWhen: (prev, curr) =>
          prev.prices[symbol]?.ltp != curr.prices[symbol]?.ltp,
      builder: (context, priceState) {
        final tick      = priceState.prices[symbol];
        final livePrice = tick?.ltp ?? rec.trade.currentPrice;
        final isBuy = rec.trade.action.toUpperCase() == "BUY";

        // For BUY:  profit = livePrice > entryPrice
        // For SELL: profit = livePrice < entryPrice (short position)
        final absGain = isBuy
            ? livePrice - rec.trade.entryPrice
            : rec.trade.entryPrice - livePrice;
        final gain = rec.trade.entryPrice > 0
            ? (absGain / rec.trade.entryPrice) * 100
            : rec.performance.gainSoFar;

        // Potential remaining to target
        // BUY:  target is above current → (target - live) / live
        // SELL: target is below current → (live - target) / live
        final potential = rec.analysis.target > 0 && livePrice > 0
            ? isBuy
                ? ((rec.analysis.target - livePrice) / livePrice) * 100
                : ((livePrice - rec.analysis.target) / livePrice) * 100
            : rec.performance.potentialLeft;

        final isProfit = gain >= 0;
        final gainColor =
            isProfit ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

        // Near target:
        // BUY:  price approaching target from below
        // SELL: price approaching target from above
        final isNearTarget = isBuy
            ? livePrice >= rec.analysis.target * 0.98
            : rec.analysis.target > 0 && livePrice <= rec.analysis.target * 1.02;
        final isOutsideRange =
            livePrice < rec.trade.rangeMin || livePrice > rec.trade.rangeMax;
        final noStoploss = rec.analysis.stoploss == null;

        // Stock's own daily change (from previous close) — from price server tick.
        // This is independent of the trade's entry price.
        final dailyChangePercent = tick?.changePercent ?? 0.0;
        final isDailyPositive    = tick?.isPositive    ?? true;
        final dailyColor = isDailyPositive
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),

              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.75),
                  Colors.white.withOpacity(0.55),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),

              border: Border.all(
                color: Colors.white.withOpacity(0.6),
                width: 1,
              ),

              boxShadow: [
                // depth shadow
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),

                // soft blue ambient glow
                BoxShadow(
                  color: const Color(0xFF3B82F6).withOpacity(0.15),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),

                // highlight (glass edge)
                BoxShadow(
                  color: Colors.white.withOpacity(0.7),
                  blurRadius: 10,
                  spreadRadius: -4,
                  offset: const Offset(-2, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// 🔹 HEADER
                Row(
                  children: [
                    Row(
                      children: [
                        // 📅 Date (refined)
                        Row(
                          children: [
                            const Icon(Icons.schedule_rounded,
                                size: 13, color: Colors.black45),
                            const SizedBox(width: 4),
                            Text(
                              _date(rec.postedAt),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(width: 8),

                        // 🏷 Badge (soft chip instead of hard block)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _badgeColor(rec.badge).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _badgeColor(rec.badge).withOpacity(0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            rec.badge.toUpperCase(),
                            style: TextStyle(
                              color: _badgeColor(rec.badge),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // Align(
                    //   alignment: Alignment.topRight,
                    //   child: Container(
                    //     padding: const EdgeInsets.symmetric(
                    //         horizontal: 14, vertical: 6),
                    //     decoration: BoxDecoration(
                    //       gradient: LinearGradient(
                    //         colors: isShort
                    //             ? [Colors.red.shade400, Colors.red.shade600]
                    //             : [Colors.teal.shade400, Colors.teal.shade700],
                    //       ),
                    //       borderRadius: BorderRadius.circular(30),
                    //       boxShadow: [
                    //         BoxShadow(
                    //           color: (isShort ? Colors.red : Colors.teal)
                    //               .withOpacity(0.4),
                    //           blurRadius: 18,
                    //           spreadRadius: 1,
                    //         ),
                    //       ],
                    //     ),
                    //     child: Text(
                    //       rec.analysis.duration.toUpperCase(),
                    //       style: const TextStyle(
                    //         color: Colors.white,
                    //         fontWeight: FontWeight.w800,
                    //         fontSize: 11,
                    //         letterSpacing: 0.8,
                    //       ),
                    //     ),
                    //   ),
                    // ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      // decoration: BoxDecoration(
                      //   color: const Color(0xFF3B82F6), // 🔵 main pill
                      //   borderRadius: BorderRadius.circular(50),
                      //   boxShadow: [
                      //     // 🔥 Inner soft glow (tight)
                      //     BoxShadow(
                      //       color: const Color(0xFF3B82F6).withOpacity(0.6),
                      //       blurRadius: 8,
                      //       spreadRadius: 1,
                      //     ),
                      //
                      //     // 🔥 Outer bubble glow (soft halo)
                      //     BoxShadow(
                      //       color: const Color(0xFF3B82F6).withOpacity(0.25),
                      //       blurRadius: 24,
                      //       spreadRadius: 6,
                      //     ),
                      //   ],
                      // ),


                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6D83F2), AuroraColors.violet],
                        ),
                        boxShadow: [

                        ],
                      ),
                      child: Text(
                        rec.analysis.duration.toUpperCase() == "1 DAY" ? "Intraday" :rec.analysis.duration.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),

                    // F&O badge — shown for options and futures
                    if (rec.trade.isFno) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          color: rec.trade.isOption
                              ? (rec.trade.optionType == 'CE'
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444))
                              : AuroraColors.violetLight,
                        ),
                        child: Text(
                          rec.trade.isOption
                              ? '${rec.trade.optionType} ${rec.trade.strikePrice?.toStringAsFixed(0) ?? ''}'
                              : 'FUT',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 12),

                /// 🔥 STOCK + PRICE
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 📊 Stock icon — NSE logo for equities, category icon for F&O/commodity/forex
                    StockIcon(
                      symbol:   rec.stock.symbol,
                      category: rec.category,
                      logoUrl:  rec.stock.logoUrl,
                      size:     40,
                      borderRadius: 12,
                    ),

                    const SizedBox(width: 12),

                    // 📈 Stock Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 🔥 Stock name (strong hierarchy)
                          Text(
                            rec.stock.symbol,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              letterSpacing: 0.1,
                              height: 1.3,
                            ),
                          ),

                          // const SizedBox(height: 4),

                          // 💰 Price + Gain Row
                          // Row(
                          //   children: [
                          //     // Price
                          //     Text(
                          //       "₹${_fmt(rec.trade.currentPrice)}",
                          //       style: const TextStyle(
                          //         fontSize: 13,
                          //         fontWeight: FontWeight.w600,
                          //         color: Colors.black87,
                          //       ),
                          //     ),
                          //
                          //     const SizedBox(width: 3),
                          //
                          //     // Divider dot (premium touch)
                          //     const Text(
                          //       "•",
                          //       style: TextStyle(color: Colors.black26),
                          //     ),
                          //
                          //     const SizedBox(width: 3),
                          //
                          //     // Gain value
                          //     Text(
                          //       "${absGain >= 0 ? '+' : ''}${_fmt(absGain)}",
                          //       style: TextStyle(
                          //         fontSize: 12.5,
                          //         fontWeight: FontWeight.w600,
                          //         color: gainColor,
                          //       ),
                          //     ),
                          //
                          //     const SizedBox(width: 4),
                          //
                          //     // Percentage
                          //     Text(
                          //       "(${gain.toStringAsFixed(2)}%)",
                          //       style: TextStyle(
                          //         fontSize: 12,
                          //         color: gainColor.withOpacity(0.85),
                          //         fontWeight: FontWeight.w500,
                          //       ),
                          //     ),
                          //   ],
                          // ),


                          // Container(
                          //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          //   decoration: BoxDecoration(
                          //     color: gainColor.withOpacity(0.08), // subtle tint based on gain/loss
                          //     borderRadius: BorderRadius.circular(10),
                          //     border: Border.all(
                          //       color: gainColor.withOpacity(0.25),
                          //       width: 0.8,
                          //     ),
                          //     boxShadow: [
                          //       BoxShadow(
                          //         color: gainColor.withOpacity(0.15),
                          //         blurRadius: 8,
                          //         spreadRadius: 0.5,
                          //         offset: const Offset(0, 2),
                          //       ),
                          //     ],
                          //   ),
                          //   child: Row(
                          //     mainAxisSize: MainAxisSize.min,
                          //     children: [
                          //       // 💰 Live Price
                          //       LivePriceText(
                          //         symbol: _priceSymbol(rec.stock.symbol),
                          //         fallbackPrice: rec.trade.currentPrice,
                          //         style: const TextStyle(
                          //           fontSize: 13.5,
                          //           fontWeight: FontWeight.w700,
                          //           color: Colors.black87,
                          //         ),
                          //       ),
                          //
                          //       const SizedBox(width: 5),
                          //
                          //       // 📊 % Highlight Chip — stock's daily change from previous close
                          //       Container(
                          //         padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          //         decoration: BoxDecoration(
                          //           color: dailyColor.withOpacity(0.18),
                          //           borderRadius: BorderRadius.circular(6),
                          //         ),
                          //         child: Text(
                          //           "${isDailyPositive ? '+' : ''}${dailyChangePercent.toStringAsFixed(2)}%",
                          //           style: TextStyle(
                          //             fontSize: 11.5,
                          //             fontWeight: FontWeight.w600,
                          //             color: dailyColor,
                          //           ),
                          //         ),
                          //       ),
                          //     ],
                          //   ),
                          // )

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: dailyColor.withOpacity(0.08), // subtle tint based on gain/loss
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: dailyColor.withOpacity(0.25),
                                width: 0.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: dailyColor.withOpacity(0.15),
                                  blurRadius: 8,
                                  spreadRadius: 0.5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 💰 Live Price
                                LivePriceText(
                                  symbol: _priceSymbol(rec.stock.symbol),
                                  fallbackPrice: rec.trade.currentPrice,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),

                                const SizedBox(width: 5),

                                // 📊 % Highlight Chip — stock's daily change from previous close
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: dailyColor.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    "${isDailyPositive ? '+' : ''}${dailyChangePercent.toStringAsFixed(2)}%",
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: dailyColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                /// 📈 TREND BAR
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: (gain.abs() / 10).clamp(0.1, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          colors: isProfit
                              ? [Color(0xFF22C55E), Color(0xFF16A34A)]
                              : [Color(0xFFEF4444), Color(0xFFDC2626)],
                        ),
                        // boxShadow: [
                        //   BoxShadow(
                        //     color: gainColor.withOpacity(0.6),
                        //     blurRadius: 10,
                        //     spreadRadius: 1,
                        //   ),
                        // ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                /// 🎯 PERFORMANCE STRIP
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    // gradient: LinearGradient(
                    //   colors: [
                    //     const Color(0xFF22C55E).withOpacity(0.15),
                    //     const Color(0xFF3B82F6).withOpacity(0.12),
                    //   ],
                    // ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.6),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Gain: ${gain.toStringAsFixed(2)}%",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: gainColor,
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // 🔥 Premium divider
                      Container(
                        height: 20,
                        width: 1,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),

                          // 🔥 Core gradient (smooth fade)
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xFF3B82F6).withOpacity(0.9),
                              const Color(0xFF3B82F6),
                              const Color(0xFF3B82F6).withOpacity(0.9),
                              Colors.transparent,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),

                          // 🔥 Soft glow (bubble style)
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.35),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.15),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          "Potential: ${potential.toStringAsFixed(2)}%",
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                /// 📊 TABLE
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.9),
                        Colors.blue.shade50.withOpacity(0.3),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.6),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      /// 🔹 HEADER (muted + structured)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Expanded(
                            child: Text(
                              "Date",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                "Action",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.black45,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Price",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Range",
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      /// 🔥 Divider (premium subtle)
                      Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.15),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      /// 🔹 DATA ROW
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _date(rec.postedAt),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                          Expanded(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (isBuy ? Colors.green : Colors.red)
                                      .withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: (isBuy ? Colors.green : Colors.red)
                                        .withOpacity(0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isBuy ? "Buy" : "Sell",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isBuy ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Expanded(
                            child: Text(
                              _fmt(rec.trade.entryPrice),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                          Expanded(
                            child: Text(
                              "${_fmt(rec.trade.rangeMin)} - ${_fmt(rec.trade.rangeMax)}",
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                /// 🧠 DETAILS
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.7),
                        Colors.white.withOpacity(0.5),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _info(
                        "SL",
                        rec.analysis.stoploss != null
                            ? "₹${_fmt(rec.analysis.stoploss!)}"
                            : "--",
                      )),

                      // 🔹 Divider
                      Container(
                        height: 28,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: Colors.black12,
                      ),

                      Expanded(child: _info(
                        "Target",
                        "₹${_fmt(rec.analysis.target)}",
                      )),

                      // 🔹 Divider
                      Container(
                        height: 28,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: Colors.black12,
                      ),

                      Expanded(child: _info(
                        "Duration",
                        rec.analysis.duration,
                      )),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                /// 📈 CHART BUTTON & NOTES BUTTON
                // Row(
                //   mainAxisAlignment: MainAxisAlignment.end,
                //   children: [
                //     // Notes button (only show if notes exist)
                //     if (rec.notes != null && rec.notes!.isNotEmpty) ...[
                //       InkWell(
                //         borderRadius: BorderRadius.circular(10),
                //         onTap: () => _showNotesDialog(context, rec.notes!),
                //         child: Container(
                //           padding: const EdgeInsets.symmetric(
                //               horizontal: 14, vertical: 8),
                //           decoration: BoxDecoration(
                //             // color: Colors.amber.withOpacity(0.08),
                //             borderRadius: BorderRadius.circular(10),
                //             color: Colors.amber.withOpacity(0.12),
                //             border: Border.all(color: Colors.amber.withOpacity(0.35)),
                //           ),
                //           child: const Row(
                //             mainAxisSize: MainAxisSize.min,
                //             children: [
                //               Icon(Icons.note_outlined,
                //                   size: 16, color: Colors.amber),
                //               SizedBox(width: 6),
                //               Text(
                //                 'Notes',
                //                 style: TextStyle(
                //                   fontSize: 12,
                //                   fontWeight: FontWeight.w700,
                //                   color: Colors.amber,
                //                 ),
                //               ),
                //             ],
                //           ),
                //         ),
                //       ),
                //       const SizedBox(width: 8),
                //     ],
                //
                //     // Chart button
                //     InkWell(
                //       borderRadius: BorderRadius.circular(10),
                //       onTap: () => context.push('/chart/${rec.stock.symbol}'),
                //       child: Container(
                //         padding: const EdgeInsets.symmetric(
                //             horizontal: 14, vertical: 8),
                //         decoration: BoxDecoration(
                //           // color: AuroraColors.violet.withOpacity(0.08),
                //           borderRadius: BorderRadius.circular(10),
                //           // border: Border.all(
                //           //     color: AuroraColors.violet.withOpacity(0.3)),
                //
                //
                //
                //           color: AuroraColors.violet.withOpacity(0.12),
                //           border: Border.all(color: AuroraColors.violet.withOpacity(0.35)),
                //         ),
                //         child: const Row(
                //           mainAxisSize: MainAxisSize.min,
                //           children: [
                //             Icon(Icons.candlestick_chart_outlined,
                //                 size: 16, color: AuroraColors.violet),
                //             SizedBox(width: 6),
                //             Text(
                //               'View Chart',
                //               style: TextStyle(
                //                 fontSize: 12,
                //                 fontWeight: FontWeight.w700,
                //                 color: AuroraColors.violet,
                //               ),
                //             ),
                //           ],
                //         ),
                //       ),
                //     ),
                //   ],
                // ),


                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Execute button — only shown for accessible live signals
                    if (!isBlurred) ...[
                      _minimalSolidPunchButton(
                        icon: Icons.bolt_rounded,
                        label: "Execute",
                        color: isBuy
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                        onTap: () => context.push(
                          '/recommendation/${rec.id}',
                          extra: {
                            'name':   rec.stock.name,
                            'symbol': rec.stock.symbol,
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _minimalSolidPunchButton(
                      icon: Icons.candlestick_chart_outlined,
                      label: "View Chart",
                      color: AuroraColors.violet,
                      onTap: () => context.push('/chart/${rec.stock.symbol}'),
                    ),
                  ],
                ),

                // Notes shown inline — full width below actions
                if (rec.notes != null && rec.notes!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE0E4F0)),
                    ),
                    child: Text(
                      rec.notes!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ],

                /// ⚠️ WARNINGS
                if (isOutsideRange || isNearTarget || noStoploss)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFF59E0B).withOpacity(0.15),
                          const Color(0xFFF97316).withOpacity(0.10),
                        ],
                      ),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withOpacity(0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withOpacity(0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 🔥 Icon with soft background
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6,vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade700,
                            size: 6,
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Text(
                            isOutsideRange
                                ? "Trade is outside buying range. Be cautious."
                                : isNearTarget
                                ? "Price is near target. Limited upside left."
                                : "No stoploss defined. Risk is high.",
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              height: 1.4, // ✨ better readability
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          /// 🔒 LOCK OVERLAY
          if (isBlurred)

            // if (isBlurred)
            //   Positioned.fill(
            //     child: ClipRRect(
            //       borderRadius: BorderRadius.circular(24), // same as card
            //       child: BackdropFilter(
            //         filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            //         child: Container(
            //           decoration: BoxDecoration(
            //             borderRadius: BorderRadius.circular(24),
            //             color: Colors.white.withOpacity(0.65),
            //           ),
            //           child: Center(
            //             child: Padding(
            //               padding: const EdgeInsets.all(24),
            //               child: Column(
            //                 mainAxisSize: MainAxisSize.min,
            //                 children: [
            //                   Container(
            //                     padding: const EdgeInsets.all(12),
            //                     decoration: const BoxDecoration(
            //                       shape: BoxShape.circle,
            //                       gradient: LinearGradient(
            //                         colors: [
            //                           AuroraColors.violetLight,
            //                           AuroraColors.violet,
            //                         ],
            //                       ),
            //                     ),
            //                     child: const Icon(
            //                       Icons.lock_outline,
            //                       color: Colors.white,
            //                       size: 26,
            //                     ),
            //                   ),
            //
            //                   const SizedBox(height: 14),
            //
            //                   const Text(
            //                     'Unlock Premium Trade',
            //                     style: TextStyle(
            //                       fontWeight: FontWeight.w800,
            //                       fontSize: 16,
            //                     ),
            //                   ),
            //
            //                   const SizedBox(height: 8),
            //
            //                   const Text(
            //                     'Get full access to entry, target & stoploss\nwith expert insights',
            //                     textAlign: TextAlign.center,
            //                   ),
            //
            //                   const SizedBox(height: 18),
            //
            //                   SizedBox(
            //                     width: double.infinity,
            //                     height: 42,
            //                     child: ElevatedButton(
            //                       onPressed: onTap,
            //                       child: const Text('Unlock Now →'),
            //                     ),
            //                   ),
            //                 ],
            //               ),
            //             ),
            //           ),
            //         ),
            //       ),
            //     ),
            //   ),
            Positioned.fill(
              top: 0,   // 👈 adjust based on your layout
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),

                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      // height: 320,
                      // margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.75),
                            Colors.white.withOpacity(0.55),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.4),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [

                          /// 🔒 ICON WITH BACKGROUND
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [AuroraColors.violetLight, AuroraColors.violet],
                              ),
                            ),
                            child: const Icon(
                              Icons.lock_outline,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),

                          const SizedBox(height: 14),

                          /// 🔥 TITLE
                          const Text(
                            'Unlock Premium Trade',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: Color(0xFF1F2937),
                              letterSpacing: 0.2,
                            ),
                          ),

                          const SizedBox(height: 6),

                          /// 💬 SUBTITLE
                          const Text(
                            'Get full access to entry, target & stoploss\nwith expert insights',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: Colors.black54,
                            ),
                          ),

                          const SizedBox(height: 18),

                          /// 🚀 PREMIUM BUTTON
                          Container(
                            width: double.infinity,
                            height: 42,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: const LinearGradient(
                                colors: [AuroraColors.violetLight, AuroraColors.violet],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AuroraColors.violet.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: onTap,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                "Unlock Now →",
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Colors.white
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          /// 🔐 SMALL NOTE
                          const Text(
                            'Only for premium members',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
      }, // BlocBuilder builder
    ); // BlocBuilder
  }

  Widget _minimalSolidPunchButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withOpacity(0.2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),

            // 🎨 Pure Solid Fill (No transparency)
            color: color,

            // 🏗️ The "Solid" Weight: Sharp, directional shadow
            // This makes the button look like it's sitting ON the UI, not in it.
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 6), // Pushes the button "up"
              ),
              // Inner highlight for a 3D "molded" look
              BoxShadow(
                color: Colors.white.withOpacity(0.2),
                blurRadius: 0,
                offset: const Offset(0, -2),
                spreadRadius: -1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: Colors.white, // Contrast is key for "punch"
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900, // Maximum weight
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _glassButton({
    required IconData icon,
    required String label,
    required Color baseColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),

          // 🌈 glass gradient
          gradient: LinearGradient(
            colors: [
              baseColor.withOpacity(0.18),
              baseColor.withOpacity(0.10),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),

          // 🧊 soft glass border
          border: Border.all(
            color: Colors.white.withOpacity(0.6),
            width: 1,
          ),

          boxShadow: [
            // 🌑 depth
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),

            // 🌟 color glow
            BoxShadow(
              color: baseColor.withOpacity(0.35),
              blurRadius: 20,
              spreadRadius: 1,
            ),

            // ✨ top highlight (glass shine)
            BoxShadow(
              color: Colors.white.withOpacity(0.8),
              blurRadius: 6,
              spreadRadius: -3,
              offset: const Offset(-2, -2),
            ),
          ],
        ),

        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: baseColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: baseColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _minimalSolidButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        splashColor: color.withOpacity(0.1),
        highlightColor: color.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),

            // 🧱 Solid Body: Higher opacity base for a "physical" feel
            color: color.withOpacity(0.12),

            // 🦾 Punchy Border: Higher contrast to define the shape
            border: Border.all(
              color: color.withOpacity(0.4),
              width: 1.2,
            ),

            // 📐 Defined Shadow: Short, dark, and sharp (less "glow," more "object")
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18, // Slightly larger for "punch"
                color: color.withOpacity(1.0), // Full vibrance
              ),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(), // Uppercase for a more authoritative, solid look
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800, // Heavy weight for "solid" feel
                  color: color.withOpacity(1.0),
                  letterSpacing: 0.8, // Increased tracking for premium readability
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
class _ClosedTradeCard extends StatelessWidget {
  const _ClosedTradeCard({
    required this.rec,
    required this.onExit,
    required this.onDetails,
  });

  final Recommendation rec;
  final VoidCallback onExit;
  final VoidCallback onDetails;

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _dateTime(DateTime dt) {
    // Firestore returns UTC — convert to IST (UTC+5:30) explicitly
    final ist = dt.isUtc
        ? dt.add(const Duration(hours: 5, minutes: 30))
        : dt.toUtc().add(const Duration(hours: 5, minutes: 30));

    const months = [
      "Jan","Feb","Mar","Apr","May","Jun",
      "Jul","Aug","Sep","Oct","Nov","Dec"
    ];

    final day = ist.day.toString().padLeft(2, '0');
    final month = months[ist.month - 1];

    int hour = ist.hour % 12;
    if (hour == 0) hour = 12;

    final min = ist.minute.toString().padLeft(2, '0');
    final ampm = ist.hour >= 12 ? "PM" : "AM";

    return "$day $month, $hour:$min $ampm";
  }

  @override
  Widget build(BuildContext context) {
    final isShort = rec.analysis.duration.toLowerCase().contains("short");
    final gain = rec.performance.gainSoFar;

    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      child: Stack(
        children: [

          /// 🌈 BACK GLOW (NEW)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: RadialGradient(
                  colors: [
                    (gain >= 0 ? Colors.green : Colors.red)
                        .withOpacity(0.15),
                    Colors.transparent,
                  ],
                  radius: 1.2,
                  center: Alignment.topRight,
                ),
              ),
            ),
          ),

          /// 🧾 MAIN CARD
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),

              /// 🌫 GLASS STYLE
              color: Colors.white.withOpacity(0.9),

              border: Border.all(
                color: Colors.grey.withOpacity(0.6),
                width: 1,
              ),

              boxShadow: [
                /// Soft shadow
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 25,
                  offset: const Offset(0, 12),
                ),

                /// Light top highlight
                BoxShadow(
                  color: Colors.white.withOpacity(0.6),
                  blurRadius: 10,
                  offset: const Offset(-4, -4),
                ),
              ],
            ),

            child: Column(
              children: [

                /// 🔴 TOP RIBBON (GLOW UPGRADE)
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isShort
                            ? [Colors.red.shade400, Colors.red.shade600]
                            : [Colors.teal.shade400, Colors.teal.shade700],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: (isShort ? Colors.red : Colors.teal)
                              .withOpacity(0.4),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Text(
                      rec.analysis.duration.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                /// 🧾 INNER CARD
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),

                  child: Column(
                    children: [

                      /// 🔹 HEADER
                      Row(
                        children: [
                          /// 💎 STOCK ICON (dynamic — logo / category / fallback)
                          StockIcon(
                            symbol: rec.stock.symbol,
                            category: rec.category,
                            logoUrl: rec.stock.logoUrl,
                            size: 48,
                            borderRadius: 14,
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              rec.stock.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),

                          /// 🟢/🔴 PROFIT / LOSS BADGE (GLASS)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: (gain >= 0 ? Colors.green : Colors.red)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              gain >= 0 ? "PROFIT" : "LOSS",
                              style: TextStyle(
                                color: gain >= 0 ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      /// 📊 TABLE HEADER (SOFTER)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),

                          /// 🌫 Glassy background
                          color: Colors.white.withOpacity(0.9),

                          border: Border.all(
                            color: Colors.black.withOpacity(0.04),
                          ),

                          boxShadow: [
                            /// depth
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),

                            /// soft highlight
                            BoxShadow(
                              color: Colors.white.withOpacity(0.7),
                              blurRadius: 10,
                              offset: const Offset(-3, -3),
                            ),
                          ],
                        ),

                        child: Column(
                          children: [

                            /// 🔹 HEADER (Modern pill style)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      "Action",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Center(
                                      child: Text(
                                        "Date",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        "Price",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            /// 📊 BUY ROW
                            _row(
                              action: "Buy",
                              actionColor: Colors.green,
                              date: _dateTime(rec.postedAt),
                              price: _fmt(rec.trade.entryPrice),
                            ),

                            /// 🔥 Divider (modern subtle)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: Colors.grey.shade200,
                              ),
                            ),

                            /// 📊 EXIT ROW
                            _row(
                              action: "Exit",
                              actionColor: Colors.blue,
                              date: _dateTime(
                                  rec.trade.exitDate ?? DateTime(2005)),
                              price: _fmt(rec.trade.exitPrice ?? 0.0),
                            ),



                          ],
                        ),
                      ),


                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gain >= 0
                                ? [Colors.green.shade400, Colors.green.shade600]
                                : [Colors.red.shade400, Colors.red.shade600],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: (gain >= 0 ? Colors.green : Colors.red)
                                  .withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            gain >= 0
                                ? "Net gain: +${gain.toStringAsFixed(2)}% in ${rec.analysis.duration}"
                                : "Net loss: ${gain.toStringAsFixed(2)}% in ${rec.analysis.duration}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),



                /// 🟢 NET GAIN (GLOW STRIP)

              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required String action,
    required Color actionColor,
    required String date,
    required String price,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Row(
        children: [
          /// Action (Left)
          Expanded(
            flex: 2,
            child: Text(
              action,
              style: TextStyle(
                color: actionColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          /// Date (Center)
          Expanded(
            flex: 3,
            child: Center(
              child: Text(
                date,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),

          /// Price (Right)
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                price,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _TableCol extends StatelessWidget {
  const _TableCol({
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  final String label;
  final String value;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 5),

          /// VALUE CONTAINER (premium touch)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: isHighlight
                ? BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
              ),
              borderRadius: BorderRadius.circular(6),
            )
                : null,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

