namespace Quantara.Api.Cockpit;

public interface ICockpitSnapshotProvider
{
    CockpitResponseContract Create(DateTimeOffset generatedAt);
}

public sealed class DeterministicCockpitSnapshotProvider : ICockpitSnapshotProvider
{
    public CockpitResponseContract Create(DateTimeOffset generatedAt)
    {
        var generatedAtUtc = generatedAt.ToUniversalTime();

        return new CockpitResponseContract(
            "cockpit-v1",
            "fa",
            generatedAtUtc,
            "demo",
            "deterministic_demo",
            "demo_not_connected",
            "داده نمایشی · بدون اتصال به بازار زنده",
            new CockpitSafetyContract(
                "none",
                false,
                false,
                false),
            Array.AsReadOnly([
                Quote(
                    "BTCUSDT",
                    "Bitcoin",
                    118420.50m,
                    1.82m,
                    1.4m,
                    generatedAtUtc.AddSeconds(-12),
                    [116800m, 117120m, 116960m, 117540m, 117900m, 117620m, 118120m, 118420m]),
                Quote(
                    "ETHUSDT",
                    "Ethereum",
                    3712.80m,
                    0.74m,
                    1.9m,
                    generatedAtUtc.AddSeconds(-15),
                    [3668m, 3682m, 3676m, 3698m, 3705m, 3692m, 3718m, 3712m]),
                Quote(
                    "SOLUSDT",
                    "Solana",
                    184.27m,
                    -0.63m,
                    3.1m,
                    generatedAtUtc.AddSeconds(-18),
                    [187.2m, 186.8m, 186.1m, 185.7m, 186m, 185.1m, 184.8m, 184.27m]),
                Quote(
                    "BNBUSDT",
                    "BNB",
                    812.14m,
                    0.18m,
                    2.2m,
                    generatedAtUtc.AddSeconds(-20),
                    [808m, 809m, 810m, 809.5m, 811m, 810.6m, 812.4m, 812.14m])
            ]),
            new CockpitAnalysisContract(
                "BTCUSDT",
                "no_trade",
                71,
                "uncertain",
                "روند میان‌مدت هنوز صعودی است، اما قیمت نزدیک مقاومت و نقدشوندگی کوتاه‌مدت نامطمئن است. ورود تازه نسبت سود به زیان مناسبی ندارد.",
                "بسته‌شدن معتبر بالای مقاومت همراه با افزایش حجم، یا بازگشت کنترل‌شده به ناحیه حمایتی، سناریو را دوباره قابل بررسی می‌کند.",
                generatedAtUtc.AddMinutes(-2),
                Array.AsReadOnly([
                    new CockpitAnalysisFactorContract(
                        "four_hour_structure",
                        "ساختار چهارساعته",
                        "کف‌ها و سقف‌های بالاتر حفظ شده‌اند.",
                        "supportive"),
                    new CockpitAnalysisFactorContract(
                        "distance_to_resistance",
                        "فاصله تا مقاومت",
                        "فضای رشد تا مقاومت بعدی برای ورود جدید محدود است.",
                        "caution"),
                    new CockpitAnalysisFactorContract(
                        "volatility_and_spread",
                        "نوسان و اسپرد",
                        "نوسان لحظه‌ای بالا رفته و هزینه اجرای احتمالی بیشتر شده است.",
                        "caution")
                ])),
            new CockpitPaperAccountContract(
                "USDT",
                true,
                100000m,
                96840m,
                3160m,
                420.75m,
                2,
                2m,
                0.64m));
    }

    private static CockpitQuoteContract Quote(
        string symbol,
        string displayName,
        decimal price,
        decimal changePercent,
        decimal spreadBps,
        DateTimeOffset observedAt,
        decimal[] sparkline)
    {
        return new CockpitQuoteContract(
            symbol,
            displayName,
            price,
            changePercent,
            spreadBps,
            observedAt,
            Array.AsReadOnly(sparkline));
    }
}
