import 'package:flutter/material.dart';

import '../../app/config/app_brand.dart';

/// The shared application mark honors the centrally configured logo asset.
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 40, this.light = true, super.key});

  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${AppBrand.appName} logo',
    image: true,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: light
            ? AppBrand.primaryColor
            : AppBrand.primaryColor.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(size * .26),
      ),
      child: AppBrand.logoAsset.isEmpty
          ? _fallback()
          : Padding(
              padding: EdgeInsets.all(size * .15),
              child: Image.asset(
                AppBrand.logoAsset,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (context, error, stackTrace) => _fallback(),
              ),
            ),
    ),
  );

  Widget _fallback() => Icon(
    Icons.point_of_sale_rounded,
    color: light ? Colors.white : AppBrand.primaryColor,
    size: size * .58,
  );
}
