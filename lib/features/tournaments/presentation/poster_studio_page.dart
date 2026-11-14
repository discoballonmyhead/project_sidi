import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme.dart';
import '../../../core/bloc/async_cubit.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../domain/tournament.dart';
import 'tournament_cubits.dart';
import 'widgets/poster_canvas.dart';

/// A starting design for a tournament: a promotion before it, a winners
/// poster once events have finished.
PosterSpec defaultPosterSpec(TournamentDetail detail, String kind) {
  final t = detail.tournament;
  final fee = t.minEntryFee;
  if (kind == 'winner') {
    return PosterSpec(
      kind: 'winner',
      template: 'classic',
      palette: 'emerald',
      sportCode: t.sportCode,
      title: t.name,
      headline: 'Champions',
      subtitle: Fmt.range(t.startsOn, t.endsOn),
      organizer: t.orgName,
      winners: [
        for (final event in detail.events.where((e) => e.podium.isNotEmpty))
          (
            event: event.name,
            first: event.podium.where((p) => p.rank == 1).firstOrNull?.name ?? '',
            second: event.podium.where((p) => p.rank == 2).firstOrNull?.name ?? '',
          ),
      ],
    );
  }
  return PosterSpec(
    kind: 'promotion',
    template: 'spotlight',
    palette: 'emerald',
    sportCode: t.sportCode,
    title: t.name,
    headline: 'Entries open',
    subtitle: Fmt.range(t.startsOn, t.endsOn),
    lines: [
      t.place,
      detail.events.map((e) => e.name).take(4).join(' · '),
      fee == null || fee == 0 ? 'Free entry' : 'Entry from ${Fmt.money(fee, t.currency)}',
      if (t.registrationClosesAt != null) 'Enter by ${Fmt.day(t.registrationClosesAt)}',
    ],
    cta: 'Enter on Sidi',
    organizer: t.orgName,
  );
}

/// Design a promotion or winners poster, then save it as a draft or publish
/// the rendered image to the tournament page.
class PosterStudioPage extends StatefulWidget {
  const PosterStudioPage({super.key, required this.cubit, required this.kind, this.poster});

  final TournamentDetailCubit cubit;
  final String kind;
  final Poster? poster;

  @override
  State<PosterStudioPage> createState() => _PosterStudioPageState();
}

class _PosterStudioPageState extends State<PosterStudioPage> {
  final _boundaryKey = GlobalKey();
  late PosterSpec _spec;
  late final TextEditingController _title;
  late final TextEditingController _headline;
  late final TextEditingController _subtitle;
  late final TextEditingController _lines;
  late final TextEditingController _cta;

  @override
  void initState() {
    super.initState();
    final poster = widget.poster;
    _spec = poster == null
        ? defaultPosterSpec(widget.cubit.state.data!, widget.kind)
        : PosterSpec.fromPayload(kind: poster.kind, template: poster.template, title: poster.title, payload: poster.payload);
    _title = TextEditingController(text: _spec.title);
    _headline = TextEditingController(text: _spec.headline);
    _subtitle = TextEditingController(text: _spec.subtitle);
    _lines = TextEditingController(text: _spec.lines.join('\n'));
    _cta = TextEditingController(text: _spec.cta);
  }

