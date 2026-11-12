import 'package:flutter/material.dart';

import '../theme.dart';
import 'food_only_tab.dart';
import 'nyota_gifts_tab.dart';

/// Add Entry: two tabs — "Nyota with Gifts" and "Food Only" quick entry.
class EntryFormScreen extends StatelessWidget {
  const EntryFormScreen({super.key, this.onSaved});

  final VoidCallback? onSaved;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: NyotaColors.royalPurple,
            child: TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              tabs: const [
                Tab(height: 52, text: '🎁  Nyota with Gifts'),
                Tab(height: 52, text: '🍛  Food Only'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                NyotaGiftsTab(onSaved: onSaved),
                FoodOnlyTab(onSaved: onSaved),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
