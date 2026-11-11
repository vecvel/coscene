import 'package:coscene_content/coscene_content.dart';
import 'package:coscene_core/coscene_core.dart';
import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../services/audio.dart';
import '../ui/kit.dart';
import 'notebook_screen.dart';

enum _After { next, replay, leave }

/// One scene. The player sets it up freely; nothing is judged until they
/// press the action button.
class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.level});
  final LevelSpec level;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  late PlaySession _session;
  late SceneDelegate _delegate;
  Playback? _playback;
  String? _status;
  bool _statusIsError = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _session = PlaySession(Engine.standard, widget.level);
    _delegate = delegateFor(_session.scene);
    _playback = null;
    _status = null;
    _busy = false;
  }

  GameState get _game => GameScope.of(context);
  String get _short => _game.shortName(widget.level);

  void _onFeedback(SceneFeedback f) {
    switch (f) {
      case SceneFeedback.tick:
        _game.play(Sfx.tick);
        _game.buzz(0);
      case SceneFeedback.lift:
        _game.play(Sfx.lift);
        _game.buzz(0);
      case SceneFeedback.snap:
        _game.play(Sfx.snap);
        _game.buzz(1);
      case SceneFeedback.reject:
        _game.play(Sfx.reject);
        _game.buzz(2);
    }
  }

  /// The player changed the setup: the last result no longer applies.
  void _onChanged() {
    if (_playback != null || _status != null) {
      setState(() {
        _playback = null;
        _status = null;
      });
    }
  }

  void _submit() {
    if (_busy || _session.solved) return;
    final result = _session.submit();
    _game.play(Sfx.engage);
    _game.buzz(2);
    setState(() {
      _busy = true;
      _status = null;
      _playback = Playback(result.outcome, result.timeline);
    });
  }

  Future<void> _onPlaybackEnd() async {
    final outcome = _playback?.outcome;
    if (outcome == null || !mounted) return;
    if (!outcome.success) {
      _game.play(Sfx.fail);
      _game.buzz(3);
      setState(() {
        _busy = false;
        _statusIsError = true;
        _status = '${_game.t('fail.$_short.${outcome.kind}')} ${_game.t('ui.try_again')}';
      });
      return;
    }
    _game.play(Sfx.success);
    _game.buzz(1);
    setState(() {
      _statusIsError = false;
      _status = _game.t('ok.$_short');
    });
    final newIdea = _game.recordSolve(_session);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    _game.play(Sfx.reveal);
    final next = _game.registry.next(widget.level);
    final canGoOn = widget.level.place != dailyPlace && next != null && _game.isLevelOpen(next);
    final choice = await showModalBottomSheet<_After>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => GameScope(
        game: _game,
        child: _RevealSheet(level: widget.level, stars: _session.stars, newIdea: newIdea, canGoOn: canGoOn),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _After.next:
        Navigator.of(context).pushReplacement(pageRoute(PlayScreen(level: next!)));
      case _After.replay:
        setState(_start);
      default:
        Navigator.of(context).pop();
    }
  }

  void _reset() {
    if (_busy) return;
    _session.reset();
    _delegate.sync();
    _game.buzz(0);
    setState(() {
      _playback = null;
      _status = null;
    });
  }

  void _showHints() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GameScope(
        game: _game,
        child: _HintSheet(session: _session, onReveal: () => setState(() {})),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final level = widget.level;
    final hintsLeft = level.hints.length - _session.hintsUsed;
    final buttons = [
      PressButton(
        icon: GameIcons.reset,
        semanticLabel: game.t('ui.reset_scene'),
        color: Palette.sand,
        foreground: Palette.ink,
        onTap: _busy ? null : _reset,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: PressButton(
          label: game.t('action.$_short'),
          color: Palette.ink,
          onTap: _busy || _session.solved ? null : _submit,
        ),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(
              title: level.place == dailyPlace ? game.t('ui.daily') : '${game.placeName(level.place)} · ${level.index}',
              trailing: Semantics(
                button: true,
                label: '${game.t('ui.hint')}, $hintsLeft',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showHints,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: Palette.sand, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const GameIcon(GameIcons.hint, size: 20, color: Palette.ink),
                        const SizedBox(width: 4),
                        Text('$hintsLeft', style: Type.label.copyWith(color: Palette.ink)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(game.objective(level), style: Type.heading),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Semantics(
                  label: game.objective(level),
                  child: SceneView(
                    delegate: _delegate,
                    playback: _playback,
                    ghost: _session.solved ? null : _session.ghost,
                    enabled: !_busy && !_session.solved,
                    reduceMotion: game.reduceMotion,
                    onChanged: _onChanged,
                    onFeedback: _onFeedback,
                    onPlaybackEnd: _onPlaybackEnd,
                  ),
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 46),
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              alignment: Alignment.centerLeft,
              child: Text(
                _status ?? game.t('tip.$_short'),
                style: Type.soft.copyWith(
                  color: _status == null ? Palette.inkSoft : (_statusIsError ? Palette.coralDeep : Palette.tealDeep),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, buttonBottomPadding(context)),
              child: Row(children: game.leftHanded ? buttons.reversed.toList() : buttons),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintSheet extends StatefulWidget {
  const _HintSheet({required this.session, required this.onReveal});
  final PlaySession session;
  final VoidCallback onReveal;

  @override
  State<_HintSheet> createState() => _HintSheetState();
}

class _HintSheetState extends State<_HintSheet> {
  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final session = widget.session;
    final shown = session.shownHints;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, buttonBottomPadding(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Handle(),
            Text(game.t('ui.hints_title'), style: Type.heading),
            const SizedBox(height: 10),
            for (var i = 0; i < shown.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(top: 1, right: 10),
                      decoration: const BoxDecoration(color: Palette.mustard, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('${i + 1}', style: Type.label.copyWith(color: Palette.ink)),
                    ),
                    Expanded(child: Text(game.t(shown[i], session.level.textParams), style: Type.body)),
                  ],
                ),
              ),
            Text(game.t(session.hasMoreHints ? 'ui.hint_cost' : 'ui.hint_none'), style: Type.soft),
            const SizedBox(height: 14),
            if (session.hasMoreHints)
              PressButton(
                label: game.t(shown.isEmpty ? 'ui.hint_show' : 'ui.hint_more'),
                icon: GameIcons.hint,
                onTap: () {
                  session.revealHint();
                  widget.onReveal();
                  setState(() {});
                },
              )
            else
              PressButton(label: game.t('ui.done'), onTap: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

/// Slides up after a correct submission: what the player did, in plain
/// words, and the name of the idea behind it.
class _RevealSheet extends StatelessWidget {
  const _RevealSheet({required this.level, required this.stars, required this.newIdea, required this.canGoOn});
  final LevelSpec level;
  final int stars;
  final bool newIdea;
  final bool canGoOn;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final concept = 'concept.${level.conceptId}';
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, buttonBottomPadding(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Handle(),
            Stars(stars, size: 30),
            const SizedBox(height: 8),
            Text(game.t('ok.${game.shortName(level)}'), style: Type.title.copyWith(fontSize: 21)),
            const SizedBox(height: 6),
            Text(game.t(level.revealKey, level.textParams), style: Type.soft.copyWith(fontSize: 15)),
            const SizedBox(height: 14),
            Panel(
              color: Palette.tealTint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(game.t('ui.reveal_idea'), style: Type.label.copyWith(color: Palette.teal)),
                  const SizedBox(height: 2),
                  Text(game.t('$concept.name'), style: Type.heading.copyWith(color: Palette.tealDeep)),
                  const SizedBox(height: 4),
                  Text(game.t('$concept.idea'), style: Type.body.copyWith(color: Palette.tealDeep)),
                  const SizedBox(height: 10),
                  Text(game.t('ui.reveal_seen'), style: Type.label.copyWith(color: Palette.teal)),
                  Text(game.t('$concept.seen'), style: Type.body.copyWith(color: Palette.tealDeep)),
                ],
              ),
            ),
            if (newIdea) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const GameIcon(GameIcons.solved, size: 18, color: Palette.teal),
                  const SizedBox(width: 6),
                  Expanded(child: Text(game.t('ui.reveal_added'), style: Type.label)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                PressButton(
                  icon: GameIcons.notebook,
                  semanticLabel: game.t('ui.notebook'),
                  color: Palette.sand,
                  foreground: Palette.ink,
                  onTap: () => Navigator.of(context).push(pageRoute(const NotebookScreen())),
                ),
                const SizedBox(width: 10),
                PressButton(
                  icon: GameIcons.replay,
                  semanticLabel: game.t('ui.reveal_replay'),
                  color: Palette.sand,
                  foreground: Palette.ink,
                  onTap: () => Navigator.of(context).pop(_After.replay),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PressButton(
                    label: game.t(
                      canGoOn ? 'ui.reveal_next' : (level.place == dailyPlace ? 'ui.done' : 'ui.reveal_places'),
                    ),
                    onTap: () => Navigator.of(context).pop(canGoOn ? _After.next : _After.leave),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Palette.stone, borderRadius: BorderRadius.circular(2)),
    ),
  );
}
