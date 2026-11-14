import 'package:flutter/material.dart';

import '../../../../core/network/rpc.dart';
import '../../../../core/widgets/common.dart';

/// Everything a poster shows. Stored as the poster's `payload`.
class PosterSpec {
  const PosterSpec({
    required this.kind,
    required this.template,
    required this.palette,
    required this.sportCode,
    required this.title,
    this.headline = '',
    this.subtitle = '',
    this.lines = const [],
    this.cta = '',
    this.organizer = '',
    this.winners = const [],
  });

  /// `promotion` or `winner`.
  final String kind;

  /// `spotlight`, `bold` or `classic`.
  final String template;
  final String palette;
  final String sportCode;
  final String title;
  final String headline;
  final String subtitle;

  /// Detail lines: dates, venue, entry fee, prize.
  final List<String> lines;
  final String cta;
  final String organizer;

  /// For winner posters: one row per event.
  final List<({String event, String first, String second})> winners;

  Json toPayload() => {
    'palette': palette,
    'sport_code': sportCode,
    'headline': headline,
    'subtitle': subtitle,
    'lines': lines,
    'cta': cta,
    'organizer': organizer,
    'winners': [
      for (final w in winners) {'event': w.event, 'first': w.first, 'second': w.second},
    ],
  };

  factory PosterSpec.fromPayload({required String kind, required String template, required String title, required Json payload}) {
    final winners = payload['winners'];
    final lines = payload['lines'];
    return PosterSpec(
      kind: kind,
      template: template,
      title: title,
      palette: payload['palette']?.toString() ?? 'emerald',
      sportCode: payload['sport_code']?.toString() ?? '',
      headline: payload['headline']?.toString() ?? '',
      subtitle: payload['subtitle']?.toString() ?? '',
      lines: lines is List ? [for (final line in lines) line.toString()] : const [],
      cta: payload['cta']?.toString() ?? '',
      organizer: payload['organizer']?.toString() ?? '',
      winners: winners is List
          ? [
              for (final w in winners.whereType<Map>())
                (event: w['event']?.toString() ?? '', first: w['first']?.toString() ?? '', second: w['second']?.toString() ?? ''),
            ]
          : const [],
    );
  }

  PosterSpec copyWith({
    String? template,
    String? palette,
    String? title,
    String? headline,
    String? subtitle,
    List<String>? lines,
    String? cta,
  }) => PosterSpec(
    kind: kind,
    template: template ?? this.template,
    palette: palette ?? this.palette,
    sportCode: sportCode,
    title: title ?? this.title,
    headline: headline ?? this.headline,
    subtitle: subtitle ?? this.subtitle,
    lines: lines ?? this.lines,
    cta: cta ?? this.cta,
    organizer: organizer,
    winners: winners,
  );
}

typedef PosterPalette = ({Color dark, Color mid, Color accent});

const posterPalettes = <String, PosterPalette>{
  'emerald': (dark: Color(0xFF04342A), mid: Color(0xFF0B6E4F), accent: Color(0xFFF2C94C)),
  'midnight': (dark: Color(0xFF0B1026), mid: Color(0xFF27357E), accent: Color(0xFF56CCF2)),
  'sunset': (dark: Color(0xFF3B0A1E), mid: Color(0xFFC0392B), accent: Color(0xFFFFD166)),
  'royal': (dark: Color(0xFF1F0B3A), mid: Color(0xFF6A3FB5), accent: Color(0xFFFF8FA3)),
  'slate': (dark: Color(0xFF111418), mid: Color(0xFF39424E), accent: Color(0xFFFF6B35)),
};

const posterTemplates = {'spotlight': 'Spotlight', 'bold': 'Bold', 'classic': 'Classic'};

/// Renders a poster at a fixed 4:5 design size and scales it to fit, so the
/// preview and the exported image are the same picture.
class PosterCanvas extends StatelessWidget {
  const PosterCanvas(this.spec, {super.key});
  final PosterSpec spec;

  static const designSize = Size(1080, 1350);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: designSize.width / designSize.height,
      child: FittedBox(
        child: SizedBox.fromSize(
          size: designSize,
          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'Roboto', color: Colors.white, height: 1.1),
            child: switch (spec.template) {
              'bold' => _Bold(spec),
              'classic' => _Classic(spec),
              _ => _Spotlight(spec),
            },
          ),
        ),
      ),
    );
  }
}

PosterPalette _paletteOf(PosterSpec spec) => posterPalettes[spec.palette] ?? posterPalettes['emerald']!;

