import 'package:flutter/material.dart';

class TaxonomyChip extends StatefulWidget {
  const TaxonomyChip({
    super.key,
    required this.text,
    required this.action,
    required this.selected,
    required this.style,
  });
  final String text;
  final VoidCallback action;
  final bool selected;
  final TextStyle style;

  @override
  State<TaxonomyChip> createState() => TaxonomyChipState();
}

class TaxonomyChipState extends State<TaxonomyChip> {
  bool hovered = false;
  bool focused = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: Focus(
      skipTraversal: true,
      onFocusChange: (value) => setState(() => focused = value),
      child: InputChip(
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 166),
          child: Text(
            widget.text,
            style: widget.style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        onPressed: widget.selected ? null : widget.action,
        onDeleted: widget.selected ? widget.action : null,
        deleteIcon: AnimatedOpacity(
          opacity: hovered || focused ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: const Icon(Icons.remove, size: 13, color: Color(0xff999999)),
        ),
        deleteButtonTooltipMessage: '移除 ${widget.text}',
        avatar: widget.selected
            ? null
            : const Icon(Icons.add, size: 12, color: Color(0xffaaaaaa)),
        backgroundColor: widget.selected
            ? const Color(0xfff1f1f1)
            : Colors.white,
        side: widget.selected
            ? BorderSide.none
            : const BorderSide(color: Color(0xffe9e9e9)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}