  @override
  void dispose() {
    for (final controller in [_title, _headline, _subtitle, _lines, _cta]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _sync() => setState(() {
    _spec = _spec.copyWith(
      title: _title.text.trim(),
      headline: _headline.text.trim(),
      subtitle: _subtitle.text.trim(),
      lines: _lines.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList(),
      cta: _cta.text.trim(),
    );
  });

  Future<void> _save({required bool publish}) async {
    if (_spec.title.isEmpty) {
      widget.cubit.say('Give the poster a title.', isError: true);
      return;
    }
    final navigator = Navigator.of(context);
    final png = publish ? await _render() : null;
    final ok = await widget.cubit.savePoster({
      'id': ?widget.poster?.id,
      'kind': _spec.kind,
      'template': _spec.template,
      'title': _spec.title,
      'payload': _spec.toPayload(),
    }, png: png);
    if (ok) navigator.pop();
  }

  /// Rasterises the preview at the poster's full design resolution.
  Future<Uint8List?> _render() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: PosterCanvas.designSize.width / boundary.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final winner = _spec.kind == 'winner';
    final preview = RepaintBoundary(key: _boundaryKey, child: PosterCanvas(_spec));
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Layout', style: Theme.of(context).textTheme.labelLarge),
        Gap.sm,
        Wrap(
          spacing: 8,
          children: [
            for (final template in posterTemplates.entries)
              ChoiceChip(
                label: Text(template.value),
                selected: _spec.template == template.key,
                onSelected: (_) => setState(() => _spec = _spec.copyWith(template: template.key)),
              ),
          ],
        ),
        Gap.lg,
        Text('Colours', style: Theme.of(context).textTheme.labelLarge),
        Gap.sm,
        Wrap(
          spacing: 10,
          children: [
            for (final palette in posterPalettes.entries)
              Tooltip(
                message: Fmt.label(palette.key),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _spec = _spec.copyWith(palette: palette.key)),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [palette.value.mid, palette.value.accent], stops: const [0.5, 0.5]),
                      border: Border.all(
                        width: 3,
                        color: _spec.palette == palette.key ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Gap.lg,
        TextField(controller: _title, onChanged: (_) => _sync(), decoration: const InputDecoration(labelText: 'Title')),
        Gap.md,
        TextField(controller: _headline, onChanged: (_) => _sync(), decoration: const InputDecoration(labelText: 'Tag line', hintText: 'Entries open')),
        Gap.md,
        TextField(controller: _subtitle, onChanged: (_) => _sync(), decoration: const InputDecoration(labelText: 'Subtitle', hintText: 'Dates')),
        if (!winner) ...[
          Gap.md,
          TextField(
            controller: _lines,
            onChanged: (_) => _sync(),
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Details', helperText: 'One per line, up to five: venue, events, fee, prizes.'),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _spec.winners.isEmpty
                  ? 'No event has finished yet, so there are no winners to show. Results fill in automatically.'
                  : 'Winners come from the final standings of ${_spec.winners.length} finished event${_spec.winners.length == 1 ? '' : 's'}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Gap.md,
        TextField(controller: _cta, onChanged: (_) => _sync(), decoration: const InputDecoration(labelText: 'Button text', hintText: 'Enter on Sidi')),
      ],
    );

    return BlocProvider.value(
      value: widget.cubit,
      child: BlocConsumer<TournamentDetailCubit, AsyncState<TournamentDetail>>(
        listenWhen: (previous, current) => previous.notice != current.notice && current.notice != null,
        listener: (context, state) => showNotice(context, state.notice!),
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: Text(winner ? 'Winners poster' : 'Promotion poster'),
            actions: [
              TextButton(onPressed: state.busy ? null : () => _save(publish: false), child: const Text('Save draft')),
              Padding(
                padding: const EdgeInsets.only(right: 12, left: 4),
                child: FilledButton(onPressed: state.busy ? null : () => _save(publish: true), child: const Text('Publish')),
              ),
            ],
            bottom: state.busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
          ),
          body: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 820
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: preview))),
                      SizedBox(width: 380, child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: controls)),
                    ],
                  )
                : ListView(
                    padding: pagePadding,
                    children: [
                      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: preview)),
                      Gap.lg,
                      controls,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// A poster as shown on the tournament page: the published image when there
/// is one, otherwise the live design.
class PosterThumb extends StatelessWidget {
  const PosterThumb(this.poster, {super.key});
  final Poster poster;

  @override
  Widget build(BuildContext context) {
    final design = PosterCanvas(PosterSpec.fromPayload(kind: poster.kind, template: poster.template, title: poster.title, payload: poster.payload));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: poster.imageUrl == null
          ? design
          : AspectRatio(
              aspectRatio: PosterCanvas.designSize.width / PosterCanvas.designSize.height,
              child: Image.network(poster.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => design),
            ),
    );
  }
}

/// Used by callers that only need the type for a status chip next to a thumb.
Widget posterStatus(Poster poster) => StatusChip(poster.isPublished ? 'open' : 'draft', label: poster.isPublished ? 'Published' : 'Draft');
