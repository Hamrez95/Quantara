import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android chart assets are present and wired for offline rendering', () {
    final html = File(
      'android/app/src/main/assets/tradingview/chart.html',
    );
    final library = File(
      'android/app/src/main/assets/tradingview/'
      'lightweight-charts.standalone.production.js',
    );
    final renderer = File(
      'android/app/src/main/assets/tradingview/quantara-chart.js',
    );

    expect(html.existsSync(), isTrue);
    expect(library.existsSync(), isTrue);
    expect(renderer.existsSync(), isTrue);
    expect(library.lengthSync(), greaterThan(100000));

    final source = html.readAsStringSync();
    expect(
      source,
      contains('lightweight-charts.standalone.production.js'),
    );
    expect(source, contains('quantara-chart.js'));
    expect(
      renderer.readAsStringSync(),
      contains('window.renderQuantaraChart'),
    );
  });
}
