import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/registry/modules.dart';
import '../modules.dart';

/// A single command palette item (mirrors sidebar items).
class _PaletteItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final String category;

  const _PaletteItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.category,
  });
}

const _recentKey = 'command_palette_recent';

/// 全局命令面板 — Ctrl+K 打开。
///
/// 支持模糊搜索、键盘导航、最近访问。
/// 搜索条目从 [ModuleRegistry.paletteItems] 生成，无需硬编码。
class CommandPalette extends StatefulWidget {
  final SharedPreferences _prefs;
  final List<PaletteItemDecl> _items;

  const CommandPalette._({
    required SharedPreferences prefs,
    required List<PaletteItemDecl> items,
    super.key,
  })  : _prefs = prefs,
      _items = items;

  /// 显示命令面板（必须在 UI 启动后调用）。
  static Future<void> show(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;

    final container = ProviderScope.containerOf(context);
    final registry = container.read(moduleRegistryProvider);

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => CommandPalette._(
        prefs: prefs,
        items: registry.paletteItems,
      ),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedIndex = 0;
  List<_PaletteItem> _filtered = [];
  List<String> _recentRoutes = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _filter('');
  }

  void _loadRecent() {
    final raw = widget._prefs.getStringList(_recentKey) ?? [];
    _recentRoutes = raw;
  }

  Future<void> _saveRecent(String route) async {
    _recentRoutes.remove(route);
    _recentRoutes.insert(0, route);
    if (_recentRoutes.length > 5) {
      _recentRoutes = _recentRoutes.sublist(0, 5);
    }
    await widget._prefs.setStringList(_recentKey, _recentRoutes);
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    final allItems = widget._items.map((p) => _PaletteItem(
          title: p.title,
          subtitle: p.subtitle,
          icon: p.icon,
          route: p.route,
          category: p.category,
        )).toList();
    if (q.isEmpty) {
      _filtered = List.of(allItems);
    } else {
      _filtered = allItems.where((item) {
        return item.title.toLowerCase().contains(q) ||
            item.subtitle.toLowerCase().contains(q) ||
            item.category.toLowerCase().contains(q);
      }).toList();
    }

    // Sort: recent first, then by title
    _filtered.sort((a, b) {
      final aRecent = _recentRoutes.contains(a.route);
      final bRecent = _recentRoutes.contains(b.route);
      if (aRecent && !bRecent) return -1;
      if (!aRecent && bRecent) return 1;
      return a.title.compareTo(b.title);
    });

    _selectedIndex = 0;
    setState(() {});
  }

  void _navigate(String route) {
    _saveRecent(route);
    Navigator.of(context).pop();
    GoRouter.of(context).go(route);
  }

  void _handleKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent || _filtered.isEmpty) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % _filtered.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            (_selectedIndex - 1 + _filtered.length) % _filtered.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      _navigate(_filtered[_selectedIndex].route);
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: _handleKey,
      child: AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search field
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _filter,
                  decoration: InputDecoration(
                    hintText: '搜索功能、页面...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _filter('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              // Results list
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: _filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '没有匹配的结果',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 8),
                          shrinkWrap: true,
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final item = _filtered[index];
                            final selected = index == _selectedIndex;
                            final isRecent =
                                _recentRoutes.contains(item.route);

                            return ListTile(
                              leading: Icon(
                                item.icon,
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              title: Text(
                                item.title,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(item.subtitle),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isRecent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme
                                            .primaryContainer,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '最近',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color:
                                              theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.category,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme
                                          .colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              selected: selected,
                              selectedTileColor:
                                  theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onTap: () => _navigate(item.route),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
