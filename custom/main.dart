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
        lowerPkg.contains('mms') ||
        lowerPkg.contains('contacts') ||
        lowerPkg.contains('dialer') ||
        lowerPkg.contains('chrome') ||
        lowerPkg.contains('browser')) {
      return 'Social';
    }
    if (lowerPkg.contains('music') ||
        lowerPkg.contains('audio') ||
        lowerPkg.contains('spotify') ||
        lowerPkg.contains('youtube') ||
        lowerPkg.contains('video') ||
        lowerPkg.contains('camera') ||
        lowerPkg.contains('gallery') ||
        lowerPkg.contains('photos') ||
        lowerPkg.contains('podcast') ||
        lowerName.contains('loocal')) {
      return 'Media';
    }
    if (lowerPkg.contains('game') ||
        lowerPkg.contains('minecraft') ||
        lowerPkg.contains('fortnite') ||
        lowerPkg.contains('roblox') ||
        lowerPkg.contains('clash') ||
        lowerPkg.contains('steam')) {
      return 'Games';
    }
    if (lowerPkg.contains('calculator') ||
        lowerPkg.contains('clock') ||
        lowerPkg.contains('deskclock') ||
        lowerPkg.contains('calendar') ||
        lowerPkg.contains('files') ||
        lowerPkg.contains('documentsui') ||
        lowerPkg.contains('notes') ||
        lowerPkg.contains('weather') ||
        lowerPkg.contains('maps') ||
        lowerPkg.contains('recorder')) {
      return 'Tools';
    }
    if (lowerPkg.contains('settings') ||
        lowerPkg.contains('system') ||
        lowerPkg.contains('android') ||
        lowerPkg.contains('google') ||
        lowerPkg.contains('vending') ||
        lowerPkg.contains('magisk') ||
        lowerName.contains('caesium')) {
      return 'System';
    }
    return 'Other';
  }
}

class CaesiumLauncherApp extends StatelessWidget {
  const CaesiumLauncherApp({super.key});

