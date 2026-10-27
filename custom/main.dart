// FILE: custom/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PixelColor {
  final String name;
  final Color color;
  const PixelColor(this.name, this.color);
}

const List<PixelColor> seedOptions = [
  PixelColor('Indigo', Color(0xFF4B5C92)),
  PixelColor('Obsidian', Color(0xFF1C1C1E)),
  PixelColor('Porcelain', Color(0xFFF4F0EA)),
  PixelColor('Frost', Color(0xFFD6E4F0)),
  PixelColor('Lemongrass', Color(0xFFD8E698)),
  PixelColor('Peony', Color(0xFFF29CB6)),
  PixelColor('Jade', Color(0xFFA3C9A8)),
  PixelColor('Moonstone', Color(0xFF8FA3B0)),
];

enum IconShape {
  circle,
  squircle,
  roundedSquare,
  teardrop,
  pebble,
  sharp,
}

const Map<IconShape, String> shapeNames = {
  IconShape.circle: 'Circle',
  IconShape.squircle: 'Squircle',
  IconShape.roundedSquare: 'Rounded',
  IconShape.teardrop: 'Teardrop',
  IconShape.pebble: 'Pebble',
  IconShape.sharp: 'Sharp',
};

ShapeBorder buildIconShape(IconShape shape, double size) {
  switch (shape) {
    case IconShape.circle:
      return const CircleBorder();
    case IconShape.squircle:
      return ContinuousRectangleBorder(
        borderRadius: BorderRadius.circular(size * 0.68),
      );
    case IconShape.roundedSquare:
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(size * 0.24),
      );
    case IconShape.teardrop:
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(size * 0.5),
          topRight: Radius.circular(size * 0.5),
          bottomLeft: Radius.circular(size * 0.5),
          bottomRight: Radius.circular(size * 0.14),
        ),
      );
    case IconShape.pebble:
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(size * 0.48),
          bottomRight: Radius.circular(size * 0.48),
          topRight: Radius.circular(size * 0.22),
          bottomLeft: Radius.circular(size * 0.22),
        ),
      );
    case IconShape.sharp:
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(size * 0.08),
      );
  }
}

class AppItem {
  final String name;
  final String pkg;
  final Uint8List icon;
  final MemoryImage provider;
  AppItem({required this.name, required this.pkg, required this.icon})
      : provider = MemoryImage(icon);
}

class LauncherState extends ChangeNotifier {
  static const MethodChannel _ch = MethodChannel('caesiumlauncher/native');
  SharedPreferences? _prefs;

  List<AppItem> apps = [];
  List<String> dockPkgs = [];
  Map<int, String> homeSlots = {};
  
  Map<String, List<String>> categories = {
    'Social & Chat': [],
    'Media & Audio': [],
    'Tools & System': [],
    'Games': [],
  };

  bool loading = true;
  bool amoledMode = false;
  bool glassEffect = true;
  bool dynamicWallpaperColor = true;
  int seedIndex = 0;
  int gridCols = 4;
  int gridRows = 4;
  bool showLabels = true;
  IconShape iconShape = IconShape.squircle;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    amoledMode = _prefs?.getBool('amoled') ?? false;
    glassEffect = _prefs?.getBool('glass') ?? true;
    dynamicWallpaperColor = _prefs?.getBool('dyn') ?? true;
    seedIndex = (_prefs?.getInt('seed') ?? 0).clamp(0, seedOptions.length - 1);
    gridCols = (_prefs?.getInt('cols') ?? 4).clamp(4, 5);
    gridRows = (_prefs?.getInt('rows') ?? 4).clamp(4, 5);
    showLabels = _prefs?.getBool('labels') ?? true;
    final shapeIdx = (_prefs?.getInt('shape') ?? 1)
        .clamp(0, IconShape.values.length - 1);
    iconShape = IconShape.values[shapeIdx];
    dockPkgs = _prefs?.getStringList('dock') ?? [];

