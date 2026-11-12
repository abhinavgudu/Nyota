import 'package:flutter/material.dart';

import '../services/nyota_service.dart';
import '../utils/sound_util.dart';
import 'dashboard_screen.dart';
import 'entry_form_screen.dart';
import 'register_screen.dart';

/// Main shell with bottom navigation: Dashboard | Add Entry | Register.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _dashboardKey = GlobalKey<DashboardScreenState>();

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(key: _dashboardKey),
      EntryFormScreen(onSaved: () => _dashboardKey.currentState?.refresh()),
      RegisterScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset('assets/logo_mark.png', width: 34, height: 34),
            ),
            const SizedBox(width: 10),
            const Text('Nyota'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: SoundUtil.enabled ? 'Sound off' : 'Sound on',
            icon: Icon(
              SoundUtil.enabled ? Icons.volume_up : Icons.volume_off,
              color: Colors.white,
            ),
            onPressed: () async {
              await SoundUtil.setEnabled(!SoundUtil.enabled);
              if (!mounted) return;
              setState(() {});
              if (SoundUtil.enabled) await SoundUtil.confirmSave();
            },
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await NyotaService.signOut();
                if (context.mounted) setState(() => _index = 0);
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), activeIcon: Icon(Icons.add_circle), label: 'Add Entry'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Register'),
        ],
      ),
    );
  }
}
