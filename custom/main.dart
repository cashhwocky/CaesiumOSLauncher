import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  runApp(const CaesiumLauncherApp());
}

class AppModel {
  final String name;
  final String pkg;
  final Uint8List iconBytes;
  final MemoryImage imageProvider;
  final String category;
  final int installTime;

  AppModel({
    required this.name,
    required this.pkg,
    required this.iconBytes,
    required this.category,
    required this.installTime,
  }) : imageProvider = MemoryImage(iconBytes);

  // Installed within the last 48 hours
  bool get isNew {
    if (installTime <= 0) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const fortyEightHoursMs = 48 * 60 * 60 * 1000;
    return (nowMs - installTime) < fortyEightHoursMs;
  }

  static String categorize(String name, String pkg) {
    final lowerPkg = pkg.toLowerCase();
    final lowerName = name.toLowerCase();
    if (lowerPkg.contains('social') ||
        lowerPkg.contains('discord') ||
        lowerPkg.contains('telegram') ||
        lowerPkg.contains('snapchat') ||
        lowerPkg.contains('instagram') ||
        lowerPkg.contains('whatsapp') ||
        lowerPkg.contains('messaging') ||
        lowerPkg.contains('dialer')) {
      return 'Social & Comm';
    }
    if (lowerPkg.contains('music') ||
        lowerPkg.contains('audio') ||
        lowerPkg.contains('spotify') ||
        lowerPkg.contains('youtube') ||
        lowerPkg.contains('video') ||
        lowerPkg.contains('camera') ||
        lowerPkg.contains('gallery') ||
        lowerPkg.contains('photos')) {
      return 'Media';
    }
    if (lowerPkg.contains('game') ||
        lowerPkg.contains('minecraft') ||
        lowerPkg.contains('fortnite') ||
        lowerPkg.contains('roblox')) {
      return 'Games';
    }
    if (lowerPkg.contains('settings') ||
        lowerPkg.contains('system') ||
        lowerPkg.contains('android') ||
        lowerPkg.contains('google') ||
        lowerPkg.contains('calculator') ||
        lowerPkg.contains('clock') ||
        lowerPkg.contains('files') ||
        lowerName.contains('caesium')) {
      return 'System & Tools';
    }
    return 'Other Apps';
  }
}

class CaesiumLauncherApp extends StatelessWidget {
  const CaesiumLauncherApp({super.key});

  static final _defaultLightScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4F6373),
    brightness: Brightness.light,
  );

  static final _defaultDarkScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8AB4F8),
    brightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightScheme = lightDynamic?.harmonized() ?? _defaultLightScheme;
        final darkScheme = darkDynamic?.harmonized() ?? _defaultDarkScheme;

        return MaterialApp(
          title: 'Caesium Launcher',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: lightScheme,
            scaffoldBackgroundColor: Colors.transparent,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkScheme,
            scaffoldBackgroundColor: Colors.transparent,
          ),
          home: const LauncherHome(),
        );
      },
    );
  }
}

class LauncherHome extends StatefulWidget {
  const LauncherHome({super.key});

  @override
  State<LauncherHome> createState() => _LauncherHomeState();
}

