import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/routes/app_routes.dart';
import '../../contacts/presentation/contacts_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'providers/recent_calls_provider.dart';
import 'widgets/recent_call_tile.dart';
import 'widgets/home_navigation.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(activeTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: activeTab,
        children: const [
          HomeRecentView(), // Index 0: Call
          ContactsScreen(), // Index 1: Contacts
          SettingsScreen(), // Index 2: Settings
        ],
      ),
      bottomNavigationBar: const HomeBottomNavBar(),
    );
  }
}

class HomeRecentView extends ConsumerStatefulWidget {
  const HomeRecentView({super.key});

  @override
  ConsumerState<HomeRecentView> createState() => _HomeRecentViewState();
}

class _HomeRecentViewState extends ConsumerState<HomeRecentView> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(recentCallsNotifierProvider.notifier).loadRecentCalls();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calls = ref.watch(recentCallsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Icon(
              Icons.videocam_outlined,
              color: theme.colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              'Call',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Options',
            onSelected: (value) {
              if (value == 'join_instant') {
                Navigator.of(context).pushNamed(AppRoutes.instantCallJoin);
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'join_instant',
                child: Row(
                  children: [
                    Icon(Icons.add_link, size: 20),
                    SizedBox(width: 10),
                    Text('Connect to Instant Call'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (value) {
                  ref.read(searchQueryProvider.notifier).state = value;
                },
                decoration: InputDecoration(
                  hintText: 'Search call history...',
                  hintStyle: TextStyle(color: theme.colorScheme.outline),
                  icon: Icon(Icons.search, color: theme.colorScheme.outline),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),

          // Recent Calls / Messages List
          Expanded(
            child: calls.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.videocam_outlined,
                          size: 48,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No recent call logs',
                          style: TextStyle(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: calls.length,
                    itemBuilder: (context, index) {
                      final record = calls[index];
                      return RecentCallTile(
                        record: record,
                        onTap: () {
                          Navigator.of(context).pushNamed(AppRoutes.call);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).pushNamed(AppRoutes.instantCallHost);
        },
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        tooltip: 'Host Instant Call',
        child: const Icon(Icons.add_ic_call, size: 26),
      ),
    );
  }
}

