import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../network/rpc.dart';
import '../utils/format.dart';
import '../utils/json.dart';

enum FieldKind { text, multiline, number, integer, choice, multiChoice, toggle, date, dateTime }

/// One input of a [showFormSheet] form. The value lands under [key] in the
/// returned document, in the shape the backend RPCs expect.
class FieldSpec {
  const FieldSpec.text(this.key, this.label, {this.initial, this.required = false, this.hint, this.helper})
    : kind = FieldKind.text,
      options = const {};

  const FieldSpec.multiline(this.key, this.label, {this.initial, this.required = false, this.hint, this.helper})
    : kind = FieldKind.multiline,
      options = const {};

  const FieldSpec.number(this.key, this.label, {this.initial, this.required = false, this.hint, this.helper})
    : kind = FieldKind.number,
      options = const {};

  const FieldSpec.integer(this.key, this.label, {this.initial, this.required = false, this.hint, this.helper})
    : kind = FieldKind.integer,
      options = const {};

  const FieldSpec.choice(this.key, this.label, this.options, {this.initial, this.required = true, this.helper})
    : kind = FieldKind.choice,
      hint = null;

  const FieldSpec.multiChoice(this.key, this.label, this.options, {this.initial, this.required = false, this.helper})
    : kind = FieldKind.multiChoice,
      hint = null;

  const FieldSpec.toggle(this.key, this.label, {this.initial = false, this.helper})
    : kind = FieldKind.toggle,
      options = const {},
      required = false,
      hint = null;

  const FieldSpec.date(this.key, this.label, {this.initial, this.required = false, this.helper})
    : kind = FieldKind.date,
      options = const {},
      hint = null;

  const FieldSpec.dateTime(this.key, this.label, {this.initial, this.required = false, this.helper})
    : kind = FieldKind.dateTime,
      options = const {},
      hint = null;

  final String key;
  final String label;
  final FieldKind kind;

  /// String / num for text and numbers, option key for a choice, a list of
  /// keys for a multi-choice, bool for a toggle, DateTime for dates.
  final Object? initial;
  final bool required;
  final String? hint;
  final String? helper;

  /// value → label, for choices.
  final Map<String, String> options;
}

/// Opens a bottom sheet with the given fields and returns the entered values,
/// or null when dismissed. Text is trimmed and blank becomes null; dates are
/// `yyyy-MM-dd`; date-times are ISO-8601 in UTC.
Future<Json?> showFormSheet(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  String submitLabel = 'Save',
  String? description,
}) {
  return showModalBottomSheet<Json>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _FormSheet(title: title, fields: fields, submitLabel: submitLabel, description: description),
  );
}

class _FormSheet extends StatefulWidget {
  const _FormSheet({required this.title, required this.fields, required this.submitLabel, this.description});