class _LauncherHomeState extends State<LauncherHome>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _channel = MethodChannel('caesiumlauncher/native');

  List<AppModel> _allApps = [];
  List<AppModel> _filteredApps = [];
  List<AppModel> _recentApps = [];
  List<String> _dockPackages = [];
  List<String> _homeGridPackages = [];
  Set<String> _dismissedNewApps = {};

  bool _isLoading = true;
  bool _categorizedMode = false;
  bool _themedIcons = false;
  bool _showRecentShelf = true;
  int _gridColumns = 4;
  String _iconShape = 'circle';

  late AnimationController _drawerController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _drawerScrollController = ScrollController();

  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _drawerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    // Listen for live app installs or uninstalls from Kotlin BroadcastReceiver
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPackagesChanged') {
        final String? action = call.arguments?['action'];
        final String? pkg = call.arguments?['pkg'];
        await _fetchApps();
        if (mounted && action == 'ADDED' && pkg != null) {
          final addedApp = _allApps.where((a) => a.pkg == pkg).firstOrNull;
          if (addedApp != null) {
            // Automatically pin new app to home screen if there's space (< 16 apps)
            if (!_homeGridPackages.contains(pkg) &&
                _homeGridPackages.length < 16) {
              setState(() => _homeGridPackages.add(pkg));
              _savePreferences();
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                content: Row(
                  children: [
                    const Icon(Icons.download_done_rounded,
                        color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text('New app installed: ${addedApp.name}')),
                  ],
                ),
                action: SnackBarAction(
                  label: 'OPEN',
                  onPressed: () => _launchApp(addedApp.pkg),
                ),
              ),
            );
          }
        }
      }
    });

    _loadPreferences();
    _fetchApps();
  }

  @override
  void dispose() {
    _drawerController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _drawerScrollController.dispose();
    _clockTimer.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dockPackages = prefs.getStringList('dock_pkgs') ?? [];
      _homeGridPackages = prefs.getStringList('home_grid_pkgs') ?? [];
      _dismissedNewApps =
          (prefs.getStringList('dismissed_new_pkgs') ?? []).toSet();
      _categorizedMode = prefs.getBool('categorized_mode') ?? false;
      _themedIcons = prefs.getBool('themed_icons') ?? false;
      _showRecentShelf = prefs.getBool('show_recent_shelf') ?? true;
      _gridColumns = prefs.getInt('grid_columns') ?? 4;
      _iconShape = prefs.getString('icon_shape') ?? 'circle';
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dock_pkgs', _dockPackages);
    await prefs.setStringList('home_grid_pkgs', _homeGridPackages);
    await prefs.setStringList(
        'dismissed_new_pkgs', _dismissedNewApps.toList());
    await prefs.setBool('categorized_mode', _categorizedMode);
    await prefs.setBool('themed_icons', _themedIcons);
    await prefs.setBool('show_recent_shelf', _showRecentShelf);
    await prefs.setInt('grid_columns', _gridColumns);
    await prefs.setString('icon_shape', _iconShape);
  }

  Future<void> _fetchApps() async {
    try {
      final List<dynamic>? rawApps = await _channel.invokeMethod('getApps');
      if (rawApps != null) {
        final List<AppModel> parsed = [];
        for (final item in rawApps) {
          final map = Map<String, dynamic>.from(item);
          final String name = map['name'] ?? 'App';
          final String pkg = map['pkg'] ?? '';
          final int installTime = (map['installTime'] as num?)?.toInt() ?? 0;
          final Uint8List icon = map['icon'] is Uint8List
              ? map['icon']
              : Uint8List.fromList(List<int>.from(map['icon']));

          final model = AppModel(
            name: name,
            pkg: pkg,
            iconBytes: icon,
            category: AppModel.categorize(name, pkg),
            installTime: installTime,
          );
          parsed.add(model);
        }

        if (mounted) {
          for (final app in parsed) {
            precacheImage(app.imageProvider, context);
          }

          // Compute Recently Installed Apps (sorted newest first, max 8)
          final recent = parsed
              .where((a) => a.isNew && !_dismissedNewApps.contains(a.pkg))
              .toList()
            ..sort((a, b) => b.installTime.compareTo(a.installTime));

          setState(() {
            _allApps = parsed;
            _filteredApps = parsed;
            _recentApps = recent.take(8).toList();
            _isLoading = false;

            if (_dockPackages.isEmpty && parsed.isNotEmpty) {
              _dockPackages = parsed.take(4).map((e) => e.pkg).toList();
            }
            if (_homeGridPackages.isEmpty && parsed.length > 4) {
              _homeGridPackages =
                  parsed.skip(4).take(8).map((e) => e.pkg).toList();
            }
          });
          _savePreferences();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterApps(String query) {
    if (query.trim().isEmpty) {
      setState(() => _filteredApps = _allApps);
    } else {
      final q = query.toLowerCase();
      setState(() {
        _filteredApps = _allApps
            .where((a) =>
                a.name.toLowerCase().contains(q) ||
                a.pkg.toLowerCase().contains(q))
            .toList();
      });
    }
  }

  void _openDrawer() {
    HapticFeedback.lightImpact();
    _drawerController.fling(velocity: 2.2);
  }

  void _closeDrawer() {
    _searchFocus.unfocus();
    _searchController.clear();
    _filterApps('');
    if (_drawerScrollController.hasClients) {
      _drawerScrollController.jumpTo(0);
    }
    _drawerController.fling(velocity: -2.2);
  }

  Future<void> _launchApp(String pkg) async {
    HapticFeedback.selectionClick();
    // Launching a new app clears its "NEW" badge after first launch if desired
    await _channel.invokeMethod('launchApp', {'pkg': pkg});
  }

  ShapeBorder _getShapeBorder() {
    switch (_iconShape) {
      case 'squircle':
        return ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(34));
      case 'rounded':
        return RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
      case 'teardrop':
        return const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(8),
          ),
        );
      case 'circle':
      default:
        return const CircleBorder();
    }
  }

  Widget _buildAppIcon(AppModel app,
      {double size = 58, bool showLabel = true, Color? textColor}) {
    final cs = Theme.of(context).colorScheme;
    final bool showNewBadge =
        app.isNew && !_dismissedNewApps.contains(app.pkg);

    return GestureDetector(
      onTap: () => _launchApp(app.pkg),
      onLongPress: () => _showAppOptionsSheet(app),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: ShapeDecoration(
                  shape: _getShapeBorder(),
                  color: _themedIcons
                      ? cs.secondaryContainer
                      : cs.surfaceContainerHighest.withOpacity(0.35),
                  shadows: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: ColorFiltered(
                  colorFilter: _themedIcons
                      ? ColorFilter.mode(
                          cs.onSecondaryContainer, BlendMode.modulate)
                      : const ColorFilter.mode(
                          Colors.transparent, BlendMode.dst),
                  child: Image(
                    image: app.imageProvider,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              if (showNewBadge)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cs.surface, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        )
                      ],
                    ),
                    child: Text(
                      'NEW',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (showLabel) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: textColor ?? Colors.white,
                  shadows: textColor == null
                      ? const [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          )
                        ]
                      : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAppOptionsSheet(AppModel app) {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
    final isPinnedHome = _homeGridPackages.contains(app.pkg);
    final isPinnedDock = _dockPackages.contains(app.pkg);
    final hasNewBadge = app.isNew && !_dismissedNewApps.contains(app.pkg);

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildAppIcon(app, size: 48, showLabel: false),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            app.pkg,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                if (hasNewBadge)
                  ListTile(
                    leading: Icon(Icons.auto_awesome_outlined,
                        color: cs.tertiary),
                    title: const Text('Dismiss "NEW" Badge'),
                    onTap: () {
                      setState(() {
                        _dismissedNewApps.add(app.pkg);
                        _recentApps.removeWhere((a) => a.pkg == app.pkg);
                      });
                      _savePreferences();
                      Navigator.pop(ctx);
                    },
                  ),
                ListTile(
                  leading: Icon(
                    isPinnedHome
                        ? Icons.remove_circle_outline
                        : Icons.add_to_home_screen_rounded,
                    color: cs.primary,
                  ),
                  title: Text(isPinnedHome
                      ? 'Remove from Home Screen'
                      : 'Add to Home Screen'),
                  onTap: () {
                    setState(() {
                      if (isPinnedHome) {
                        _homeGridPackages.remove(app.pkg);
                      } else {
                        _homeGridPackages.add(app.pkg);
                      }
                    });
                    _savePreferences();
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: Icon(
                    isPinnedDock ? Icons.dock_outlined : Icons.dock_rounded,
                    color: cs.primary,
                  ),
                  title: Text(
                      isPinnedDock ? 'Remove from Dock' : 'Pin to Dock (Max 5)'),
                  onTap: () {
                    setState(() {
                      if (isPinnedDock) {
                        _dockPackages.remove(app.pkg);
                      } else if (_dockPackages.length < 5) {
                        _dockPackages.add(app.pkg);
                      }
                    });
                    _savePreferences();
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: cs.secondary),
                  title: const Text('App Info'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _channel.invokeMethod('appInfo', {'pkg': app.pkg});
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                  title: const Text('Uninstall'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _channel.invokeMethod('uninstallApp', {'pkg': app.pkg});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLauncherSettings() {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Caesium Settings',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Icon Shape',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final shape in [
                          ('circle', 'Circle'),
                          ('squircle', 'Squircle'),
                          ('rounded', 'Rounded'),
                          ('teardrop', 'Teardrop'),
                        ])
                          ChoiceChip(
                            label: Text(shape.$2),
                            selected: _iconShape == shape.$1,
                            onSelected: (_) {
                              setState(() => _iconShape = shape.$1);
                              setSheetState(() {});
                              _savePreferences();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show Recently Installed'),
                      subtitle: const Text(
                          'Highlight newly downloaded apps (last 48h)'),
                      value: _showRecentShelf,
                      onChanged: (val) {
                        setState(() => _showRecentShelf = val);
                        setSheetState(() {});
                        _savePreferences();
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Material You Themed Icons'),
                      subtitle:
                          const Text('Tint icons with dynamic wallpaper colors'),
                      value: _themedIcons,
                      onChanged: (val) {
                        setState(() => _themedIcons = val);
                        setSheetState(() {});
                        _savePreferences();
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Categorized App Drawer'),
                      subtitle: const Text('Group apps into smart folders'),
                      value: _categorizedMode,
                      onChanged: (val) {
                        setState(() => _categorizedMode = val);
                        setSheetState(() {});
                        _savePreferences();
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Grid Columns'),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 4, label: Text('4x')),
                            ButtonSegment(value: 5, label: Text('5x')),
                          ],
                          selected: {_gridColumns},
                          onSelectionChanged: (s) {
                            setState(() => _gridColumns = s.first);
                            setSheetState(() {});
                            _savePreferences();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _channel.invokeMethod('pickWallpaper');
                            },
                            icon: const Icon(Icons.wallpaper_rounded),
                            label: const Text('Wallpaper'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _channel.invokeMethod('openDefaultSettings');
                            },
                            icon: const Icon(Icons.home_outlined),
                            label: const Text('Default Home'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formattedDate() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final d = days[_now.weekday - 1];
    final m = months[_now.month - 1];
    return '$d, $m ${_now.day}';
  }

  String _formattedTime() {
    final hour = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final min = _now.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }

  Widget _buildHomeScreen(ColorScheme cs) {
    final homeApps = _homeGridPackages
        .map((pkg) => _allApps.where((a) => a.pkg == pkg).firstOrNull)
        .whereType<AppModel>()
        .toList();

    final dockApps = _dockPackages
        .map((pkg) => _allApps.where((a) => a.pkg == pkg).firstOrNull)
        .whereType<AppModel>()
        .toList();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: _showLauncherSettings,
      onVerticalDragUpdate: (details) {
        final screenHeight = MediaQuery.of(context).size.height;
        _drawerController.value -= details.primaryDelta! / (screenHeight * 0.75);
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -350 || _drawerController.value > 0.35) {
          _openDrawer();
        } else {
          _closeDrawer();
        }
      },
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pixel At-a-Glance & Material You Clock Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formattedDate(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _recentApps.isNotEmpty
                            ? '${_recentApps.length} newly installed'
                            : 'Caesium Material You',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.85),
                          shadows: const [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _formattedTime(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Home Screen Pinned Apps Grid
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: homeApps.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _gridColumns,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemBuilder: (context, index) {
                    return RepaintBoundary(
                      child: _buildAppIcon(homeApps[index], size: 58),
                    );
                  },
                ),
              ),

              // Bottom Search Pill
              GestureDetector(
                onTap: () {
                  _openDrawer();
                  Future.delayed(const Duration(milliseconds: 220), () {
                    if (mounted) _searchFocus.requestFocus();
                  });
                },
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh.withOpacity(0.94),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: cs.primary, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Search apps or web...',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.tune_rounded,
                            color: cs.onSurfaceVariant, size: 22),
                        onPressed: _showLauncherSettings,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Floating Material You Tonal Dock
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer.withOpacity(0.88),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final app in dockApps)
                      RepaintBoundary(
                        child: _buildAppIcon(app, size: 54, showLabel: false),
                      ),
                    GestureDetector(
                      onTap: _openDrawer,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: ShapeDecoration(
                          shape: _getShapeBorder(),
                          color: cs.primaryContainer,
                        ),
                        child: Icon(
                          Icons.apps_rounded,
                          color: cs.onPrimaryContainer,
                          size: 26,
                        ),
                      ),
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

  Widget _buildRecentlyInstalledShelf(ColorScheme cs) {
    if (!_showRecentShelf ||
        _recentApps.isEmpty ||
        _searchController.text.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(0.45),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.primary.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Recently Installed',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    for (final a in _recentApps) {
                      _dismissedNewApps.add(a.pkg);
                    }
                    _recentApps.clear();
                  });
                  _savePreferences();
                },
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _recentApps.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, idx) {
                final app = _recentApps[idx];
                return SizedBox(
                  width: 68,
                  child: RepaintBoundary(
                    child: _buildAppIcon(
                      app,
                      size: 52,
                      textColor: cs.onSurface,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerSheet(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // Drag Handle
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                final screenHeight = MediaQuery.of(context).size.height;
                _drawerController.value -=
                    details.primaryDelta! / (screenHeight * 0.75);
              },
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity > 350 || _drawerController.value < 0.65) {
                  _closeDrawer();
                } else {
                  _openDrawer();
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),

            // Header & Mode Switch
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'All Apps (${_filteredApps.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  FilterChip(
                    label: Text(_categorizedMode ? 'Categories' : 'A - Z Grid'),
                    avatar: Icon(
                      _categorizedMode
                          ? Icons.folder_copy_outlined
                          : Icons.grid_view_rounded,
                      size: 18,
                    ),
                    selected: _categorizedMode,
                    onSelected: (val) {
                      setState(() => _categorizedMode = val);
                      _savePreferences();
                    },
                  ),
                ],
              ),
            ),

            // Recently Installed Shelf
            _buildRecentlyInstalledShelf(cs),

            // Main App List / Grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _categorizedMode
                      ? _buildCategorizedDrawer(cs)
                      : GridView.builder(
                          controller: _drawerScrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          cacheExtent: 1500,
                          itemCount: _filteredApps.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _gridColumns,
                            mainAxisSpacing: 18,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.80,
                          ),
                          itemBuilder: (context, index) {
                            final app = _filteredApps[index];
                            return RepaintBoundary(
                              child: _buildAppIcon(
                                app,
                                size: 56,
                                textColor: cs.onSurface,
                              ),
                            );
                          },
                        ),
            ),

            // Bottom Search Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withOpacity(0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onChanged: _filterApps,
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Search installed apps...',
                        hintStyle: TextStyle(color: cs.onSurfaceVariant),
                        prefixIcon:
                            Icon(Icons.search_rounded, color: cs.primary),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterApps('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withOpacity(0.65),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    onPressed: _closeDrawer,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    tooltip: 'Close Drawer',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorizedDrawer(ColorScheme cs) {
    final Map<String, List<AppModel>> groups = {};
    for (final app in _filteredApps) {
      groups.putIfAbsent(app.category, () => []).add(app);
    }
    final categories = groups.keys.toList()..sort();

    return ListView.builder(
      controller: _drawerScrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      physics: const BouncingScrollPhysics(),
      cacheExtent: 1200,
      itemCount: categories.length,
      itemBuilder: (context, idx) {
        final category = categories[idx];
        final apps = groups[category]!;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$category (${apps.length})',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: apps.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _gridColumns,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.80,
                ),
                itemBuilder: (context, i) {
                  return RepaintBoundary(
                    child: _buildAppIcon(
                      apps[i],
                      size: 52,
                      textColor: cs.onSurface,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (_drawerController.value > 0.1) {
          _closeDrawer();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            RepaintBoundary(
              child: _buildHomeScreen(cs),
            ),
            AnimatedBuilder(
              animation: _drawerController,
              builder: (context, child) {
                final val = _drawerController.value.clamp(0.0, 1.0);
                if (val == 0.0) return const SizedBox.shrink();

                return Stack(
                  children: [
                    GestureDetector(
                      onTap: _closeDrawer,
                      child: Container(
                        color: Colors.black.withOpacity(0.45 * val),
                      ),
                    ),
                    FractionalTranslation(
                      translation: Offset(0, 1.0 - val),
                      child: child,
                    ),
                  ],
                );
              },
              child: RepaintBoundary(
                child: _buildDrawerSheet(cs),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
