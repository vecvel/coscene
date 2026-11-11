import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'scene_delegate.dart';

/// Shows a scene, scaled to fit, and passes touches to its delegate.
///
/// The view repaints only while something moves: a finger is down, a
/// playback is running, or the delegate reports that it is still easing.
class SceneView extends StatefulWidget {
  const SceneView({
    super.key,
    required this.delegate,
    this.playback,
    this.ghost,
    this.enabled = true,
    this.reduceMotion = false,
    this.onChanged,
    this.onFeedback,
    this.onPlaybackEnd,
  });

  final SceneDelegate delegate;
  final Playback? playback;
  final Map<String, dynamic>? ghost;

  /// False while a result is playing or after the level is solved.
  final bool enabled;
  final bool reduceMotion;
  final VoidCallback? onChanged;
  final ValueChanged<SceneFeedback>? onFeedback;
  final VoidCallback? onPlaybackEnd;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double _clock = 0;
  double _playTime = 0;
  bool _ended = false;

  int? _pointer;
  Offset _downAt = Offset.zero;
  bool _dragging = false;
  bool _moved = false;
  bool _wasEasing = false;

  static const double _tapSlop = 10;

  @override
  void initState() {
    super.initState();
    _bind();
    _ticker = createTicker(_onTick);
    _wake();
  }

  /// Starts the frame ticker if it is resting. It stops itself again once
  /// nothing is moving, so an idle scene costs no battery.
  void _wake() {
    if (_ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  void _bind() {
    widget.delegate
      ..onChanged = (() {
        widget.onChanged?.call();
        _frame.value++;
        _wake();
      })
      ..onFeedback = (f) => widget.onFeedback?.call(f);
  }

  @override
  void didUpdateWidget(SceneView old) {
    super.didUpdateWidget(old);
    if (!identical(old.delegate, widget.delegate)) _bind();
    if (!identical(old.playback, widget.playback)) {
      _playTime = 0;
      _ended = false;
    }
    _frame.value++;
    _wake();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    _clock += dt;
    final easing = widget.delegate.tick(dt);
    var dirty = easing || _wasEasing || _dragging;
    _wasEasing = easing;
    final playback = widget.playback;
    if (playback != null && !_ended) {
      _playTime += dt;
      dirty = true;
      if (_playTime >= playback.timeline.duration) {
        _playTime = playback.timeline.duration;
        _ended = true;
        widget.onPlaybackEnd?.call();
      }
    }
    if (dirty) {
      _frame.value++;
    } else {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  ({double scale, Offset origin}) _fit(Size size) {
    final logical = widget.delegate.logicalSize;
    final scale = (size.width / logical.width) < (size.height / logical.height)
        ? size.width / logical.width
        : size.height / logical.height;
    return (
      scale: scale,
      origin: Offset((size.width - logical.width * scale) / 2, (size.height - logical.height * scale) / 2),
    );
  }

  Offset _toScene(Offset local, Size size) {
    final fit = _fit(size);
    return (local - fit.origin) / fit.scale;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (!widget.enabled || _pointer != null) return;
            _pointer = e.pointer;
            _downAt = e.localPosition;
            _moved = false;
            _dragging = widget.delegate.onDown(_toScene(e.localPosition, size));
            _frame.value++;
            _wake();
          },
          onPointerMove: (e) {
            if (e.pointer != _pointer) return;
            if ((e.localPosition - _downAt).distance > _tapSlop) _moved = true;
            if (_dragging) {
              widget.delegate.onMove(_toScene(e.localPosition, size));
              _frame.value++;
            }
          },
          onPointerUp: (e) {
            if (e.pointer != _pointer) return;
            _pointer = null;
            final p = _toScene(e.localPosition, size);
            if (_dragging) {
              widget.delegate.onUp(p);
              if (!_moved) widget.delegate.onTap(p);
            } else if (!_moved) {
              widget.delegate.onTap(p);
            }
            _dragging = false;
            _frame.value++;
            _wake();
          },
          onPointerCancel: (e) {
            if (e.pointer != _pointer) return;
            _pointer = null;
            if (_dragging) widget.delegate.onUp(_toScene(e.localPosition, size));
            _dragging = false;
            _frame.value++;
          },
          child: RepaintBoundary(
            child: CustomPaint(size: size, painter: _ScenePainter(this, _frame)),
          ),
        );
      },
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.state, Listenable repaint) : super(repaint: repaint);
  final _SceneViewState state;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = state._fit(size);
    final w = state.widget;
    canvas.save();
    canvas.translate(fit.origin.dx, fit.origin.dy);
    canvas.scale(fit.scale);
    w.delegate.paint(
      canvas,
      PaintContext(
        playback: w.playback,
        time: w.reduceMotion && w.playback != null ? w.playback!.timeline.duration : state._playTime,
        ghost: w.ghost,
        clock: state._clock,
        reduceMotion: w.reduceMotion,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter old) => true;
}
