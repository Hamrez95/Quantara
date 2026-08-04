from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 anchor, found {count}")
    return text.replace(old, new)


runtime_path = Path(
    "src/client/quantara_app/lib/features/auto_trade/application/"
    "local_live_portfolio_risk_runtime.dart"
)
runtime = runtime_path.read_text()
runtime = replace_once(
    runtime,
    """  }) => LocalLivePortfolioRiskRuntime._(
    _store:
        store ??
        DatabasePortfolioRiskLedgerStore(
          recordKey: 'local-live-portfolio-risk-ledger-v1',
        ),
    _dailyRiskLimit: dailyRiskLimit,
    _timezoneOffsetMinutes: timezoneOffsetMinutes,
    maximumAssetGroupRiskFraction: maximumAssetGroupRiskFraction,
  );

  const LocalLivePortfolioRiskRuntime._({
    required this._store,
    required this._dailyRiskLimit,
    required this._timezoneOffsetMinutes,
    required this.maximumAssetGroupRiskFraction,
  });""",
    """  }) => LocalLivePortfolioRiskRuntime._(
    store ??
        DatabasePortfolioRiskLedgerStore(
          recordKey: 'local-live-portfolio-risk-ledger-v1',
        ),
    dailyRiskLimit,
    timezoneOffsetMinutes,
    maximumAssetGroupRiskFraction,
  );

  const LocalLivePortfolioRiskRuntime._(
    this._store,
    this._dailyRiskLimit,
    this._timezoneOffsetMinutes,
    this.maximumAssetGroupRiskFraction,
  );""",
    "runtime constructor",
)
runtime_path.write_text(runtime)

preferences_path = Path(
    "src/client/quantara_app/lib/features/auto_trade/data/"
    "local_live_preferences_store.dart"
)
preferences = preferences_path.read_text()
preferences = replace_once(
    preferences,
    """  static const minimumConcurrentPositions = 1;
  static const maximumConcurrentPositions = 3;""",
    """  static const minimumConcurrentPositionCount = 1;
  static const maximumConcurrentPositionCount = 3;""",
    "preference constants",
)
preferences = replace_once(
    preferences,
    """      maximumConcurrentPositions: maximumConcurrentPositions.clamp(
        minimumConcurrentPositions,
        maximumConcurrentPositions,
      ),""",
    """      maximumConcurrentPositions: maximumConcurrentPositions.clamp(
        minimumConcurrentPositionCount,
        maximumConcurrentPositionCount,
      ),""",
    "preference normalization",
)
preferences_path.write_text(preferences)

models_path = Path(
    "src/client/quantara_app/lib/features/auto_trade/domain/"
    "local_live_trade_models.dart"
)
models = models_path.read_text()
models = replace_once(
    models,
    "import 'profit_lock_stop_policy.dart';\nimport 'trading_pnl_projection.dart';",
    "import 'local_live_portfolio_admission.dart';\n"
    "import 'profit_lock_stop_policy.dart';\n"
    "import 'trading_pnl_projection.dart';",
    "configuration import",
)
models = replace_once(
    models,
    """    if (maximumConcurrentPositions != 1) {
      throw const FormatException(
        'The first local live canary is limited to one concurrent position.',
      );
    }""",
    """    if (maximumConcurrentPositions < 1 ||
        maximumConcurrentPositions >
            LocalLivePortfolioAdmission.maximumSupportedConcurrentPositions) {
      throw const FormatException(
        'Local Live supports between one and three concurrent positions.',
      );
    }""",
    "configuration concurrency validation",
)
models_path.write_text(models)

service_path = Path(
    "src/client/quantara_app/lib/features/auto_trade/application/"
    "local_live_trade_service.dart"
)
service = service_path.read_text()
assert service.count("reservationId: activeReservationId!,") == 3
service = service.replace(
    "reservationId: activeReservationId!,",
    "reservationId: activeReservationId,",
)
service_path.write_text(service)

