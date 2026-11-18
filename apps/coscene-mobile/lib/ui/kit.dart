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
/// A [subtitle] sits right under the title and starts where the title does.
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, this.subtitle, this.trailing, this.onBack});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onBack;

  static const double _row = 48;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final sub = subtitle;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 4, 16, sub == null ? 4 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: game.t('ui.back'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: _row,
                height: _row,
                child: Center(child: GameIcon(GameIcons.back, size: 26)),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              // Centres the title line on the back button.
              padding: EdgeInsets.only(top: (_row - Type.heading.fontSize! * Type.heading.height!) / 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Type.heading, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: Type.soft)],
                ],
              ),
            ),
          ),
          if (trailing case final Widget action)
            SizedBox(
              height: _row,
              child: Center(child: action),
            ),
        ],
      ),
    );
  }
}

/// Fades scrolled content out toward the top edge, so it slips under the
/// status bar instead of being cut off. There is no fade until the content
/// moves, and it eases in over the first 44 points of scrolling.
class TopEdgeFade extends StatefulWidget {
  const TopEdgeFade({super.key, required this.child});
  final Widget child;

  @override
  State<TopEdgeFade> createState() => _TopEdgeFadeState();
}

class _TopEdgeFadeState extends State<TopEdgeFade> {
  static const double _reach = 44;
  double _strength = 0;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final s = (n.metrics.pixels / _reach).clamp(0.0, 1.0);
    if (s != _strength) setState(() => _strength = s);
    return false;
  }

  static double _smootherstep(double t) => t * t * t * (t * (t * 6 - 15) + 10);

  @override
  Widget build(BuildContext context) {
    final fadeEnd = MediaQuery.viewPaddingOf(context).top + _reach;
    final strength = _strength;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      // The mask stays in the tree at rest (fully opaque) so the scroll view
      // underneath keeps its state when the fade switches on.
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) {
          const steps = 16;
          final end = (fadeEnd / rect.height).clamp(0.0, 1.0);
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              for (var i = 0; i < steps; i++)
                Color.fromRGBO(0, 0, 0, 1 - strength * (1 - _smootherstep(i / (steps - 1)))),
              const Color(0xFF000000),
            ],
            stops: [for (var i = 0; i < steps; i++) end * i / (steps - 1), 1],
          ).createShader(rect);
        },
        child: widget.child,
      ),
    );
  }
}

/// A full-height page: the header scrolls away with the content, which fades
/// out under the status bar.
class ScrollPage extends StatelessWidget {
  const ScrollPage({super.key, required this.header, required this.body});
  final Widget header;

  /// The page content, as a sliver.
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: TopEdgeFade(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.viewPaddingOf(context).top)),
            SliverToBoxAdapter(child: header),
            SliverPadding(padding: EdgeInsets.fromLTRB(16, 4, 16, scrollEndPadding(context)), sliver: body),
          ],
        ),
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