    final rawSlots = _prefs?.getStringList('home_slots') ?? [];
    homeSlots = {};
    for (int i = 0; i < rawSlots.length; i++) {
      if (rawSlots[i].isNotEmpty) {
        homeSlots[i] = rawSlots[i];
      }
    }

    final savedCats = _prefs?.getString('categories');
    if (savedCats != null) {
      try {
        final decoded = jsonDecode(savedCats) as Map;
        categories = decoded.map((k, v) => MapEntry(k as String, List<String>.from(v as List)));
      } catch (_) {}
    }

    notifyListeners();
    await refreshApps();
  }

  void _saveHomeSlots() {
    final total = gridCols * gridRows;
    final list = List.generate(total, (i) => homeSlots[i] ?? '');
    _prefs?.setStringList('home_slots', list);
  }

  void _saveCategories() {
    _prefs?.setString('categories', jsonEncode(categories));
    notifyListeners();
  }

  void assignCategory(String pkg, String category) {
    categories.forEach((cat, list) {
      list.remove(pkg);
    });
    if (category.isNotEmpty) {
      categories[category] ??= [];
      categories[category]!.add(pkg);
    }
    _saveCategories();
  }

  String getAppCategory(String pkg) {
    for (final entry in categories.entries) {
      if (entry.value.contains(pkg)) return entry.key;
    }
    return 'Uncategorized';
  }

  Future<void> refreshApps() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('getApps');
      if (raw != null) {
        final loaded = <AppItem>[];
        for (final item in raw) {
          if (item is Map) {
            final name = (item['name'] as String?) ?? 'App';
            final pkg = (item['pkg'] as String?) ?? '';
            final icon = item['icon'] as Uint8List?;
            if (pkg.isNotEmpty && icon != null) {
              loaded.add(AppItem(name: name, pkg: pkg, icon: icon));
            }
          }
        }
        apps = loaded;

        if (dockPkgs.isEmpty && apps.isNotEmpty) {
          final defaults = <String>[];
          for (final a in apps) {
            final l = a.pkg.toLowerCase();
            if (l.contains('dialer') ||
                l.contains('contacts') ||
                l.contains('messaging') ||
                l.contains('mms') ||
                l.contains('chrome') ||
                l.contains('browser') ||
                l.contains('camera') ||
                l.contains('audio_player') ||
                l.contains('vending')) {
              if (!defaults.contains(a.pkg)) defaults.add(a.pkg);
            }
            if (defaults.length >= 4) break;
          }
          if (defaults.length < 4) {
            for (final a in apps) {
              if (!defaults.contains(a.pkg)) defaults.add(a.pkg);
              if (defaults.length >= 4) break;
            }
          }
          dockPkgs = defaults;
          _prefs?.setStringList('dock', dockPkgs);
        }

        bool catChanged = false;
        for (final a in apps) {
          if (getAppCategory(a.pkg) == 'Uncategorized') {
            final l = a.pkg.toLowerCase();
            final name = a.name.toLowerCase();
            if (l.contains('whatsapp') || l.contains('telegram') || l.contains('discord') || l.contains('snapchat') || l.contains('message') || l.contains('twitter') || l.contains('reddit')) {
              categories['Social & Chat'] ??= [];
              categories['Social & Chat']!.add(a.pkg);
              catChanged = true;
            } else if (l.contains('spotify') || l.contains('youtube') || l.contains('music') || l.contains('audio_player') || l.contains('netflix') || l.contains('media') || l.contains('camera')) {
              categories['Media & Audio'] ??= [];
              categories['Media & Audio']!.add(a.pkg);
              catChanged = true;
            } else if (name.contains('game') || l.contains('minecraft') || l.contains('fortnite')) {
              categories['Games'] ??= [];
              categories['Games']!.add(a.pkg);
              catChanged = true;
            } else {
              categories['Tools & System'] ??= [];
              categories['Tools & System']!.add(a.pkg);
              catChanged = true;
            }
          }
        }
        if (catChanged) _saveCategories();

        if (homeSlots.isEmpty && apps.isNotEmpty) {
          int slot = 0;
          for (final a in apps) {
            if (!dockPkgs.contains(a.pkg)) {
              homeSlots[slot] = a.pkg;
              slot++;
              if (slot >= gridCols * gridRows) break;
            }
          }
          _saveHomeSlots();
        }
      }
    } catch (_) {}
    loading = false;
    notifyListeners();
  }

  List<AppItem> get dockApps {
    final map = {for (final a in apps) a.pkg: a};
    return [
      for (final p in dockPkgs)
        if (map[p] != null) map[p]!
    ];
  }

  void toggleDock(String pkg) {
    if (dockPkgs.contains(pkg)) {
      dockPkgs.remove(pkg);
    } else {
      if (dockPkgs.length >= 5) dockPkgs.removeLast();
      dockPkgs.add(pkg);
    }
    _prefs?.setStringList('dock', dockPkgs);
    notifyListeners();
  }

  void moveHomeSlot(int fromIndex, int toIndex) {
    final appPkg = homeSlots[fromIndex];
    final targetPkg = homeSlots[toIndex];

    if (appPkg != null) {
      homeSlots[toIndex] = appPkg;
      if (targetPkg != null) {
        homeSlots[fromIndex] = targetPkg;
      } else {
        homeSlots.remove(fromIndex);
      }
      _saveHomeSlots();
      notifyListeners();
    }
  }

  void addOrMoveToHome(String pkg) {
    if (homeSlots.containsValue(pkg)) return;
    for (int i = 0; i < gridCols * gridRows; i++) {
      if (!homeSlots.containsKey(i)) {
        homeSlots[i] = pkg;
        _saveHomeSlots();
        notifyListeners();
        break;
      }
    }
  }

  void removeFromHome(String pkg) {
    homeSlots.removeWhere((k, v) => v == pkg);
    _saveHomeSlots();
    notifyListeners();
  }

  void setIconShape(IconShape s) {
    iconShape = s;
    _prefs?.setInt('shape', s.index);
    notifyListeners();
  }

  void setAmoled(bool v) {
    amoledMode = v;
    _prefs?.setBool('amoled', v);
    notifyListeners();
  }

  void setGlass(bool v) {
    glassEffect = v;
    _prefs?.setBool('glass', v);
    notifyListeners();
  }

  void setDynamicColor(bool v) {
    dynamicWallpaperColor = v;
    _prefs?.setBool('dyn', v);
    notifyListeners();
  }

  void setSeed(int i) {
    seedIndex = i;
    dynamicWallpaperColor = false;
    _prefs?.setInt('seed', i);
    _prefs?.setBool('dyn', false);
    notifyListeners();
  }

  void setGridSize(int cols, int rows) {
    gridCols = cols;
    gridRows = rows;
    _prefs?.setInt('cols', cols);
    _prefs?.setInt('rows', rows);
    notifyListeners();
  }

  void setShowLabels(bool v) {
    showLabels = v;
    _prefs?.setBool('labels', v);
    notifyListeners();
  }

  Future<void> launch(String pkg) async {
    HapticFeedback.lightImpact();
    await _ch.invokeMethod('launchApp', {'pkg': pkg});
  }

  Future<void> openAppInfo(String pkg) async {
    await _ch.invokeMethod('appInfo', {'pkg': pkg});
  }

  Future<void> uninstall(String pkg) async {
    await _ch.invokeMethod('uninstallApp', {'pkg': pkg});
    Future.delayed(const Duration(seconds: 3), refreshApps);
  }

  Future<void> openHomeSettings() async {
    await _ch.invokeMethod('openDefaultSettings');
  }

  Future<void> pickWallpaper() async {
    await _ch.invokeMethod('pickWallpaper');
  }

  Future<void> searchWeb(String query) async {
    final url =
        'https://www.google.com/search?q=${Uri.encodeComponent(query.trim())}';
    await _ch.invokeMethod('openUrl', {'url': url});
  }
}

