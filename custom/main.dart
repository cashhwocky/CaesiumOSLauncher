// FILE: custom/main.dart
import 'dart:async';
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

class AppItem {
  final String name;
  final String pkg;
  final Uint8List icon;
  const AppItem({required this.name, required this.pkg, required this.icon});
}

class LauncherState extends ChangeNotifier {
  static const MethodChannel _ch = MethodChannel('pixellauncher/native');
  SharedPreferences? _prefs;

  List<AppItem> apps = [];
  List<String> dockPkgs = [];
  List<String> homePkgs = [];
  bool loading = true;

  bool amoledMode = false;
  bool glassEffect = true;
  bool dynamicWallpaperColor = true;
  int seedIndex = 0;
  int gridCols = 4;
  bool showLabels = true;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    amoledMode = _prefs?.getBool('amoled') ?? false;
    glassEffect = _prefs?.getBool('glass') ?? true;
    dynamicWallpaperColor = _prefs?.getBool('dyn') ?? true;
    seedIndex = (_prefs?.getInt('seed') ?? 0).clamp(0, seedOptions.length - 1);
    gridCols = (_prefs?.getInt('cols') ?? 4).clamp(4, 5);
    showLabels = _prefs?.getBool('labels') ?? true;
    dockPkgs = _prefs?.getStringList('dock') ?? [];
    homePkgs = _prefs?.getStringList('home') ?? [];
    notifyListeners();
    await refreshApps();
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

        // Auto-populate dock and home favorites on first launch
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

