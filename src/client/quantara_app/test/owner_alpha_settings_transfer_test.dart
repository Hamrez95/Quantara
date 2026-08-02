import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/owner_alpha_settings_transfer.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('round-trips non-sensitive owner settings', () {
    const settings = OwnerAlphaSettings(
      symbols: ['BTCUSDT', 'XRPUSDT'],
      capital: 800,
      riskPercent: 0.5,
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.active,
    );

    final encoded = OwnerAlphaSettingsTransfer.encode(settings);
    final decoded = OwnerAlphaSettingsTransfer.decode(encoded);

    expect(encoded, startsWith(OwnerAlphaSettingsTransfer.marker));
    expect(decoded.symbols, settings.symbols);
    expect(decoded.capital, settings.capital);
    expect(decoded.riskPercent, settings.riskPercent);
    expect(decoded.strategy, settings.strategy);
    expect(decoded.cadence, settings.cadence);
    expect(encoded.toLowerCase(), isNot(contains('apikey')));
    expect(encoded.toLowerCase(), isNot(contains('secret')));
  });

  test('rejects malformed or unsafe backups', () {
    expect(
      () => OwnerAlphaSettingsTransfer.decode('not-a-quantara-backup'),
      throwsFormatException,
    );
    expect(
      () => OwnerAlphaSettingsTransfer.decode(
        '${OwnerAlphaSettingsTransfer.marker}{"schema":1,"symbols":[],"capital":1,"riskPercent":20,"strategy":"structureZones","cadence":"balanced"}',
      ),
      throwsFormatException,
    );
  });
}
