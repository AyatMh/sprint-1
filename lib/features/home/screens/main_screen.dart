import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../../history/screens/history_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/liquid_tab_bar.dart';
import '../../../shared/widgets/particles_background.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        onOpenProfile: () => _go(2),
        onSeeAllRecordings: () => _go(1),
      ),
      const HistoryScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Stack(
        children: [
          // Ambient wallpaper the glass refracts, plus subtle particles.
          const Positioned.fill(child: AmbientBackground()),
          const Positioned.fill(
            child: ParticlesBackground(
              quantity: 60,
              color: AppColors.wine,
            ),
          ),

          // Active tab, cross-faded. Each tab rebuilds from its Firestore
          // stream when revisited, so no state needs to be kept alive.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey(_index),
                child: pages[_index],
              ),
            ),
          ),

          // Floating Liquid Glass tab bar.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 18),
              child: Center(
                child: LiquidTabBar(
                  selectedIndex: _index,
                  onItemSelected: _go,
                  items: const [
                    LiquidTabItem(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                      label: 'Home',
                    ),
                    LiquidTabItem(
                      icon: Icons.video_library_outlined,
                      selectedIcon: Icons.video_library_rounded,
                      label: 'Recordings',
                    ),
                    LiquidTabItem(
                      icon: Icons.person_outline_rounded,
                      selectedIcon: Icons.person_rounded,
                      label: 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
