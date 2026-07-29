import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app/quantara_app.dart';
import 'features/owner_alpha/data/background_opportunity_scanner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuantaraApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(BackgroundOpportunityScanner.initialize());
  });
}
