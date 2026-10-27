import 'package:flutter/material.dart';
import 'dart:ui';

void main() => runApp(const CaesiumLauncherApp());

class CaesiumLauncherApp extends StatelessWidget {
  const CaesiumLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0C),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _drawerController;
  bool _isDrawerOpen = false;
  String _selectedCategory = 'All';

  final List<Map<String, String>> _apps = [
    {'name': 'Caesium Panelz', 'category': 'System', 'icon': 'tune'},
    {'name': 'Loocal Music', 'category': 'Media', 'icon': 'music_note'},
    {'name': 'Browser', 'category': 'Internet', 'icon': 'public'},
    {'name': 'Settings', 'category': 'System', 'icon': 'settings'},
    {'name': 'Camera', 'category': 'Media', 'icon': 'camera_alt'},
    {'name': 'Files', 'category': 'System', 'icon': 'folder'},
    {'name': 'Terminal', 'category': 'Development', 'icon': 'terminal'},
    {'name': 'Discord', 'category': 'Social', 'icon': 'chat'},
    {'name': 'Spotify', 'category': 'Media', 'icon': 'headset'},
  ];

  @override
  void initState() {
    super.initState();
    _drawerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _drawerController.dispose();
    super.dispose();
  }

  void _toggleDrawer() {
    setState(() {
      _isDrawerOpen = !_isDrawerOpen;
      if (_isDrawerOpen) {
        _drawerController.forward();
      } else {
        _drawerController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['All', 'System', 'Media', 'Internet', 'Development', 'Social'];
    final filteredApps = _selectedCategory == 'All' 
        ? _apps 
        : _apps.where((app) => app['category'] == _selectedCategory).toList();

    return WillPopScope(
      onWillPop: () async {
        if (_isDrawerOpen) {
          _toggleDrawer();
          return false;
        }
        return false;
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF141418), Color(0xFF070709)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 48.0),
                        child: Column(
                          children: [
                            Text(
                              TimeOfDay.now().format(context),
                              style: const TextStyle(
                                fontSize: 64,
                                fontWeight: FontWeight.w300,
                                color: Colors.white,
                                letterSpacing: -2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "TUESDAY, OCTOBER 27",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.cyanAccent,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              width: MediaQuery.of(context).size.width * 0.85,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildDockIcon(Icons.music_note, "Music"),
                                  _buildDockIcon(Icons.tune, "Panelz"),
                                  GestureDetector(
                                    onTap: _toggleDrawer,
                                    child: Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: Colors.cyanAccent.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.cyanAccent, width: 1.5),
                                      ),
                                      child: const Icon(Icons.apps, color: Colors.cyanAccent),
                                    ),
                                  ),
                                  _buildDockIcon(Icons.public, "Browser"),
                                  _buildDockIcon(Icons.settings, "Settings"),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _drawerController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, MediaQuery.of(context).size.height * (1 - _drawerController.value)),
                  child: child,
                );
              },
              child: RepaintBoundary(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF101014).withOpacity(0.95),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 38,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: categories.length,
                            itemBuilder: (context, index) {
                              final cat = categories[index];
                              final isSelected = _selectedCategory == cat;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ChoiceChip(
                                  label: Text(cat),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    setState(() => _selectedCategory = cat);
                                  },
                                  selectedColor: Colors.cyanAccent,
                                  backgroundColor: Colors.white10,
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: GridView.builder(
                            cacheExtent: 1000,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 20,
                              crossAxisSpacing: 16,
                              childAspectRatio: 0.8,
                            ),
                            itemCount: filteredApps.length,
                            itemBuilder: (context, index) {
                              final app = filteredApps[index];
                              return Column(
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Icon(_getIconData(app['icon']!), color: Colors.cyanAccent),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    app['name']!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: IconButton(
                            onPressed: _toggleDrawer,
                            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.cyanAccent, size: 28),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDockIcon(IconData icon, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }

  IconData _getIconData(String name) {
    switch (name) {
      case 'tune': return Icons.tune;
      case 'music_note': return Icons.music_note;
      case 'public': return Icons.public;
      case 'settings': return Icons.settings;
      case 'camera_alt': return Icons.camera_alt;
      case 'folder': return Icons.folder;
      case 'terminal': return Icons.terminal;
      case 'chat': return Icons.chat;
      case 'headset': return Icons.headset;
      default: return Icons.apps;
    }
  }
}
