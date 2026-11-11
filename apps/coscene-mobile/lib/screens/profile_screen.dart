import 'dart:io';
import 'dart:ui' as ui;

import 'package:coscene_core/coscene_core.dart';
import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../game/game_state.dart';
import '../ui/kit.dart';

/// What goes on the share card.
class CardData {
  const CardData({
    required this.name,
    required this.score,
    required this.rank,
    required this.stats,
    required this.caption,
    required this.language,
  });

  factory CardData.of(GameState game) => CardData(
    name: game.name.trim().isEmpty ? game.t('ui.profile_name_default') : game.name.trim(),
    score: game.score,
    rank: game.t('rank.${game.rank}'),
    stats: [
      ('${game.totalSolved}', game.t('card.scenes')),
      ('${game.totalStars}', game.t('card.stars')),
      ('${game.foundConcepts.length}', game.t('card.ideas')),
    ],
    caption: game.t('card.caption'),
    language: game.language,
  );

  final String name;
  final int score;
  final String rank;
  final List<(String, String)> stats;
  final String caption;
  final String language;
}

/// The shareable card: the mascot on top, the score underneath. Drawn on a
/// 1080 by 1350 canvas and scaled to whatever size it is shown at.
class ShareCardPainter extends CustomPainter {
  ShareCardPainter(this.data);
  final CardData data;

  static const Size cardSize = Size(1080, 1350);

  void _text(
    Canvas canvas,
    String text,
    double centerX,
    double top, {
    required double size,
    Color color = Palette.ink,
    FontWeight weight = FontWeight.w600,
    double maxWidth = 960,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.1, locale: Locale(data.language)),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(centerX - painter.width / 2, top));
    painter.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / cardSize.width);
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & cardSize, const Radius.circular(64)));
    canvas.drawRect(Offset.zero & cardSize, Paint()..color = Palette.white);

    // The mark, widened past its square so the wave runs edge to edge.
    Logo.paint(canvas, const Rect.fromLTWH(140, 20, 800, 800), bleed: 24);

    _text(canvas, data.name, 540, 770, size: 46, color: Palette.inkSoft, weight: FontWeight.w500);
    _text(canvas, 'cosIQ', 540, 850, size: 44, color: Palette.orange, weight: FontWeight.w700);
    _text(canvas, '${data.score}', 540, 890, size: 210, weight: FontWeight.w800);

    // Rank, on a dark pill.
    final rank = TextPainter(
      text: TextSpan(
        text: data.rank,
        style: TextStyle(
          fontSize: 44,
          color: Palette.cream,
          fontWeight: FontWeight.w600,
          height: 1.1,
          locale: Locale(data.language),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 820);
    final pill = Rect.fromCenter(center: const Offset(540, 1160), width: rank.width + 80, height: 84);
    canvas.drawRRect(RRect.fromRectAndRadius(pill, const Radius.circular(42)), Paint()..color = Palette.ink);
    rank.paint(canvas, Offset(540 - rank.width / 2, 1160 - rank.height / 2));
    rank.dispose();

    final line = [for (final (value, label) in data.stats) '$value $label'].join('   ·   ');
    _text(canvas, line, 540, 1230, size: 34, color: Palette.inkSoft, weight: FontWeight.w500);
    _text(canvas, 'coscene  ·  ${data.caption}', 540, 1290, size: 28, color: Palette.stone, weight: FontWeight.w500);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ShareCardPainter old) => true;
}

/// Renders the card to a PNG file and returns it.
Future<File> renderShareCard(CardData data) async {
  final recorder = ui.PictureRecorder();
  ShareCardPainter(data).paint(Canvas(recorder), ShareCardPainter.cardSize);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    ShareCardPainter.cardSize.width.toInt(),
    ShareCardPainter.cardSize.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/coscene-card.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  TextEditingController? _name;
  final _shareKey = GlobalKey();
  bool _sharing = false;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  Future<void> _share(GameState game) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final file = await renderShareCard(CardData.of(game));
      // iPad needs to know where to anchor the share sheet.
      final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: game.t('ui.profile_share_text', {'score': game.score}),
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final name = _name ??= TextEditingController(text: game.name);
    final toNext = pointsToNextRank(game.score);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(title: game.t('ui.profile')),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 4, 16, scrollEndPadding(context)),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: AspectRatio(
                        aspectRatio: ShareCardPainter.cardSize.aspectRatio,
                        child: CustomPaint(painter: ShareCardPainter(CardData.of(game))),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PressButton(
                    key: _shareKey,
                    label: game.t('ui.profile_share'),
                    icon: GameIcons.share,
                    color: Palette.orange,
                    foreground: Palette.white,
                    onTap: _sharing ? null : () => _share(game),
                  ),
                  const SizedBox(height: 20),
                  Text(game.t('ui.profile_name'), style: Type.label),
                  const SizedBox(height: 6),
                  TextField(
                    controller: name,
                    maxLength: 24,
                    textCapitalization: TextCapitalization.words,
                    style: Type.body,
                    cursorColor: Palette.ink,
                    decoration: InputDecoration(
                      hintText: game.t('ui.profile_name_default'),
                      hintStyle: Type.soft,
                      counterText: '',
                      filled: true,
                      fillColor: Palette.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) => game.update(() => game.name = v),
                  ),
                  const SizedBox(height: 16),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Stat(game.t('ui.profile_rank'), game.t('rank.${game.rank}')),
                        _Stat(game.t('ui.profile_solved'), '${game.totalSolved} / ${game.registry.count}'),
                        _Stat(game.t('ui.profile_stars'), '${game.totalStars} / ${game.registry.count * 3}'),
                        _Stat(game.t('ui.profile_ideas'), '${game.foundConcepts.length} / ${game.allConcepts.length}'),
                        _Stat(game.t('ui.profile_streak'), '${game.currentStreak}'),
                        const SizedBox(height: 6),
                        Text(
                          toNext == null
                              ? game.t('ui.profile_top_rank')
                              : game.t('ui.profile_next_rank', {
                                  'points': toNext,
                                  'rank': game.t('rank.${game.rank + 1}'),
                                }),
                          style: Type.soft,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(game.t('ui.profile_score_note'), style: Type.soft),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: Type.body)),
        Text(value, style: Type.body.copyWith(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
