import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/network/rpc.dart';
import '../../../core/widgets/common.dart';
import '../../catalog/domain/catalog.dart';
import '../domain/tournament.dart';

const entrantKinds = {'player': 'Singles (players)', 'pair': 'Doubles (pairs)', 'team': 'Teams'};
const eventCategories = {'open': 'Open', 'men': 'Men', 'women': 'Women', 'mixed': 'Mixed', 'junior': 'Junior'};

/// Creates or edits an event and its stage pipeline.
///
/// The pipeline is what the engine runs: each stage picks a format (the
/// pairing and ranking engines) and its options, and every stage after the
/// first says who advances into it. Pops with the document for
/// `org_event_save`, or null.
class EventFormPage extends StatefulWidget {
  const EventFormPage({super.key, required this.catalog, required this.sportCode, this.existing, required this.canChargeFees});

  final Catalog catalog;
  final String sportCode;
  final EventSummary? existing;
  final bool canChargeFees;

  @override
  State<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends State<EventFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _fee = TextEditingController(text: _number(widget.existing?.entryFee));
  late final _max = TextEditingController(text: widget.existing?.maxEntrants?.toString() ?? '');

  late String _rulesetKey;
  late String _entrantKind;
  late String _category;
  String? _templateKey;
  late List<StageSpec> _stages;

  List<Ruleset> get _rulesets => widget.catalog.rulesetsFor(widget.sportCode);
  List<FormatTemplate> get _templates => widget.catalog.templatesFor(widget.sportCode);

