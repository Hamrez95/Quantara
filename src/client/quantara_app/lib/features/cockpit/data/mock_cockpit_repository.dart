import '../domain/cockpit_models.dart';

final class MockCockpitRepository implements CockpitRepository {
  const MockCockpitRepository();

  @override
  Future<CockpitSnapshot> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));

    return const CockpitSnapshot(
      environment: AppEnvironment.demo,
      marketStatus: 'بازار باز است · داده نمایشی',
      watchlist: [
        MarketQuote(
          symbol: 'BTCUSDT',
          displayName: 'Bitcoin',
          price: 118420.50,
          changePercent: 1.82,
          spreadBps: 1.4,
          freshness: Duration(seconds: 12),
          sparkline: [
            116800,
            117120,
            116960,
            117540,
            117900,
            117620,
            118120,
            118420,
          ],
        ),
        MarketQuote(
          symbol: 'ETHUSDT',
          displayName: 'Ethereum',
          price: 3712.80,
          changePercent: 0.74,
          spreadBps: 1.9,
          freshness: Duration(seconds: 15),
          sparkline: [3668, 3682, 3676, 3698, 3705, 3692, 3718, 3712],
        ),
        MarketQuote(
          symbol: 'SOLUSDT',
          displayName: 'Solana',
          price: 184.27,
          changePercent: -0.63,
          spreadBps: 3.1,
          freshness: Duration(seconds: 18),
          sparkline: [187.2, 186.8, 186.1, 185.7, 186.0, 185.1, 184.8, 184.27],
        ),
        MarketQuote(
          symbol: 'BNBUSDT',
          displayName: 'BNB',
          price: 812.14,
          changePercent: 0.18,
          spreadBps: 2.2,
          freshness: Duration(seconds: 20),
          sparkline: [808, 809, 810, 809.5, 811, 810.6, 812.4, 812.14],
        ),
      ],
      analysis: ExplainableAnalysis(
        symbol: 'BTCUSDT',
        decision: AnalysisDecision.noTrade,
        confidencePercent: 71,
        regime: MarketRegime.uncertain,
        summary:
            'روند میان‌مدت هنوز صعودی است، اما قیمت نزدیک مقاومت و نقدشوندگی کوتاه‌مدت نامطمئن است. ورود تازه نسبت سود به زیان مناسبی ندارد.',
        invalidation:
            'بسته‌شدن معتبر بالای مقاومت همراه با افزایش حجم، یا بازگشت کنترل‌شده به ناحیه حمایتی، سناریو را دوباره قابل بررسی می‌کند.',
        freshness: Duration(minutes: 2),
        factors: [
          AnalysisFactor(
            title: 'ساختار چهارساعته',
            detail: 'کف‌ها و سقف‌های بالاتر حفظ شده‌اند.',
            impact: EvidenceImpact.supportive,
          ),
          AnalysisFactor(
            title: 'فاصله تا مقاومت',
            detail: 'فضای رشد تا مقاومت بعدی برای ورود جدید محدود است.',
            impact: EvidenceImpact.caution,
          ),
          AnalysisFactor(
            title: 'نوسان و اسپرد',
            detail: 'نوسان لحظه‌ای بالا رفته و هزینه اجرای احتمالی بیشتر شده است.',
            impact: EvidenceImpact.caution,
          ),
        ],
      ),
      paperAccount: PaperAccountSummary(
        equity: 100000,
        availableBalance: 96840,
        usedMargin: 3160,
        dailyPnl: 420.75,
        openPositions: 2,
        maximumDailyRiskPercent: 2,
        currentDailyRiskPercent: 0.64,
      ),
    );
  }
}
