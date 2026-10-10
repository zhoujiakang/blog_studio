import 'dart:async';

import 'package:flutter/material.dart';

/// Stages and elapsed time, without pretending network work has a fixed duration.
class OperationProgress extends StatefulWidget {
  const OperationProgress({
    super.key,
    required this.stages,
    required this.current,
    required this.running,
    this.startedAt,
    this.fraction,
  });
  final List<String> stages;
  final int current;
  final bool running;
  final DateTime? startedAt;
  final double? fraction;
  @override
  State<OperationProgress> createState() => _OperationProgressState();
}

class _OperationProgressState extends State<OperationProgress> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _ticker();
  }

  @override
  void didUpdateWidget(OperationProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ticker();
  }

  void _ticker() {
    if (!widget.running) {
      timer?.cancel();
      timer = null;
    } else {
      timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.startedAt == null
        ? 0
        : DateTime.now().difference(widget.startedAt!).inSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (var i = 0; i < widget.stages.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    i < widget.current
                        ? Icons.check_circle_outline
                        : i == widget.current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 15,
                    color: i <= widget.current
                        ? const Color(0xff555555)
                        : const Color(0xffbbbbbb),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.stages[i],
                    style: TextStyle(
                      fontSize: 12,
                      color: i <= widget.current
                          ? const Color(0xff555555)
                          : const Color(0xffaaaaaa),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (widget.running) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: widget.fraction),
          const SizedBox(height: 8),
          Text(
            '已用时 ${seconds ~/ 60} 分 ${seconds % 60} 秒',
            style: const TextStyle(fontSize: 12, color: Color(0xff888888)),
          ),
        ],
      ],
    );
  }
}