  static String _number(double? value) => value == null || value == 0 ? '' : (value == value.roundToDouble() ? value.toInt().toString() : value.toString());

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _rulesetKey = existing?.rulesetKey ?? _rulesets.first.key;
    _entrantKind = existing?.entrantKind ?? (_rulesets.first.isTeam ? 'team' : 'player');
    _category = existing?.category ?? 'open';
    _templateKey = existing?.templateKey;
    _stages = existing?.stages.map((s) => s.toSpec()).toList() ?? [];
    if (existing == null) _applyTemplate(_templates.first);
  }

  @override
  void dispose() {
    _name.dispose();
    _fee.dispose();
    _max.dispose();
    super.dispose();
  }

  void _applyTemplate(FormatTemplate template) {
    _templateKey = template.key;
    _stages = [...template.stages];
    final ruleset = widget.catalog.ruleset(template.rulesetKey);
    if (ruleset != null && ruleset.sportCode == widget.sportCode) {
      _rulesetKey = ruleset.key;
      if (ruleset.isTeam) _entrantKind = 'team';
    }
  }

  void _updateStage(int index, StageSpec stage) => setState(() {
    _stages[index] = stage;
    _templateKey = null; // no longer the preset as published
  });

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop<Json>(context, {
      'id': ?widget.existing?.id,
      'name': _name.text.trim(),
      'entrant_kind': _entrantKind,
      'category': _category,
      'ruleset_key': _rulesetKey,
      'template_key': _templateKey,
      'entry_fee': num.tryParse(_fee.text.trim()) ?? 0,
      'max_entrants': int.tryParse(_max.text.trim()),
      'stages': [for (final stage in _stages) stage.toJson()],
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ruleset = widget.catalog.ruleset(_rulesetKey);
    final template = _templates.where((t) => t.key == _templateKey).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New event' : 'Edit event'),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: FilledButton(onPressed: _submit, child: const Text('Save')))],
      ),
      body: Form(
        key: _formKey,
        child: ContentWidth(
          maxWidth: 720,
          child: ListView(
            padding: pagePadding,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Event name *', hintText: "Men's singles, U17 doubles, T20 cup"),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) => (value ?? '').trim().length < 2 ? 'Give the event a name' : null,
              ),
              Gap.md,
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _entrantKind,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Entrants'),
                      items: [for (final kind in entrantKinds.entries) DropdownMenuItem(value: kind.key, child: Text(kind.value, overflow: TextOverflow.ellipsis))],
                      onChanged: (value) => setState(() => _entrantKind = value!),
                    ),
                  ),
                  Gap.md,
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [for (final category in eventCategories.entries) DropdownMenuItem(value: category.key, child: Text(category.value))],
                      onChanged: (value) => setState(() => _category = value!),
                    ),
                  ),
                ],
              ),
              Gap.md,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fee,
                      enabled: widget.canChargeFees,
                      decoration: InputDecoration(
                        labelText: 'Entry fee',
                        helperText: widget.canChargeFees ? 'Empty for free entry' : 'Needs the "Paid tournament entries" feature',
                        helperMaxLines: 2,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    ),
                  ),
                  Gap.md,
                  Expanded(
                    child: TextFormField(
                      controller: _max,
                      decoration: const InputDecoration(labelText: 'Entrant limit', helperText: 'Extra entries are wait-listed'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        final n = int.tryParse((value ?? '').trim());
                        return (value ?? '').trim().isNotEmpty && (n == null || n < 2) ? 'At least 2' : null;
                      },
                    ),
                  ),
                ],
              ),
              const SectionHeader('Scoring'),
              DropdownButtonFormField<String>(
                key: ValueKey('ruleset-$_rulesetKey'),
                initialValue: _rulesetKey,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ruleset'),
                items: [
                  for (final r in _rulesets)
                    DropdownMenuItem(value: r.key, child: Text('${r.name}${r.governingBody == null ? '' : ' · ${r.governingBody}'}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => setState(() => _rulesetKey = value!),
              ),
              if (ruleset != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(ruleset.description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              const SectionHeader('Format'),
              DropdownButtonFormField<String?>(
                key: ValueKey('template-$_templateKey'),
                initialValue: _templateKey,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Start from a format'),
                items: [
                  const DropdownMenuItem<String?>(child: Text('Custom')),
                  for (final t in _templates)
                    DropdownMenuItem<String?>(
                      value: t.key,
                      child: Text('${t.name}${t.governingBody == null ? '' : ' · ${t.governingBody}'}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  final picked = _templates.where((t) => t.key == value).firstOrNull;
                  setState(() => picked == null ? _templateKey = null : _applyTemplate(picked));
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, bottom: 12),
                child: Text(
                  template?.description ?? 'Stages run in order. Each one seeds the next from its final standings.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              for (final (index, stage) in _stages.indexed)
                _StageEditor(
                  // Rebuild the editor when a template replaces the pipeline.
                  key: ValueKey('$index-${stage.format}-${_templateKey ?? 'custom'}-${_stages.length}'),
                  index: index,
                  stage: stage,
                  catalog: widget.catalog,
                  onChanged: (updated) => _updateStage(index, updated),
                  onRemove: _stages.length > 1
                      ? () => setState(() {
                          _stages.removeAt(index);
                          _templateKey = null;
                        })
                      : null,
                ),
              if (_stages.length < 6)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _stages.add(const StageSpec(name: 'Knockout', format: 'single_elimination', config: {'qualify': {'top': 4}}));
                      _templateKey = null;
                    }),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add a stage'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageEditor extends StatelessWidget {
  const _StageEditor({super.key, required this.index, required this.stage, required this.catalog, required this.onChanged, this.onRemove});

  final int index;
  final StageSpec stage;
  final Catalog catalog;
  final ValueChanged<StageSpec> onChanged;
  final VoidCallback? onRemove;

  void _set(String key, Object? value) {
    final config = {...stage.config};
    value == null ? config.remove(key) : config[key] = value;
    onChanged(stage.copyWith(config: config));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = catalog.format(stage.format);
    final qualify = stage.config['qualify'] is Map ? Map<String, dynamic>.from(stage.config['qualify'] as Map) : <String, dynamic>{};
    final perGroup = qualify.containsKey('per_group');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 13, child: Text('${index + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                  Gap.md,
                  Expanded(
                    child: TextFormField(
                      initialValue: stage.name,
                      decoration: const InputDecoration(labelText: 'Stage name', isDense: true),
                      onChanged: (value) => onChanged(stage.copyWith(name: value)),
                    ),
                  ),
                  if (onRemove != null) IconButton(tooltip: 'Remove stage', icon: const Icon(Icons.delete_outline), onPressed: onRemove),
                ],
              ),
              Gap.md,
              DropdownButtonFormField<String>(
                initialValue: stage.format,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Format'),
                items: [for (final f in catalog.stageFormats) DropdownMenuItem(value: f.key, child: Text(f.name))],
                onChanged: (value) {
                  // Options belong to a format; keep only who advances and the draw.
                  final kept = {
                    for (final key in const ['qualify', 'draw'])
                      if (stage.config.containsKey(key)) key: stage.config[key],
                  };
                  onChanged(stage.copyWith(format: value, config: kept));
                },
              ),
              if (format != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(format.description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              for (final option in format?.options ?? const <FormatOption>[])
                if (option.type == 'bool')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(option.label),
                    value: (stage.config[option.key] ?? option.defaultValue) == true,
                    onChanged: (value) => _set(option.key, value),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _IntField(
                      label: option.label,
                      value: (stage.config[option.key] ?? option.defaultValue) as num?,
                      min: option.min,
                      max: option.max,
                      onChanged: (value) => _set(option.key, value),
                    ),
                  ),
              if (index == 0)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Random draw for unseeded entrants'),
                  subtitle: const Text('Off: unseeded entrants are placed in order of entry'),
                  value: (stage.config['draw'] ?? 'random') == 'random',
                  onChanged: (value) => _set('draw', value ? 'random' : 'entry_order'),
                )
              else ...[
                Gap.md,
                Text('Who advances into this stage', style: theme.textTheme.labelLarge),
                Gap.sm,
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<bool>(
                        initialValue: perGroup,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: const [
                          DropdownMenuItem(value: true, child: Text('Top of each group')),
                          DropdownMenuItem(value: false, child: Text('Top of the table')),
                        ],
                        onChanged: (value) {
                          final count = (qualify['per_group'] ?? qualify['top'] ?? 2) as num;
                          _set('qualify', value! ? {'per_group': count} : {'top': count});
                        },
                      ),
                    ),
                    Gap.md,
                    Expanded(
                      flex: 2,
                      child: _IntField(
                        label: 'How many',
                        value: (qualify['per_group'] ?? qualify['top'] ?? 4) as num?,
                        min: 1,
                        max: 64,
                        onChanged: (value) => _set('qualify', {...qualify, perGroup ? 'per_group' : 'top': value ?? 2}),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IntField extends StatelessWidget {
  const _IntField({required this.label, required this.value, required this.onChanged, this.min, this.max});
  final String label;
  final num? value;
  final int? min;
  final int? max;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value?.toInt().toString() ?? '',
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (text) => onChanged(int.tryParse(text)),
      validator: (text) {
        final n = int.tryParse((text ?? '').trim());
        if ((text ?? '').trim().isEmpty) return null;
        if (n == null || (min != null && n < min!) || (max != null && n > max!)) {
          return '${min ?? 0} to ${max ?? 99}';
        }
        return null;
      },
    );
  }
}
