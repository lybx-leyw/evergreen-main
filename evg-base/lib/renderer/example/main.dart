/// Evergreen 渲染层示例应用入口。
///
/// 展示三层渲染结构：
/// - widgets/ 组件画廊（widget_gallery.dart）
/// - shared/ 范式视图演示（paradigm_demo.dart）
/// - compositions/ 组合视图演示（composition_demo.dart）
///
/// 深色/浅色模式可切换。

import 'package:flutter/material.dart';
import 'widget_gallery.dart';
import 'paradigm_demo.dart';
import 'composition_demo.dart';

void main() {
  runApp(const RendererExampleApp());
}

class RendererExampleApp extends StatefulWidget {
  const RendererExampleApp({super.key});

  @override
  State<RendererExampleApp> createState() => _RendererExampleAppState();
}

class _RendererExampleAppState extends State<RendererExampleApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evergreen 渲染层示例',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4CAF50),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4CAF50),
        brightness: Brightness.dark,
      ),
      home: ExampleHome(toggleTheme: _toggleTheme, themeMode: _themeMode),
    );
  }
}

class ExampleHome extends StatefulWidget {
  final VoidCallback toggleTheme;
  final ThemeMode themeMode;

  const ExampleHome({
    super.key,
    required this.toggleTheme,
    required this.themeMode,
  });

  @override
  State<ExampleHome> createState() => _ExampleHomeState();
}

class _ExampleHomeState extends State<ExampleHome> {
  int _selectedIndex = 0;

  static const _pages = <String>[
    '原子组件画廊',
    '范式视图演示',
    '组合视图演示',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Evergreen 渲染层示例'),
        actions: [
          IconButton(
            icon: Icon(
              widget.themeMode == ThemeMode.light
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
            tooltip: '切换深色/浅色模式',
            onPressed: widget.toggleTheme,
          ),
        ],
      ),
      body: Column(
        children: [
          // 导航标签
          _buildNavTabs(),
          // 页面内容
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                WidgetGallery(),
                ParadigmDemo(),
                CompositionDemo(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTabs() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: List.generate(_pages.length, (index) {
              final selected = _selectedIndex == index;
              return ChoiceChip(
                label: Text(_pages[index]),
                selected: selected,
                onSelected: (v) {
                  if (v) setState(() => _selectedIndex = index);
                },
              );
            }),
          ),
        ),
      ),
    );
  }
}