  static final _defaultLightScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8D6E63),
    brightness: Brightness.light,
  );

  static final _defaultDarkScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFD7CCC8),
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
  List<String> _dockPackages = [];
  List<String> _homeGridPackages = [];

  bool _isLoading = true;
  bool _categorizedMode = true;
  bool _themedIcons = false;
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
      duration: const Duration(milliseconds: 260),
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPackagesChanged') {
        final String? action = call.arguments?['action'];
        final String? pkg = call.arguments?['pkg'];
        await _fetchApps();
        if (mounted && action == 'ADDED' && pkg != null) {
          final addedApp = _allApps.where((a) => a.pkg == pkg).firstOrNull;
          if (addedApp != null) {
            if (!_homeGridPackages.contains(pkg) &&
                _homeGridPackages.length < 16) {
              setState(() => _homeGridPackages.add(pkg));
              _savePreferences();
            }
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
      _categorizedMode = prefs.getBool('axion_categories_mode') ?? true;
      _themedIcons = prefs.getBool('themed_icons') ?? false;
      _gridColumns = prefs.getInt('grid_columns') ?? 4;
      _iconShape = prefs.getString('icon_shape') ?? 'circle';
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dock_pkgs', _dockPackages);
    await prefs.setStringList('home_grid_pkgs', _homeGridPackages);
    await prefs.setBool('axion_categories_mode', _categorizedMode);
    await prefs.setBool('themed_icons', _themedIcons);
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

          setState(() {
            _allApps = parsed;
            _filteredApps = parsed;
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
    _drawerController.fling(velocity: 2.8);
  }

  void _closeDrawer() {
    _searchFocus.unfocus();
    _searchController.clear();
    _filterApps('');
    if (_drawerScrollController.hasClients) {
      _drawerScrollController.jumpTo(0);
    }
    _drawerController.fling(velocity: -2.8);
  }

  Future<void> _launchApp(String pkg) async {
    HapticFeedback.selectionClick();
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

  Widget _buildRawAppAvatar(AppModel app, double size) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: _getShapeBorder(),
        color: _themedIcons
            ? cs.secondaryContainer
            : cs.surfaceContainerHighest.withOpacity(0.35),
      ),
      clipBehavior: Clip.antiAlias,
      child: ColorFiltered(
        colorFilter: _themedIcons
            ? ColorFilter.mode(cs.onSecondaryContainer, BlendMode.modulate)
            : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
        child: Image(
          image: app.imageProvider,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }

  Widget _buildAppIcon(AppModel app,
      {double size = 58, bool showLabel = true, Color? textColor}) {
    return GestureDetector(
      onTap: () => _launchApp(app.pkg),
      onLongPress: () => _showAppOptionsSheet(app),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildRawAppAvatar(app, size),
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

  void _openCategoryFolderModal(String categoryTitle, List<AppModel> apps) {
    HapticFeedback.lightImpact();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(ctx),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: MediaQuery.of(context).size.width * 0.88,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.68,
                ),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.45),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          categoryTitle,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '${apps.length} apps',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Flexible(
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        itemCount: apps.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemBuilder: (context, idx) {
                          final app = apps[idx];
                          return _buildAppIcon(
                            app,
                            size: 54,
                            textColor: cs.onSurface,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAxionCategoryCard(
      String title, List<AppModel> apps, ColorScheme cs) {
    final bool hasMoreThanFour = apps.length > 4;

    Widget buildSlot(int slotIndex) {
      if (slotIndex >= apps.length) {
        return const SizedBox.shrink();
      }
      if (slotIndex == 3 && hasMoreThanFour) {
        final subApps = apps.skip(3).take(4).toList();
        return GestureDetector(
          onTap: () => _openCategoryFolderModal(title, apps),
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Container(
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: subApps.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemBuilder: (context, i) {
                  return Center(
                    child: _buildRawAppAvatar(subApps[i], 20),
                  );
                },
              ),
            ),
          ),
        );
      }

      final app = apps[slotIndex];
      return GestureDetector(
        onTap: () => _launchApp(app.pkg),
        onLongPress: () => _showAppOptionsSheet(app),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: _buildRawAppAvatar(app, 58),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _openCategoryFolderModal(title, apps),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow.withOpacity(0.88),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.16),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 10),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withOpacity(0.88),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: buildSlot(0)),
                        const SizedBox(width: 8),
                        Expanded(child: buildSlot(1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: buildSlot(2)),
                        const SizedBox(width: 8),
                        Expanded(child: buildSlot(3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAxionCategorizedGrid(ColorScheme cs) {
    final Map<String, List<AppModel>> groups = {};

    const orderedCategories = [
      'Social',
      'Media',
      'Games',
      'Tools',
      'System',
      'Other'
    ];
    for (final cat in orderedCategories) {
      final matching = _filteredApps.where((a) => a.category == cat).toList();
      if (matching.isNotEmpty) {
        groups[cat] = matching;
      }
    }

    final categoryKeys = groups.keys.toList();

    return GridView.builder(
      controller: _drawerScrollController,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      cacheExtent: 1200,
      itemCount: categoryKeys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (context, idx) {
        final title = categoryKeys[idx];
        final apps = groups[title]!;
        return RepaintBoundary(
          child: _buildAxionCategoryCard(title, apps, cs),
        );
      },
    );
  }

  void _showAppOptionsSheet(AppModel app) {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
    final isPinnedHome = _homeGridPackages.contains(app.pkg);
    final isPinnedDock = _dockPackages.contains(app.pkg);

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
                      title: const Text('Axion OS Smart Categories'),
                      subtitle: const Text(
                          'Organize App Drawer into 2-column Bento cards'),
                      value: _categorizedMode,
                      onChanged: (val) {
                        setState(() => _categorizedMode = val);
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
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Home Grid Columns'),
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
        if (details.localPosition.dy > screenHeight * 0.85 ||
            details.localPosition.dy < screenHeight * 0.12) {
          return;
        }

        _drawerController.value -= details.primaryDelta! / (screenHeight * 0.75);
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 600 && _drawerController.value < 0.1) {
          _channel.invokeMethod('expandNotifications');
          return;
        }

        if (velocity < -650 || _drawerController.value > 0.45) {
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
                        'Caesium Material You',
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
                          'Search apps',
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

  Widget _buildDrawerSheet(ColorScheme cs) {
    final bool isSearching = _searchController.text.trim().isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        final screenHeight = MediaQuery.of(context).size.height;
        _drawerController.value += details.primaryDelta! / (screenHeight * 0.75);
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 350 || _drawerController.value < 0.65) {
          _closeDrawer();
        } else {
          _openDrawer();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 18),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 28,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: true,
          bottom: true,
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDrawer,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 16),
                  child: Center(
                    child: Container(
                      width: 46,
                      height: 5.5,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: _filterApps,
                    style: TextStyle(
                      fontSize: 16,
                      color: cs.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search apps',
                      hintStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: cs.onSurfaceVariant.withOpacity(0.75),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: cs.onSurfaceVariant.withOpacity(0.8),
                        size: 24,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSearching)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                _filterApps('');
                              },
                            ),
                          IconButton(
                            tooltip: _categorizedMode
                                ? 'Switch to All Apps Grid'
                                : 'Switch to Smart Categories',
                            icon: Icon(
                              _categorizedMode
                                  ? Icons.grid_view_rounded
                                  : Icons.folder_copy_rounded,
                              size: 20,
                              color: cs.onSurfaceVariant.withOpacity(0.8),
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(
                                  () => _categorizedMode = !_categorizedMode);
                              _savePreferences();
                            },
                          ),
                        ],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : (_categorizedMode && !isSearching)
                        ? _buildAxionCategorizedGrid(cs)
                        : GridView.builder(
                            controller: _drawerScrollController,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
            ],
          ),
        ),
      ),
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
                        color: Colors.black.withOpacity(0.55 * val),
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
