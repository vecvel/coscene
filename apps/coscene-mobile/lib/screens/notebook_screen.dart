import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/material.dart';

import '../ui/kit.dart';

/// Every idea the player has uncovered, and how many are still hidden.
class NotebookScreen extends StatelessWidget {
  const NotebookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final all = game.allConcepts;
    final found = game.foundConcepts;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(title: game.t('ui.notebook')),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                found.isEmpty
                    ? game.t('ui.notebook_empty')
                    : game.t('ui.notebook_count', {'found': found.length, 'total': all.length}),
                style: Type.soft,
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(16, 4, 16, scrollEndPadding(context)),
                itemCount: all.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final key = 'concept.${all[i]}';
                  if (!found.contains(all[i])) {
                    return Panel(
                      color: Palette.sand,
                      child: Row(
                        children: [
                          const GameIcon(GameIcons.lock, size: 18, color: Palette.stone),
                          const SizedBox(width: 10),
                          Text(game.t('ui.notebook_hidden'), style: Type.soft),
                        ],
                      ),
                    );
                  }
                  return Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(game.t('$key.name'), style: Type.heading),
                        const SizedBox(height: 4),
                        Text(game.t('$key.idea'), style: Type.body),
                        const SizedBox(height: 8),
                        Text(game.t('ui.reveal_seen'), style: Type.label),
                        Text(game.t('$key.seen'), style: Type.soft),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
