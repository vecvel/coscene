import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'game/game_state.dart';
import 'screens/home_screen.dart';
import 'services/save_store.dart';
import 'ui/kit.dart';

class CosceneApp extends StatefulWidget {
  const CosceneApp({super.key, this.store});

  /// Where progress is saved. Tests pass a memory store.
  final SaveStore? store;

  @override
  State<CosceneApp> createState() => _CosceneAppState();
}

class _CosceneAppState extends State<CosceneApp> {
  GameState? _game;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final game = await GameState.load(
      widget.store ?? SecureSaveStore(),
      deviceLanguages: PlatformDispatcher.instance.locales.map((l) => l.languageCode),
    );
    if (!mounted) return;
    setState(() => _game = game);
    // Neither of these blocks the first screen.
    game.audio.prepare();
    getApplicationSupportDirectory().then((dir) => game.syncPacks(Directory('${dir.path}/packs'))).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    return MaterialApp(
      title: 'coscene',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Palette.cream,
        colorScheme: const ColorScheme.light(
          primary: Palette.ink,
          onPrimary: Palette.cream,
          secondary: Palette.orange,
          surface: Palette.cream,
          onSurface: Palette.ink,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Palette.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Palette.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      builder: (context, child) {
        // Large system text is welcome, but past this the scenes lose room.
        final page = MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!);
        if (game == null) return page;
        return GameScope(
          game: game,
          child: ListenableBuilder(
            listenable: game,
            // Naming the language lets the system pick the right glyphs
            // for each script from the fonts already on the phone.
            builder: (context, _) => DefaultTextStyle.merge(
              style: TextStyle(locale: Locale(game.language)),
              child: page,
            ),
          ),
        );
      },
      home: const _Root(),
    );
  }
}

/// Shows the mark while the save loads, then the home screen.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> with SingleTickerProviderStateMixin {
  // The last stretch of the logo's intro: the glasses drop on and it blinks.
  static const double _from = 5.3;
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.maybeOf(context);
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, _) {
        if (game != null && (_intro.isCompleted || game.reduceMotion)) return const HomeScreen();
        return ColoredBox(
          color: Palette.orange,
          child: Center(
            child: CustomPaint(
              size: const Size.square(168),
              painter: LogoPainter(time: _from + _intro.value * (Logo.introSeconds - _from), background: false),
            ),
          ),
        );
      },
    );
  }
}