        if (homePkgs.isEmpty && apps.isNotEmpty) {
          final favs = <String>[];
          for (final a in apps) {
            if (!dockPkgs.contains(a.pkg)) favs.add(a.pkg);
            if (favs.length >= 8) break;
          }
          homePkgs = favs;
          _prefs?.setStringList('home', homePkgs);
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

  List<AppItem> get homeApps {
    final map = {for (final a in apps) a.pkg: a};
    return [
      for (final p in homePkgs)
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

  void toggleHome(String pkg) {
    if (homePkgs.contains(pkg)) {
      homePkgs.remove(pkg);
    } else {
      if (homePkgs.length >= 12) homePkgs.removeLast();
      homePkgs.add(pkg);
    }
    _prefs?.setStringList('home', homePkgs);
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

  void setCols(int c) {
    gridCols = c;
    _prefs?.setInt('cols', c);
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
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await state.init();
  runApp(const PixelLauncherApp());
}

class PixelLauncherApp extends StatelessWidget {
  const PixelLauncherApp({super.key});

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
              title: 'Pixel Launcher',
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

class LauncherShell extends StatefulWidget {
  const LauncherShell({super.key});

  @override
  State<LauncherShell> createState() => _LauncherShellState();
}

class _LauncherShellState extends State<LauncherShell>
    with WidgetsBindingObserver {
  final PageController _pageCtrl = PageController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer.cancel();
    _pageCtrl.dispose();
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
    _pageCtrl.animateToPage(
      1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _closeDrawer() {
    FocusScope.of(context).unfocus();
    _pageCtrl.animateToPage(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _showAppMenu(AppItem app) {
    HapticFeedback.mediumImpact();
    final inDock = state.dockPkgs.contains(app.pkg);
    final inHome = state.homePkgs.contains(app.pkg);
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161618),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(app.icon, width: 44, height: 44),
                  ),
                  title: Text(
                    app.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    app.pkg,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                const Divider(color: Colors.white12),
                ListTile(
                  leading: Icon(
                    inHome ? Icons.Star_rounded : Icons.star_border_rounded,
                    color: cs.primary,
                  ),
                  title: Text(
                    inHome ? 'Remove from Home Screen' : 'Pin to Home Screen',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    state.toggleHome(app.pkg);
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
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    state.toggleDock(app.pkg);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded,
                      color: Colors.white70),
                  title: const Text('App Info',
                      style: TextStyle(color: Colors.white)),
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
      backgroundColor: const Color(0xFF121214),
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
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final d = days[(dt.weekday - 1).clamp(0, 6)];
    final m = months[(dt.month - 1).clamp(0, 11)];
    return '$d, $m ${dt.day}';
  }

  Widget _buildGlassBox({
    required Widget child,
    double radius = 28,
    EdgeInsets padding = const EdgeInsets.all(12),
    Color? tint,
  }) {
    final baseColor = tint ??
        (state.amoledMode
            ? const Color(0xFF141416)
            : Colors.black.withValues(alpha: 0.42));
    if (!state.glassEffect || state.amoledMode) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildAppIcon(AppItem app, {bool showLabel = true, double size = 56}) {
    return GestureDetector(
      onTap: () => state.launch(app.pkg),
      onLongPress: () => _showAppMenu(app),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.28),
              child: Image.memory(
                app.icon,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
          if (showLabel && state.showLabels) ...[
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
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 6),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHomePage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final homeApps = state.homeApps;
    final dockApps = state.dockApps;

    return GestureDetector(
      onLongPress: _openLauncherSettings,
      behavior: HitTestBehavior.translucent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pixel "At a Glance" Clock & Weather/System Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(_now),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 8)
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatTime(_now),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 64,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                            letterSpacing: -2,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 14)
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _openLauncherSettings,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.35),
                    ),
                    icon: const Icon(Icons.tune_rounded, color: Colors.white),
                    tooltip: 'Launcher Settings',
                  ),
                ],
              ),

              const Spacer(),

              // Pinned Home Favorites Grid
              if (homeApps.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 20),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: state.gridCols,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: homeApps.length,
                  itemBuilder: (ctx, i) => _buildAppIcon(homeApps[i]),
                ),

              // Universal Search Pill
              GestureDetector(
                onTap: _openDrawer,
                child: _buildGlassBox(
                  radius: 32,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: cs.primary, size: 24),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Search apps or web...',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _openDrawer,
                        child: Icon(Icons.apps_rounded,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 22),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Frosted Bottom Dock
              _buildGlassBox(
                radius: 34,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final app in dockApps)
                      _buildAppIcon(app, showLabel: false, size: 54),
                    if (dockApps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'Long-press any app in drawer to pin to dock',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 6),
              Center(
                child: GestureDetector(
                  onTap: _openDrawer,
                  child: Column(
                    children: [
                      Icon(Icons.keyboard_arrow_up_rounded,
                          color: Colors.white.withValues(alpha: 0.7), size: 22),
                      Text(
                        'Swipe up for all apps (${state.apps.length})',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppDrawer(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final filtered = state.apps.where((a) {
      if (q.isEmpty) return true;
      return a.name.toLowerCase().contains(q) ||
          a.pkg.toLowerCase().contains(q);
    }).toList();

    return Container(
      color: state.amoledMode
          ? Colors.black
          : Colors.black.withValues(alpha: 0.82),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white, size: 30),
                    onPressed: _closeDrawer,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search ${state.apps.length} installed apps...',
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
                        fillColor: const Color(0xFF1E1E22),
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (v) {
                        if (filtered.isNotEmpty) {
                          state.launch(filtered.first.pkg);
                        } else if (v.trim().isNotEmpty) {
                          state.searchWeb(v);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_query.trim().isNotEmpty && filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: FilledButton.icon(
                  onPressed: () => state.searchWeb(_query),
                  icon: const Icon(Icons.travel_explore_rounded),
                  label: Text('Search Google for "$_query"'),
                ),
              ),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: state.gridCols,
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => _buildAppIcon(filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (_pageCtrl.hasClients && (_pageCtrl.page ?? 0) > 0.5) {
          _closeDrawer();
        }
      },
      child: Scaffold(
        backgroundColor: state.amoledMode ? Colors.black : Colors.transparent,
        body: PageView(
          controller: _pageCtrl,
          scrollDirection: Axis.vertical,
          children: [
            _buildHomePage(context),
            _buildAppDrawer(context),
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
          initialChildSize: 0.72,
          maxChildSize: 0.92,
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
                        child: Icon(Icons.rocket_launch_rounded,
                            color: cs.onPrimary, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pixel Launcher',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            Text(
                              'Made by Alex Desrosier • Custom AOSP Build',
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
                const SizedBox(height: 16),
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
                  value: state.glassEffect,
                  onChanged: state.setGlass,
                  title: const Text('Liquid Glass Blur Dock',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Frosted translucent dock and search bar',
                      style: TextStyle(color: Colors.white60)),
                ),
                SwitchListTile.adaptive(
                  value: state.showLabels,
                  onChanged: state.setShowLabels,
                  title: const Text('Show App Icon Labels',
                      style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Grid Columns',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 4, label: Text('4 Columns')),
                    ButtonSegment(value: 5, label: Text('5 Columns')),
                  ],
                  selected: {state.gridCols},
                  onSelectionChanged: (s) => state.setCols(s.first),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Pixel 10 Accent Color',
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
