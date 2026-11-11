import 'package:coscene_content/coscene_content.dart';
import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/material.dart';

import '../ui/kit.dart';
import 'play_screen.dart';

/// The ten scenes of one place.
class PlaceScreen extends StatelessWidget {
  const PlaceScreen({super.key, required this.place});
  final PlaceInfo place;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final levels = game.registry.levelsOf(place.number);
    final accent = Palette.place(place.number);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(title: game.t('place.${place.id}.name')),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(game.t('place.${place.id}.tagline'), style: Type.soft),
            ),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(16, 4, 16, scrollEndPadding(context)),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                ),
                itemCount: levels.length,
                itemBuilder: (context, i) {
                  final level = levels[i];
                  final open = game.isLevelOpen(level);
                  final solved = game.isSolved(level.id);
                  return Semantics(
                    button: true,
                    enabled: open,
                    label: open
                        ? game.t('ui.scene_number', {'number': level.index})
                        : '${game.t('ui.scene_number', {'number': level.index})}, ${game.t('ui.locked')}',
                    child: Panel(
                      color: open ? Palette.white : Palette.sand,
                      onTap: () {
                        if (open) {
                          Navigator.of(context).push(pageRoute(PlayScreen(level: level)));
                        } else {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Palette.ink,
                                content: Text(game.t('ui.locked_scene')),
                              ),
                            );
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${level.index}',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              color: open ? (solved ? Palette.ink : accent) : Palette.stone,
                            ),
                          ),
                          if (!open)
                            const GameIcon(GameIcons.lock, color: Palette.stone, size: 20)
                          else
                            Stars(game.starsOf(level.id), size: 22),
                        ],
                      ),
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