final LauncherState state = LauncherState();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 1000;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 250 << 20;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await state.init();
  runApp(const CaesiumLauncherApp());
}

class CaesiumLauncherApp extends StatelessWidget {
  const CaesiumLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return DynamicColorBuilder(
          builder: (lightDyn, darkDyn) {
            final seed = (state.dynamicWallpaperColor && darkDyn != null)
                ? darkDyn.primary
                : seedOptions[state.seedIndex].color;
            final scheme = ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            );
            return MaterialApp(
              title: 'Caesium Launcher',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: scheme,
                scaffoldBackgroundColor: Colors.transparent,
              ),
              home: const LauncherShell(),
            );
          },
        );
      },
    );
  }
}

class AppIconTile extends StatelessWidget {
  final AppItem app;
  final IconShape shape;
  final bool showLabel;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const AppIconTile({
    super.key,
    required this.app,
    required this.shape,
    required this.showLabel,
    required this.size,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PhysicalShape(
              clipper: ShapeBorderClipper(shape: buildIconShape(shape, size)),
              clipBehavior: Clip.antiAlias,
              color: Colors.transparent,
              child: SizedBox(
                width: size,
                height: size,
                child: Image(
                  image: app.provider,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ),
            if (showLabel) ...[
              const SizedBox(height: 6),
              Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LauncherShell extends StatefulWidget {
  const LauncherShell({super.key});

  @override
  State<LauncherShell> createState() => _LauncherShellState();
}

class _LauncherShellState extends State<LauncherShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _drawerCtrl;
  late final Animation<Offset> _drawerOffset;

  final ScrollController _gridScrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  late Timer _clockTimer;
  DateTime _now = DateTime.now();
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _drawerOffset = Tween<Offset>(
      begin: const Offset(0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _drawerCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    state.addListener(_precacheIconsIfNeeded);
  }

  void _precacheIconsIfNeeded() {
    if (!_precached && state.apps.isNotEmpty && mounted) {
      _precached = true;
      for (final a in state.apps) {
        precacheImage(a.provider, context);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheIconsIfNeeded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(_precacheIconsIfNeeded);
    _clockTimer.cancel();
    _drawerCtrl.dispose();
    _gridScrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      state.refreshApps();
      if (mounted) setState(() => _now = DateTime.now());
    }
  }

  void _openDrawer() {
    HapticFeedback.selectionClick();
    _drawerCtrl.forward();
  }

  void _closeDrawer() {
    FocusScope.of(context).unfocus();
    _drawerCtrl.reverse();
  }

  void _onVerticalDragUpdate(DragUpdateDetails d, double height) {
    _drawerCtrl.value -= d.primaryDelta! / height;
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0.0;
    if (v < -200) {
      _drawerCtrl.forward();
    } else if (v > 200) {
      _closeDrawer();
    } else if (_drawerCtrl.value > 0.35) {
      _drawerCtrl.forward();
    } else {
      _closeDrawer();
    }
  }

  void _showAppMenu(AppItem app) {
    HapticFeedback.mediumImpact();
    final inDock = state.dockPkgs.contains(app.pkg);
    final inHome = state.homeSlots.containsValue(app.pkg);
    final currentCat = state.getAppCategory(app.pkg);
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surfaceContainerHighest,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: PhysicalShape(
                    clipper: ShapeBorderClipper(
                        shape: buildIconShape(state.iconShape, 44)),
                    clipBehavior: Clip.antiAlias,
                    color: Colors.transparent,
                    child: Image(image: app.provider, width: 44, height: 44),
                  ),
                  title: Text(
                    app.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: cs.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Category: $currentCat',
                    style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const Divider(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Move to Category:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final catName in state.categories.keys)
                      ActionChip(
                        label: Text(catName),
                        backgroundColor: currentCat == catName ? cs.primaryContainer : const Color(0xFF1E1E24),
                        labelStyle: TextStyle(color: currentCat == catName ? cs.onPrimaryContainer : Colors.white, fontSize: 12),
                        onPressed: () {
                          state.assignCategory(app.pkg, catName);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
                const Divider(height: 24),
                ListTile(
                  leading: Icon(
                    inHome ? Icons.star_rounded : Icons.star_border_rounded,
                    color: cs.primary,
                  ),
                  title: Text(
                    inHome ? 'Remove from Home Screen' : 'Pin to Home Screen',
                    style: TextStyle(color: cs.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (inHome) {
                      state.removeFromHome(app.pkg);
                    } else {
                      state.addOrMoveToHome(app.pkg);
                    }
                  },
                ),
                ListTile(
                  leading: Icon(
                    inDock
                        ? Icons.remove_circle_outline_rounded
                        : Icons.dock_rounded,
                    color: cs.primary,
                  ),
                  title: Text(
                    inDock ? 'Remove from Bottom Dock' : 'Pin to Bottom Dock',
                    style: TextStyle(color: cs.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    state.toggleDock(app.pkg);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.info_outline_rounded,
                      color: cs.onSurfaceVariant),
                  title: Text('App Info',
                      style: TextStyle(color: cs.onSurface)),
                  onTap: () {
                    Navigator.pop(ctx);
                    state.openAppInfo(app.pkg);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFFF5252)),
                  title: const Text('Uninstall App',
                      style: TextStyle(color: Color(0xFFFF5252))),
                  onTap: () {
                    Navigator.pop(ctx);
                    state.uninstall(app.pkg);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openLauncherSettings() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141418),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const LauncherSettingsSheet(),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDate(DateTime dt) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final d = days[(dt.weekday - 1).clamp(0, 6)];
    final m = months[(dt.month - 1).clamp(0, 11)];
    return '$d, $m ${dt.day}';
  }

  Widget _buildGlassBox({
    required Widget child,
    double radius = 32,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: state.amoledMode
            ? const Color(0xFF121216)
            : Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildHomePage(BuildContext context, double screenHeight) {
    final cs = Theme.of(context).colorScheme;
    final dockApps = state.dockApps;
    final totalSlots = state.gridCols * state.gridRows;
    final appMap = {for (final a in state.apps) a.pkg: a};

    return GestureDetector(
      onLongPress: _openLauncherSettings,
      onVerticalDragUpdate: (d) => _onVerticalDragUpdate(d, screenHeight),
      onVerticalDragEnd: _onVerticalDragEnd,
      behavior: HitTestBehavior.translucent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _buildGlassBox(
                      radius: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatDate(_now).toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _formatTime(_now),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1,
                                ),
                              ),
                            ],
                          ),
                          const Icon(Icons.cloud_queue_rounded, color: Colors.white70, size: 34),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  IconButton(
                    onPressed: _openLauncherSettings,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.35),
                      padding: const EdgeInsets.all(16),
                    ),
                    icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 22),
                    tooltip: 'Settings',
                  ),
                ],
              ),
              const Spacer(),

              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: state.gridCols,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 18,
                  childAspectRatio: 0.78,
                ),
                itemCount: totalSlots,
                itemBuilder: (ctx, slotIndex) {
                  final pkg = state.homeSlots[slotIndex];
                  final app = pkg != null ? appMap[pkg] : null;

                  return DragTarget<int>(
                    onWillAcceptWithDetails: (details) => true,
                    onAcceptWithDetails: (details) {
                      HapticFeedback.mediumImpact();
                      state.moveHomeSlot(details.data, slotIndex);
                    },
                    builder: (context, candidateData, rejectedData) {
                      if (app == null) {
                        return Container(
                          decoration: BoxDecoration(
                            color: candidateData.isNotEmpty
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                            border: candidateData.isNotEmpty
                                ? Border.all(color: cs.primary, width: 2)
                                : null,
                          ),
                        );
                      }
                      return LongPressDraggable<int>(
                        data: slotIndex,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Opacity(
                            opacity: 0.9,
                            child: AppIconTile(
                              app: app,
                              shape: state.iconShape,
                              showLabel: state.showLabels,
                              size: 62,
                              onTap: () {},
                              onLongPress: () {},
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.25,
                          child: AppIconTile(
                            app: app,
                            shape: state.iconShape,
                            showLabel: state.showLabels,
                            size: 60,
                            onTap: () {},
                            onLongPress: () {},
                          ),
                        ),
                        child: AppIconTile(
                          app: app,
                          shape: state.iconShape,
                          showLabel: state.showLabels,
                          size: 60,
                          onTap: () => state.launch(app.pkg),
                          onLongPress: () => _showAppMenu(app),
                        ),
                      );
                    },
                  );
                },
              ),

              _buildGlassBox(
                radius: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final app in dockApps)
                      AppIconTile(
                        app: app,
                        shape: state.iconShape,
                        showLabel: false,
                        size: 58,
                        onTap: () => state.launch(app.pkg),
                        onLongPress: () => _showAppMenu(app),
                      ),
                    if (dockApps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'Pin apps to dock',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppDrawer(BuildContext context, double screenHeight) {
    final cs = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final appMap = {for (final a in state.apps) a.pkg: a};
    final isSearching = q.isNotEmpty;
    final searchFiltered = state.apps.where((a) {
      return a.name.toLowerCase().contains(q) || a.pkg.toLowerCase().contains(q);
    }).toList();

    return Container(
      color: state.amoledMode ? Colors.black : const Color(0xFF101014),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is OverscrollNotification &&
                            n.overscroll < -8 &&
                            _gridScrollCtrl.offset <= 0) {
                          _closeDrawer();
                          return true;
                        }
                        return false;
                      },
                      child: ListView(
                        controller: _gridScrollCtrl,
                        physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics()),
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                        children: [
                          if (isSearching) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text('Search Results (${searchFiltered.length})',
                                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: state.gridCols,
                                mainAxisSpacing: 18,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.78,
                              ),
                              itemCount: searchFiltered.length,
                              itemBuilder: (ctx, i) {
                                final app = searchFiltered[i];
                                return AppIconTile(
                                  key: ValueKey(app.pkg),
                                  app: app,
                                  shape: state.iconShape,
                                  showLabel: state.showLabels,
                                  size: 56,
                                  onTap: () => state.launch(app.pkg),
                                  onLongPress: () => _showAppMenu(app),
                                );
                              },
                            ),
                          ] else ...[
                            for (final entry in state.categories.entries)
                              if (entry.value.isNotEmpty) ...[
                                Container(
                                  margin: const EdgeInsets.only(bottom: 20),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF18181E),
                                    borderRadius: BorderRadius.circular(26),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.folder_rounded, color: cs.primary, size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            entry.key,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${entry.value.length}',
                                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      GridView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: state.gridCols,
                                          mainAxisSpacing: 16,
                                          crossAxisSpacing: 12,
                                          childAspectRatio: 0.78,
                                        ),
                                        itemCount: entry.value.length,
                                        itemBuilder: (ctx, idx) {
                                          final pkg = entry.value[idx];
                                          final app = appMap[pkg];
                                          if (app == null) return const SizedBox.shrink();
                                          return AppIconTile(
                                            key: ValueKey(app.pkg),
                                            app: app,
                                            shape: state.iconShape,
                                            showLabel: state.showLabels,
                                            size: 54,
                                            onTap: () => state.launch(app.pkg),
                                            onLongPress: () => _showAppMenu(app),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                          ],
                        ],
                      ),
                    ),
            ),

            if (isSearching && searchFiltered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: FilledButton.icon(
                  onPressed: () => state.searchWeb(_query),
                  icon: const Icon(Icons.travel_explore_rounded),
                  label: Text('Search Google for "$_query"'),
                ),
              ),

            GestureDetector(
              onVerticalDragUpdate: (d) =>
                  _onVerticalDragUpdate(d, screenHeight),
              onVerticalDragEnd: _onVerticalDragEnd,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A20),
                  border: Border(
                      top: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white, size: 30),
                      tooltip: 'Back to Home',
                      onPressed: _closeDrawer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _query = v),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText:
                              'Search ${state.apps.length} apps in categories...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon:
                              Icon(Icons.search_rounded, color: cs.primary),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Colors.white70),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFF141418),
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (v) {
                          if (searchFiltered.isNotEmpty) {
                            state.launch(searchFiltered.first.pkg);
                          } else if (v.trim().isNotEmpty) {
                            state.searchWeb(v);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (_drawerCtrl.value > 0.1) {
          _closeDrawer();
        }
      },
      child: Scaffold(
        backgroundColor: state.amoledMode ? Colors.black : Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: _buildHomePage(context, h),
            ),
            SlideTransition(
              position: _drawerOffset,
              child: RepaintBoundary(
                child: _buildAppDrawer(context, h),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LauncherSettingsSheet extends StatelessWidget {
  const LauncherSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (ctx, scrollCtrl) {
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primaryContainer, cs.tertiaryContainer],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: cs.primary,
                        child: Icon(Icons.phone_iphone_rounded,
                            color: cs.onPrimary, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Caesium Launcher',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            Text(
                              'Made by Alex Desrosier • 120Hz Enforced',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onPrimaryContainer
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                const Text(
                  'Home Screen Grid Size',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => state.setGridSize(4, 4),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              state.gridCols == 4 && state.gridRows == 4
                                  ? cs.primaryContainer
                                  : const Color(0xFF1E1E24),
                        ),
                        child: const Text('4 x 4'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => state.setGridSize(4, 5),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              state.gridCols == 4 && state.gridRows == 5
                                  ? cs.primaryContainer
                                  : const Color(0xFF1E1E24),
                        ),
                        child: const Text('4 x 5'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => state.setGridSize(5, 5),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              state.gridCols == 5 && state.gridRows == 5
                                  ? cs.primaryContainer
                                  : const Color(0xFF1E1E24),
                        ),
                        child: const Text('5 x 5'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => state.setGridSize(5, 6),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              state.gridCols == 5 && state.gridRows == 6
                                  ? cs.primaryContainer
                                  : const Color(0xFF1E1E24),
                        ),
                        child: const Text('5 x 6'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),
                const Text(
                  'App Icon Shape',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.25,
                  children: [
                    for (final s in IconShape.values)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          state.setIconShape(s);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: state.iconShape == s
                                ? cs.primaryContainer
                                : const Color(0xFF1E1E24),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: state.iconShape == s
                                  ? cs.primary
                                  : Colors.white12,
                              width: state.iconShape == s ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              PhysicalShape(
                                clipper: ShapeBorderClipper(
                                    shape: buildIconShape(s, 36)),
                                color: state.iconShape == s
                                    ? cs.primary
                                    : Colors.white38,
                                child: const SizedBox(width: 36, height: 36),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                shapeNames[s] ?? '',
                                style: TextStyle(
                                  color: state.iconShape == s
                                      ? cs.onPrimaryContainer
                                      : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: state.iconShape == s
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: state.openHomeSettings,
                  icon: const Icon(Icons.home_filled),
                  label: const Text('Set as Default System Launcher'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: state.pickWallpaper,
                  icon: const Icon(Icons.wallpaper_rounded),
                  label: const Text('Change System Wallpaper'),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Appearance & Backdrop',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: state.amoledMode,
                  onChanged: state.setAmoled,
                  title: const Text('Pure AMOLED Black (#000000)',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Replaces live system wallpaper with pitch black',
                      style: TextStyle(color: Colors.white60)),
                ),
                SwitchListTile.adaptive(
                  value: state.showLabels,
                  onChanged: state.setShowLabels,
                  title: const Text('Show App Icon Labels',
                      style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Accent Color',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (int i = 0; i < seedOptions.length; i++)
                      GestureDetector(
                        onTap: () => state.setSeed(i),
                        child: Chip(
                          avatar: CircleAvatar(
                            backgroundColor: seedOptions[i].color,
                          ),
                          label: Text(seedOptions[i].name),
                          backgroundColor: state.seedIndex == i
                              ? cs.primaryContainer
                              : const Color(0xFF1E1E22),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
