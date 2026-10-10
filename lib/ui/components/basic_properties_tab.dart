import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:blog_studio/ui/components/property_bindings.dart';

import 'package:blog_studio/ui/theme/property_style.dart';

class BasicPropertiesTab extends StatefulWidget {
  const BasicPropertiesTab({super.key, required this.data});
  final PropertyBindings data;
  @override
  State<BasicPropertiesTab> createState() => _BasicPropertiesTabState();
}

class _BasicPropertiesTabState extends State<BasicPropertiesTab> {
  final _controllers = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    for (final key in ['title', 'date', 'description']) {
      _controllers[key] = TextEditingController(
        text: widget.data.values[key]?.toString() ?? '',
      );
    }
  }

  @override
  void didUpdateWidget(covariant BasicPropertiesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final key in _controllers.keys) {
      final value = widget.data.values[key]?.toString() ?? '';
      if (_controllers[key]!.text != value) _controllers[key]!.text = value;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String label, {String? hint}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: propertyTextStyle.copyWith(
          fontSize: 12,
          color: const Color(0xff777777),
        ),
      ),
      const SizedBox(height: 8),
      Semantics(
        label: label,
        child: TextField(
          onTap: widget.data.onFocus,
          controller: _controllers[key],
          style: propertyTextStyle,
          decoration: InputDecoration(
            // Keep the label above the field, rather than on its outline.
            hintText: hint,
            hintStyle: propertyTextStyle.copyWith(
              color: const Color(0xffa0a0a0),
            ),
            filled: true,
            fillColor: const Color(0xfff7f7f7),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xffbdbdbd)),
            ),
          ),
          minLines: key == 'description'
              ? 4
              : key == 'title'
              ? 1
              : null,
          maxLines: key == 'description'
              ? 6
              : key == 'title'
              ? 3
              : 1,
          onChanged: (value) => widget.data.onChanged({
            key: ['tags', 'categories'].contains(key)
                ? value
                      .split(RegExp(r'[,，]'))
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toSet()
                      .toList()
                : value,
          }),
        ),
      ),
    ],
  );

  Widget _dialogTheme(BuildContext context, Widget child) =>
      Localizations.override(
        context: context,
        locale: const Locale('zh', 'CN'),
        delegates: GlobalMaterialLocalizations.delegates,
        child: Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(context).textTheme
                .apply(fontFamily: 'CupertinoSystemText'),
          ),
          child: child,
        ),
      );

  DateTime _date() =>
      DateTime.tryParse(
        _controllers['date']!.text.replaceFirst(
          RegExp(r'(Z|[+-]\d{2}:?\d{2})$'),
          '',
        ),
      ) ??
      DateTime.now();
  String _pad(int n) => n.toString().padLeft(2, '0');
  Future<void> _pickDate() async {
    widget.data.onFocus?.call();
    final current = _date();
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year < 1900 ? current.year : 1900),
      lastDate: DateTime(current.year > 2200 ? current.year + 1 : 2200, 12, 31),
      helpText: '选择文章日期',
      cancelText: '取消',
      confirmText: '确定',
      builder: (context, child) => _dialogTheme(context, child!),
    );
    if (selected == null || !mounted) return;
    final old = _controllers['date']!.text;
    final suffix = RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(old)
        ? old.substring(10)
        : ' ${_pad(current.hour)}:${_pad(current.minute)}:${_pad(current.second)}';
    _setDate(
      '${selected.year.toString().padLeft(4, '0')}-${_pad(selected.month)}-${_pad(selected.day)}$suffix',
    );
  }

  Future<void> _pickTime() async {
    widget.data.onFocus?.call();
    final current = _date();
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      initialEntryMode: TimePickerEntryMode.input,
      helpText: '选择文章时间',
      cancelText: '取消',
      confirmText: '确定',
      builder: (context, child) => _dialogTheme(
        context,
        MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final old = _controllers['date']!.text;
    final prefix = RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(old)
        ? old.substring(0, 10)
        : '${current.year}-${_pad(current.month)}-${_pad(current.day)}';
    final zone =
        RegExp(r'(Z|[+-]\d{2}:?\d{2})$').firstMatch(old)?.group(0) ?? '';
    _setDate(
      '$prefix ${_pad(selected.hour)}:${_pad(selected.minute)}:${_pad(current.second)}$zone',
    );
  }

  void _setDate(String value) {
    setState(() => _controllers['date']!.text = value);
    widget.data.onChanged({'date': value});
  }

  Widget _dateField() {
    final date = _date();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '日期与时间',
          style: propertyTextStyle.copyWith(
            fontSize: 12,
            color: const Color(0xff777777),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 15),
                label: Text(
                  '${date.year}-${_pad(date.month)}-${_pad(date.day)}',
                  style: propertyTextStyle,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _pickTime,
              child: Text(
                '${_pad(date.hour)}:${_pad(date.minute)}',
                style: propertyTextStyle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field('title', '标题', hint: '为文章起一个名字'),
      const SizedBox(height: 22),
      _dateField(),
      const SizedBox(height: 22),
      _field('description', '摘要', hint: '简短介绍这篇文章'),
    ],
  );
}
