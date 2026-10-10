import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'package:blog_studio/models/studio_exception.dart';

class FrontMatterDocument {
  FrontMatterDocument._(
    this.source,
    this.body,
    this.yamlSource,
    this.prefix,
    this.suffix,
    this.fields,
    this.nodes,
    this.newline,
  );
  final String source, body, yamlSource, prefix, suffix, newline;
  final Map<String, dynamic> fields;
  final YamlMap? nodes;

  factory FrontMatterDocument.parse(String source) {
    final start = RegExp(r'^\uFEFF?---\r?\n').firstMatch(source);
    if (start == null) {
      return FrontMatterDocument._(
        source,
        source,
        '',
        '',
        '',
        {},
        null,
        source.contains('\r\n') ? '\r\n' : '\n',
      );
    }
    final end = RegExp(
      r'^---[ \t]*(?:\r?\n|$)',
      multiLine: true,
    ).firstMatch(source.substring(start.end));
    if (end == null) {
      throw const StudioException(
        StudioError.invalidMetadata,
        '文章属性缺少结束的 ---，请先修复原文件。',
      );
    }
    final yaml = source.substring(start.end, start.end + end.start);
    try {
      final node = loadYamlNode(yaml);
      if (node is! YamlMap && node.value != null) throw const FormatException();
      final map = node is YamlMap ? node : null;
      final fields = <String, dynamic>{};
      map?.forEach((key, value) {
        if (key is! String) throw const FormatException();
        fields[key] = value;
      });
      return FrontMatterDocument._(
        source,
        source.substring(start.end + end.end),
        yaml,
        source.substring(0, start.end),
        source.substring(start.end + end.start, start.end + end.end),
        fields,
        map,
        source.contains('\r\n') ? '\r\n' : '\n',
      );
    } catch (_) {
      throw const StudioException(
        StudioError.invalidMetadata,
        '文章 YAML 属性无法解析，未修改原文件。',
      );
    }
  }

  String encode(String body, Map<String, dynamic> changes) {
    final closing = suffix.endsWith('\n') || body.isEmpty
        ? suffix
        : '$suffix$newline';
    if (changes.isEmpty) {
      return prefix.isEmpty ? body : '$prefix$yamlSource$closing$body';
    }
    if (prefix.isEmpty) {
      return '---$newline${changes.entries.map((e) => '${e.key}: ${jsonEncode(e.value)}$newline').join()}---$newline$body';
    }
    var yaml = yamlSource;
    final edits = <({int start, int end, String text})>[];
    final append = StringBuffer();
    for (final entry in changes.entries) {
      if (jsonEncode(fields[entry.key]) == jsonEncode(entry.value)) continue;
      YamlNode? keyNode;
      YamlNode? valueNode;
      nodes?.nodes.forEach((key, value) {
        if (key.value == entry.key) {
          keyNode = key;
          valueNode = value;
        }
      });
      final line = '${entry.key}: ${jsonEncode(entry.value)}$newline';
      if (keyNode == null) {
        append.write(line);
        continue;
      }
      // Flow maps, aliases and complex keys cannot be safely patched as lines.
      final begin = keyNode!.span.start.offset;
      if (keyNode!.span.start.column != 0 ||
          RegExp(r'(^|\s)[&*][\w-]+', multiLine: true).hasMatch(yamlSource)) {
        throw const StudioException(
          StudioError.invalidMetadata,
          '此属性使用复杂 YAML 结构，请在原文件中修改；正文仍可正常保存。',
        );
      }
      var end = valueNode!.span.end.offset;
      if (valueNode!.span.end.column != 0 || end == begin) {
        final next = yamlSource.indexOf('\n', end);
        end = next < 0 ? yamlSource.length : next + 1;
      }
      edits.add((start: begin, end: end, text: line));
    }
    edits.sort((a, b) => b.start.compareTo(a.start));
    for (final edit in edits) {
      yaml = yaml.replaceRange(edit.start, edit.end, edit.text);
    }
    if (append.isNotEmpty) {
      if (yaml.isNotEmpty && !yaml.endsWith('\n')) yaml += newline;
      yaml += append.toString();
    }
    // Reject accidental changes to neighboring fields before reaching disk.
    final result = '$prefix$yaml$closing$body';
    final parsed = FrontMatterDocument.parse(result);
    for (final entry in {...fields, ...changes}.entries) {
      if (jsonEncode(parsed.fields[entry.key]) != jsonEncode(entry.value)) {
        throw const StudioException(
          StudioError.invalidMetadata,
          '属性无法安全更新，原文件保持不变。',
        );
      }
    }
    return result;
  }
}
