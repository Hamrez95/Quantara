import 'package:flutter/widgets.dart';

import 'app/quantara_app.dart';
import 'features/owner_alpha/data/background_opportunity_scanner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundOpportunityScanner.initialize();
  runApp(const QuantaraApp());
}