/// The body shared by every template: details for a promotion, a results
/// table for a winner poster.
class _Details extends StatelessWidget {
  const _Details(this.spec, {required this.color, required this.accent, this.align = CrossAxisAlignment.start});
  final PosterSpec spec;
  final Color color;
  final Color accent;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    if (spec.kind == 'winner' && spec.winners.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final winner in spec.winners.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.emoji_events_rounded, color: accent, size: 64),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(winner.event.toUpperCase(), style: TextStyle(fontSize: 26, letterSpacing: 3, color: color.withValues(alpha: 0.75))),
                        const SizedBox(height: 6),
                        Text(winner.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 52, fontWeight: FontWeight.w800, color: color)),
                        if (winner.second.isNotEmpty)
                          Text('Runner-up · ${winner.second}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 28, color: color.withValues(alpha: 0.8))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: align,
      children: [
        for (final line in spec.lines.where((l) => l.trim().isNotEmpty).take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: align == CrossAxisAlignment.center ? TextAlign.center : TextAlign.start,
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w500, color: color),
            ),
          ),
      ],
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta(this.text, {required this.background, required this.foreground});
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 22),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(60)),
    child: Text(text.toUpperCase(), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 2, color: foreground)),
  );
}

class _Spotlight extends StatelessWidget {
  const _Spotlight(this.spec);
  final PosterSpec spec;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteOf(spec);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [palette.mid, palette.dark]),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -160,
            top: -120,
            child: Icon(sportStyle(spec.sportCode).icon, size: 760, color: Colors.white.withValues(alpha: 0.07)),
          ),
          Padding(
            padding: const EdgeInsets.all(84),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (spec.headline.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                    decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      spec.headline.toUpperCase(),
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 3, color: palette.dark),
                    ),
                  ),
                const SizedBox(height: 44),
                Text(spec.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 112, fontWeight: FontWeight.w900, height: 0.98)),
                if (spec.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(spec.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 44, color: palette.accent, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 56),
                Container(width: 120, height: 8, color: palette.accent),
                const SizedBox(height: 56),
                Expanded(child: _Details(spec, color: Colors.white, accent: palette.accent)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: Text(spec.organizer, maxLines: 2, style: TextStyle(fontSize: 32, color: Colors.white.withValues(alpha: 0.8)))),
                    if (spec.cta.isNotEmpty) _Cta(spec.cta, background: palette.accent, foreground: palette.dark),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bold extends StatelessWidget {
  const _Bold(this.spec);
  final PosterSpec spec;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteOf(spec);
    return ColoredBox(
      color: palette.dark,
      child: Stack(
        children: [
          Positioned(left: 0, top: 0, bottom: 0, width: 48, child: ColoredBox(color: palette.accent)),
          Positioned(
            right: -80,
            bottom: 260,
            child: Transform.rotate(angle: -0.2, child: Icon(sportStyle(spec.sportCode).icon, size: 520, color: palette.mid.withValues(alpha: 0.55))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(130, 96, 84, 84),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.headline.toUpperCase(), style: TextStyle(fontSize: 34, letterSpacing: 8, fontWeight: FontWeight.w700, color: palette.accent)),
                const SizedBox(height: 36),
                Text(
                  spec.title.toUpperCase(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 128, fontWeight: FontWeight.w900, height: 0.92, letterSpacing: -2),
                ),
                if (spec.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text(spec.subtitle, maxLines: 2, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w300)),
                ],
                const SizedBox(height: 60),
                Expanded(child: _Details(spec, color: Colors.white, accent: palette.accent)),
                if (spec.cta.isNotEmpty) _Cta(spec.cta, background: Colors.white, foreground: palette.dark),
                const SizedBox(height: 32),
                Text(spec.organizer.toUpperCase(), style: TextStyle(fontSize: 28, letterSpacing: 4, color: Colors.white.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Classic extends StatelessWidget {
  const _Classic(this.spec);
  final PosterSpec spec;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteOf(spec);
    const paper = Color(0xFFFBF7EE);
    return ColoredBox(
      color: paper,
      child: Padding(
        padding: const EdgeInsets.all(44),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: palette.mid, width: 6)),
          child: Padding(
            padding: const EdgeInsets.all(64),
            child: Column(
              children: [
                Icon(spec.kind == 'winner' ? Icons.emoji_events_rounded : sportStyle(spec.sportCode).icon, size: 150, color: palette.mid),
                const SizedBox(height: 28),
                if (spec.headline.isNotEmpty)
                  Text(spec.headline.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: 32, letterSpacing: 10, color: palette.mid)),
                const SizedBox(height: 30),
                Text(
                  spec.title,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 100, fontWeight: FontWeight.w800, color: palette.dark, height: 1.02),
                ),
                if (spec.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(spec.subtitle, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 42, fontStyle: FontStyle.italic, color: palette.mid)),
                ],
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 90, height: 3, color: palette.mid),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Icon(Icons.star_rounded, color: palette.mid, size: 36)),
                    Container(width: 90, height: 3, color: palette.mid),
                  ],
                ),
                const SizedBox(height: 44),
                Expanded(child: _Details(spec, color: palette.dark, accent: palette.mid, align: CrossAxisAlignment.center)),
                if (spec.cta.isNotEmpty) _Cta(spec.cta, background: palette.mid, foreground: paper),
                const SizedBox(height: 28),
                Text(spec.organizer, textAlign: TextAlign.center, style: TextStyle(fontSize: 30, color: palette.dark.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