  final String title;
  final List<FieldSpec> fields;
  final String submitLabel;
  final String? description;

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _values = <String, Object?>{};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      switch (field.kind) {
        case FieldKind.text || FieldKind.multiline || FieldKind.number || FieldKind.integer:
          final initial = field.initial;
          _controllers[field.key] = TextEditingController(text: initial is num ? Fmt.number(initial) : initial?.toString() ?? '');
        case FieldKind.multiChoice:
          _values[field.key] = {...?(field.initial as Iterable<String>?)};
        case FieldKind.toggle:
          _values[field.key] = field.initial == true;
        default:
          _values[field.key] = field.initial;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final result = <String, dynamic>{};
    for (final field in widget.fields) {
      final text = _controllers[field.key]?.text.trim() ?? '';
      result[field.key] = switch (field.kind) {
        FieldKind.text || FieldKind.multiline => text.isEmpty ? null : text,
        FieldKind.number => text.isEmpty ? null : num.tryParse(text),
        FieldKind.integer => text.isEmpty ? null : int.tryParse(text),
        FieldKind.multiChoice => (_values[field.key]! as Set<String>).toList(),
        FieldKind.date => _values[field.key] == null ? null : isoDay(_values[field.key]! as DateTime),
        FieldKind.dateTime => (_values[field.key] as DateTime?)?.toUtc().toIso8601String(),
        FieldKind.choice || FieldKind.toggle => _values[field.key],
      };
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (widget.description != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(widget.description!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 16),
            for (final field in widget.fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: _buildField(field)),
            const SizedBox(height: 4),
            FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
          ],
        ),
      ),
    );
  }

  Widget _buildField(FieldSpec field) {
    final label = field.required ? '${field.label} *' : field.label;
    switch (field.kind) {
      case FieldKind.text || FieldKind.multiline:
        return TextFormField(
          controller: _controllers[field.key],
          decoration: InputDecoration(labelText: label, hintText: field.hint, helperText: field.helper, helperMaxLines: 3),
          maxLines: field.kind == FieldKind.multiline ? 4 : 1,
          minLines: field.kind == FieldKind.multiline ? 2 : 1,
          textCapitalization: TextCapitalization.sentences,
          validator: (value) => field.required && (value == null || value.trim().isEmpty) ? 'Required' : null,
        );
      case FieldKind.number || FieldKind.integer:
        final integer = field.kind == FieldKind.integer;
        return TextFormField(
          controller: _controllers[field.key],
          decoration: InputDecoration(labelText: label, hintText: field.hint, helperText: field.helper, helperMaxLines: 3),
          keyboardType: TextInputType.numberWithOptions(decimal: !integer),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(integer ? r'[0-9]' : r'[0-9.]'))],
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return field.required ? 'Required' : null;
            return num.tryParse(text) == null ? 'Enter a number' : null;
          },
        );
      case FieldKind.choice:
        return DropdownButtonFormField<String>(
          initialValue: field.options.containsKey(_values[field.key]) ? _values[field.key] as String? : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, helperText: field.helper, helperMaxLines: 3),
          items: [
            if (!field.required) const DropdownMenuItem<String>(child: Text('None')),
            for (final option in field.options.entries)
              DropdownMenuItem(value: option.key, child: Text(option.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (value) => setState(() => _values[field.key] = value),
          validator: (value) => field.required && value == null ? 'Required' : null,
        );
      case FieldKind.multiChoice:
        final selected = _values[field.key]! as Set<String>;
        return FormField<Set<String>>(
          validator: (_) => field.required && selected.isEmpty ? 'Pick at least one' : null,
          builder: (state) => InputDecorator(
            decoration: InputDecoration(labelText: label, errorText: state.errorText, helperText: field.helper),
            child: Wrap(
              spacing: 8,
              children: [
                for (final option in field.options.entries)
                  FilterChip(
                    label: Text(option.value),
                    selected: selected.contains(option.key),
                    onSelected: (on) => setState(() => on ? selected.add(option.key) : selected.remove(option.key)),
                  ),
              ],
            ),
          ),
        );
      case FieldKind.toggle:
        return SwitchListTile(
          value: _values[field.key] == true,
          onChanged: (value) => setState(() => _values[field.key] = value),
          title: Text(field.label),
          subtitle: field.helper == null ? null : Text(field.helper!),
          contentPadding: EdgeInsets.zero,
        );
      case FieldKind.date || FieldKind.dateTime:
        final value = _values[field.key] as DateTime?;
        final withTime = field.kind == FieldKind.dateTime;
        return FormField<DateTime>(
          validator: (_) => field.required && _values[field.key] == null ? 'Required' : null,
          builder: (state) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pickDate(field, withTime),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                helperText: field.helper,
                errorText: state.errorText,
                suffixIcon: value != null && !field.required
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _values[field.key] = null))
                    : const Icon(Icons.calendar_today_outlined, size: 18),
              ),
              child: Text(value == null ? 'Not set' : (withTime ? Fmt.dayTime(value) : Fmt.dayYear(value))),
            ),
          ),
        );
    }
  }

  Future<void> _pickDate(FieldSpec field, bool withTime) async {
    final current = _values[field.key] as DateTime? ?? DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (day == null || !mounted) return;
    var picked = day;
    if (withTime) {
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
      if (time == null) return;
      picked = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    }
    setState(() => _values[field.key] = picked);
  }
}
