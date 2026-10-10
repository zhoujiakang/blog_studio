import 'dart:async';

import 'package:flutter/material.dart';

import 'package:blog_studio/services/managed_runtime.dart';
import 'package:blog_studio/services/preview_manager.dart';

/// Owns its route, so completion can never dismiss an unrelated dialog.
class PreviewPreparationDialog extends StatefulWidget {
  const PreviewPreparationDialog({
    super.key,
    required this.preview,
    required this.start,
  });
  final PreviewManager preview;
  final Future<Uri> Function() start;
  @override
  State<PreviewPreparationDialog> createState() =>
      _PreviewPreparationDialogState();
}

class _PreviewPreparationDialogState extends State<PreviewPreparationDialog> {
  bool failed = false, cancelling = false;
  String failureMessage = '';
  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final result = await widget.start();
      if (mounted) Navigator.pop(context, result);
    } on PreviewPreparationCancelled {
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        failed = true;
        failureMessage =
            error is FormatException &&
                RegExp(r'^(暂时没有适合|下载|预览组件|这台电脑|准备时间)').hasMatch(error.message)
            ? error.message
            : widget.preview.preparationFailureMessage ??
                  '这次没能完成预览准备。可以重试，已有内容会保留。';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: failed,
    child: AlertDialog(
      title: Text(failed ? '暂时无法打开预览' : '正在准备本地预览'),
      content: SizedBox(
        width: 400,
        child: AnimatedBuilder(
          animation: widget.preview,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!failed) ...[
                LinearProgressIndicator(
                  value: widget.preview.preparationProgress,
                ),
                const SizedBox(height: 20),
                Text(
                  widget.preview.preparationMessage,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  '准备完成后会自动打开博客。',
                  style: TextStyle(fontSize: 12, color: Color(0xff888888)),
                ),
              ] else
                Text(failureMessage),
            ],
          ),
        ),
      ),
      actions: failed
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('稍后再试'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() {
                    failed = false;
                    cancelling = false;
                  });
                  unawaited(_start());
                },
                child: const Text('重试'),
              ),
            ]
          : [
              TextButton(
                onPressed: cancelling
                    ? null
                    : () async {
                        setState(() => cancelling = true);
                        try {
                          await widget.preview.cancelPreparation();
                        } catch (_) {
                          /* The running operation reports the final state. */
                        }
                      },
                child: Text(cancelling ? '正在取消…' : '取消'),
              ),
            ],
    ),
  );
}
