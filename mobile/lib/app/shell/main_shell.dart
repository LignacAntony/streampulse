import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'player_bar.dart';

/// Barre de navigation inférieure + `IndexedStack` des onglets
/// (`StatefulShellRoute`) ; chaque onglet conserve son état.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      // Barre de lecture (direct STR-109 ou file d'attente US-05-04) + barre de
      // nav dans le `bottomNavigationBar` : hors du `body`, elles ne sont pas
      // soumises à `resizeToAvoidBottomInset` (un clavier ne remonte donc pas le
      // mini-player ni ne comprime l'onglet). La barre est masquée
      // (SizedBox.shrink) quand rien ne joue.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PlayerBar(),
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onDestinationSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Accueil',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Bibliothèque',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: 'Découvrir',
              ),
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view),
                label: 'Tableau',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profil',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
