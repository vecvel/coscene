import 'package:coscene_content/coscene_content.dart';
import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../ui/kit.dart';
import 'notebook_screen.dart';
import 'place_screen.dart';
import 'play_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// The front door: continue, today's scene, and the list of places.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final next = game.nextUp;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, scrollEndPadding(context)),
          children: [
            Row(
              children: [
                const LogoMark(size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(game.t('app.name'), style: Type.title),
                      Text(game.t('app.tagline'), style: Type.label),
                    ],
                  ),
                ),
                _ScoreChip(game: game),
                const SizedBox(width: 8),
                PressButton(
                  icon: GameIcons.settings,
                  semanticLabel: game.t('ui.settings'),
                  color: Palette.sand,
                  foreground: Palette.ink,
                  height: 44,
                  onTap: () => Navigator.of(context).push(pageRoute(const SettingsScreen())),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (game.newScenesReady) ...[
              Panel(
                color: Palette.tealTint,
                child: Text(game.t('ui.new_scenes'), style: Type.body.copyWith(color: Palette.tealDeep)),
              ),
              const SizedBox(height: 12),
            ],
            if (next != null) ...[
              PressButton(
                label:
                    '${game.t(game.totalSolved == 0 ? 'ui.play' : 'ui.continue')} · '
                    '${game.placeName(next.place)} ${next.index}',
                icon: GameIcons.play,
                color: Palette.orange,
                foreground: Palette.white,
                height: 58,
                onTap: () => Navigator.of(context).push(pageRoute(PlayScreen(level: next))),
              ),
              const SizedBox(height: 12),
            ],
            _DailyCard(game: game),
            const SizedBox(height: 12),
            Panel(
              onTap: () => Navigator.of(context).push(pageRoute(const NotebookScreen())),
              child: Row(
                children: [
                  const GameIcon(GameIcons.notebook, color: Palette.ink),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(game.t('ui.notebook'), style: Type.heading),
                        Text(
                          game.t('ui.notebook_count', {
                            'found': game.foundConcepts.length,
                            'total': game.allConcepts.length,
                          }),
                          style: Type.label,
                        ),
                      ],
                    ),
                  ),
                  const GameIcon(GameIcons.open, color: Palette.stone),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(game.t('ui.places'), style: Type.heading),
            const SizedBox(height: 10),
            for (final place in game.registry.places) ...[
              _PlaceCard(game: game, place: place),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${game.t('ui.profile')}, cosIQ ${game.score}',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(pageRoute(const ProfileScreen())),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'cosIQ ',
              style: TextStyle(fontSize: 12, color: Palette.stone, fontWeight: FontWeight.w500),
            ),
            Text(
              '${game.score}',
              style: const TextStyle(fontSize: 17, color: Palette.cream, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final done = game.dailyDone;
    final streak = game.currentStreak;
    return Panel(
      color: Palette.slate,
      onTap: done ? null : () => Navigator.of(context).push(pageRoute(PlayScreen(level: dailyLevel(DateTime.now())))),
      child: Row(
        children: [
          GameIcon(done ? GameIcons.solved : GameIcons.sun, color: Palette.mustard, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(game.t('ui.daily'), style: Type.heading.copyWith(color: Palette.cream)),
                Text(
                  game.t(done ? 'ui.daily_done' : 'ui.daily_tagline'),
                  style: Type.soft.copyWith(color: Palette.sand),
                ),
                if (streak > 0)
                  Text(game.t('ui.daily_streak', {'days': streak}), style: Type.label.copyWith(color: Palette.mustard)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.game, required this.place});
  final GameState game;
  final PlaceInfo place;

  @override
  Widget build(BuildContext context) {
    final open = game.isPlaceOpen(place.number);
    final total = game.registry.levelsOf(place.number).length;
    final solved = game.solvedIn(place.number);
    final accent = Palette.place(place.number);
    return Panel(
      color: open ? Palette.white : Palette.sand,
      onTap: () {
        if (open) {
          Navigator.of(context).push(pageRoute(PlaceScreen(place: place)));
          return;
        }
        final places = game.registry.places;
        final before = places[places.indexWhere((p) => p.number == place.number) - 1];
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: Palette.ink,
              content: Text(
                game.t('ui.locked_place', {'count': levelsToOpenNextPlace, 'place': game.placeName(before.number)}),
              ),
            ),
          );
      },
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: open ? accent : Palette.stone, borderRadius: BorderRadius.circular(14)),
            alignment: Alignment.center,
            child: open
                ? Text(
                    '${place.number}',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Palette.white),
                  )
                : const GameIcon(GameIcons.lock, color: Palette.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(game.t('place.${place.id}.name'), style: Type.heading),
                Text(game.t('place.${place.id}.tagline'), style: Type.soft),
                const SizedBox(height: 2),
                Text(
                  open ? game.t('ui.place_progress', {'solved': solved, 'total': total}) : game.t('ui.locked'),
                  style: Type.label,
                ),
              ],
            ),
          ),
          if (open && solved == total)
            const GameIcon(GameIcons.solved, color: Palette.teal)
          else if (open)
            const GameIcon(GameIcons.open, color: Palette.stone),
        ],
      ),
    );
  }
}
