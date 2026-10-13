import 'package:flutter/material.dart';

/// Shared brand tokens. Business names come from authenticated tenant data.
abstract final class AppBrand {
  static const appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'NexaPOS',
  );
  static const tagline = String.fromEnvironment(
    'APP_TAGLINE',
    defaultValue: 'Smart Retail & Cafe POS',
  );
  static const logoAsset = String.fromEnvironment('BRAND_LOGO_ASSET');
  static const businessName = 'Your business';
  static const primaryColor = Color(0xff2563eb);
  static const secondaryColor = Color(0xff0d9488);
  static const navyColor = Color(0xff10223f);
}
