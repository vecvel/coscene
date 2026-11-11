import 'dart:math' as math;

import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../services/audio.dart';

/// Gives every screen the shared [GameState] and rebuilds them when it changes.
class GameScope extends InheritedNotifier<GameState> {
  const GameScope({super.key, required GameState game, required super.child}) : super(notifier: game);

  static GameState of(BuildContext context) => maybeOf(context)!;

  static GameState? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GameScope>()?.notifier;
}

abstract final class Type {
  static const TextStyle title = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Palette.ink, height: 1.2);
  static const TextStyle heading = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Palette.ink,
    height: 1.3,
  );
  static const TextStyle body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: Palette.ink, height: 1.45);
  static const TextStyle soft = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Palette.inkSoft,
    height: 1.45,
  );
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Palette.inkSoft,
    height: 1.3,
  );
}

/// A flat, solid button that dips slightly while pressed.
class PressButton extends StatefulWidget {
  const PressButton({
    super.key,
    this.label,
    this.icon,
    required this.onTap,
    this.color = Palette.ink,
    this.foreground = Palette.cream,
    this.height = 52,
    this.semanticLabel,
  });

  final String? label;
  final GameIcons? icon;
  final VoidCallback? onTap;
  final Color color;
  final Color foreground;
  final double height;
  final String? semanticLabel;

  @override
  State<PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<PressButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final label = widget.label;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled
            ? () {
                GameScope.maybeOf(context)?.play(Sfx.tick);
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          child: Container(
            height: widget.height,
            constraints: BoxConstraints(minWidth: widget.height),
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 20),
            decoration: BoxDecoration(
              color: enabled ? widget.color : Palette.stone,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) GameIcon(widget.icon!, color: widget.foreground, size: 24),
                if (widget.icon != null && label != null) const SizedBox(width: 8),
                if (label != null)
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: widget.foreground),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One to three stars, earned ones in mustard.
class Stars extends StatelessWidget {
  const Stars(this.count, {super.key, this.size = 18, this.empty = Palette.stone});
  final int count;
  final double size;
  final Color empty;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$count / 3',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          if (i < count)
            GameIcon(GameIcons.star, size: size, fill: Palette.mustard)
          else
            GameIcon(GameIcons.star, size: size, color: empty),
      ],
    ),
  );
}

/// Screen heading with a back button and an optional action on the right.
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, this.trailing, this.onBack});
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: game.t('ui.back'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              child: const SizedBox(width: 48, height: 48, child: Center(child: GameIcon(GameIcons.back, size: 26))),
            ),
          ),
          Expanded(
            child: Text(title, style: Type.heading, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A flat card.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color = Palette.white,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
      child: child,
    );
    return onTap == null ? card : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card);
  }
}

/// A plain page route. Slides with the platform's own transition.
Route<T> pageRoute<T>(Widget page) => MaterialPageRoute<T>(builder: (_) => page);

/// Space under the last item of a scrolling screen. The list itself runs to
/// the bottom edge of the phone; only its end clears the home indicator.
double scrollEndPadding(BuildContext context) => MediaQuery.viewPaddingOf(context).bottom + 16;

/// Space under a row of buttons pinned to the bottom: the phone's own inset
/// where it has one, a small margin where it does not. Never both.
double buttonBottomPadding(BuildContext context) => math.max(MediaQuery.viewPaddingOf(context).bottom, 16);
