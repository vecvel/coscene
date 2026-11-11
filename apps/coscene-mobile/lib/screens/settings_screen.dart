import 'package:coscene_i18n/coscene_i18n.dart';
import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../ui/kit.dart';

/// Shown on the About line. Kept in step with pubspec.yaml.
const String appVersion = '1.0.0';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmReset(BuildContext context, GameState game) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(game.t('ui.reset_title'), style: Type.heading),
        content: Text(game.t('ui.reset_body'), style: Type.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(game.t('ui.cancel'), style: Type.body),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(game.t('ui.reset_confirm'), style: Type.body.copyWith(color: Palette.coralDeep)),
          ),
        ],
      ),
    );
    if (yes == true) await game.resetProgress();
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(title: game.t('ui.settings')),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 4, 16, scrollEndPadding(context)),
                children: [
                  Text(game.t('ui.language'), style: Type.label),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final lang in supportedLanguages)
                        Semantics(
                          button: true,
                          selected: lang.code == game.language,
                          label: lang.englishName,
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: () => game.setLanguage(lang.code),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: lang.code == game.language ? Palette.ink : Palette.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                lang.nativeName,
                                // Each name is drawn in its own script.
                                locale: Locale(lang.code),
                                style: Type.body.copyWith(
                                  color: lang.code == game.language ? Palette.cream : Palette.ink,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(
                      children: [
                        _Toggle(game.t('ui.sound'), game.sound, (v) => game.update(() => game.sound = v)),
                        _Toggle(game.t('ui.haptics'), game.haptics, (v) => game.update(() => game.haptics = v)),
                        _Toggle(
                          game.t('ui.reduce_motion'),
                          game.reduceMotion,
                          (v) => game.update(() => game.reduceMotion = v),
                        ),
                        _Toggle(
                          game.t('ui.left_handed'),
                          game.leftHanded,
                          (v) => game.update(() => game.leftHanded = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  PressButton(
                    label: game.t('ui.reset_progress'),
                    color: Palette.sand,
                    foreground: Palette.coralDeep,
                    onTap: () => _confirmReset(context, game),
                  ),
                  const SizedBox(height: 24),
                  Text(game.t('ui.about'), style: Type.label),
                  const SizedBox(height: 6),
                  Text(game.t('ui.version', {'version': appVersion}), style: Type.soft),
                  Text(game.t('ui.privacy'), style: Type.soft),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label, style: Type.body)),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 46,
              height: 28,
              padding: const EdgeInsets.all(3),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: value ? Palette.teal : Palette.stone,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: Palette.white, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