ui_path = Path(
    "src/client/quantara_app/lib/features/owner_alpha/presentation/"
    "owner_alpha_auto_trade.dart"
)
ui = ui_path.read_text()
ui = replace_once(
    ui,
    "  double _dailyLossLimit = 1;\n  int _tp1Percent = 65;",
    "  double _dailyLossLimit = 1;\n"
    "  int _maximumConcurrentPositions = 2;\n"
    "  int _tp1Percent = 65;",
    "UI state",
)
ui = replace_once(
    ui,
    "        _dailyLossLimit = value.dailyLossLimitPercent;\n        _tp1Percent",
    "        _dailyLossLimit = value.dailyLossLimitPercent;\n"
    "        _maximumConcurrentPositions = value.maximumConcurrentPositions;\n"
    "        _tp1Percent",
    "UI restore",
)
ui = replace_once(
    ui,
    "    dailyLossLimitPercent: _dailyLossLimit,\n    targetAllocation:",
    "    dailyLossLimitPercent: _dailyLossLimit,\n"
    "    maximumConcurrentPositions: _maximumConcurrentPositions,\n"
    "    targetAllocation:",
    "UI preferences",
)
ui = replace_once(
    ui,
    """              'این حالت می‌تواند سفارش واقعی فیوچرز ارسال کند. فقط یک پوزیشن هم‌زمان و Isolated مجاز است؛ ریسک قابل تنظیم تا ۲٪ و سقف ضرر روزانه تا ۱۰٪ باز شده، اما هر ورود همچنان باید با SL کامل و سه TP تأییدشده صرافی محافظت شود.',
              'This mode can submit real futures orders. It remains isolated and limited to one concurrent position; risk is adjustable up to 2% and the daily cap up to 10%, while every entry still requires a full exchange-confirmed stop and three targets.',""",
    """              'این حالت می‌تواند سفارش واقعی فیوچرز ارسال کند. حداکثر سه پوزیشن Isolated فقط در محدوده بودجه اتمیک ریسک و مارجین پرتفوی مجاز است؛ هر ورود همچنان باید با SL کامل و سه TP تأییدشده صرافی محافظت شود.',
              'This mode can submit real futures orders. Up to three isolated positions are allowed only inside the atomic portfolio risk and margin budget; every entry still requires a full exchange-confirmed stop and three targets.',""",
    "UI boundary",
)
ui = replace_once(
    ui,
    """                  '${status.openPositionCount} پوزیشن باز',
                  '${status.openPositionCount} open',""",
    """                  '${status.openPositionCount}/$_maximumConcurrentPositions پوزیشن باز',
                  '${status.openPositionCount}/$_maximumConcurrentPositions open',""",
    "UI slot status",
)
ui = replace_once(
    ui,
    """                  TpAllocationEditor(
                    allocation: _targetAllocation,""",
    """                  _numberRow(
                    label: _t(
                      'حداکثر پوزیشن هم‌زمان',
                      'Maximum concurrent positions',
                    ),
                    value: _maximumConcurrentPositions.toString(),
                    onMinus: () => _mutateAndSave(
                      () => _maximumConcurrentPositions = math.max(
                        1,
                        _maximumConcurrentPositions - 1,
                      ),
                    ),
                    onPlus: () => _mutateAndSave(
                      () => _maximumConcurrentPositions = math.min(
                        3,
                        _maximumConcurrentPositions + 1,
                      ),
                    ),
                  ),
                  TpAllocationEditor(
                    allocation: _targetAllocation,""",
    "UI concurrency control",
)
ui = replace_once(
    ui,
    """              'این تنظیمات می‌توانند زیان واقعی را سریع‌تر افزایش دهند. Quantara استاپ را دورتر نمی‌کند، بعد از ضرر ریسک را بالا نمی‌برد و همچنان فقط یک پوزیشن Isolated باز می‌کند. ادامه می‌دهی؟',
              'These settings can increase real losses faster. Quantara will not widen stops, increase risk after losses, or open more than one isolated position. Continue?',""",
    """              'این تنظیمات می‌توانند زیان واقعی را سریع‌تر افزایش دهند. Quantara استاپ را دورتر نمی‌کند، بعد از ضرر ریسک را بالا نمی‌برد و هر ورود هم‌زمان را به بودجه اتمیک پرتفوی محدود می‌کند. ادامه می‌دهی؟',
              'These settings can increase real losses faster. Quantara will not widen stops or increase risk after losses, and every concurrent entry remains constrained by the atomic portfolio budget. Continue?',""",
    "advanced dialog",
)
ui = replace_once(
    ui,
    """              Text(
                '${_t('تقسیم اهداف', 'Target allocation')}: TP1 $_tp1Percent% · TP2 $_tp2Percent% · TP3 $_tp3Percent%',""",
    """              Text(
                '${_t('حداکثر پوزیشن هم‌زمان', 'Maximum concurrent positions')}: $_maximumConcurrentPositions',
              ),
              Text(
                '${_t('تقسیم اهداف', 'Target allocation')}: TP1 $_tp1Percent% · TP2 $_tp2Percent% · TP3 $_tp3Percent%',""",
    "confirmation dialog",
)
ui = replace_once(
    ui,
    "        maximumConcurrentPositions: 1,",
    "        maximumConcurrentPositions: _maximumConcurrentPositions,",
    "start configuration",
)
ui_path.write_text(ui)
