import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The product mark is separate from a blog author's avatar.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/brand/logo-mark.svg',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticsLabel: '拾笺 InkJian 标志',
  );
}
