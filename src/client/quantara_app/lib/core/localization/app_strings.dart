import 'package:flutter/widgets.dart';

final class AppStrings {
  const AppStrings._(this.isPersian);

  final bool isPersian;

  static AppStrings of(BuildContext context) {
    return AppStrings._(Localizations.localeOf(context).languageCode == 'fa');
  }

  String t(String fa, String en) => isPersian ? fa : en;

  String integer(int value) =>
      isPersian ? _persianDigits(value.toString()) : '$value';
  String decimal(double value, {int decimals = 1}) {
    final raw = value.toStringAsFixed(decimals);
    return isPersian ? _persianDigits(raw).replaceAll('.', '٫') : raw;
  }

  String _persianDigits(String value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    return value.split('').map((character) {
      final index = latin.indexOf(character);
      return index < 0 ? character : persian[index];
    }).join();
  }

  String get appName => 'Quantara';
  String get appSubtitle => t('پایش و تحلیل بازار', 'Market intelligence');
  String get radar => t('رادار', 'Radar');
  String get watchlist => t('واچ‌لیست', 'Watchlist');
  String get analysis => t('تحلیل', 'Analysis');
  String get profile => t('پروفایل', 'Profile');
  String get settings => t('تنظیمات', 'Settings');
  String get language => t('زبان', 'Language');
  String get persian => t('فارسی', 'Persian');
  String get english => t('انگلیسی', 'English');
  String get languageDescription => t(
    'زبان و جهت رابط همان لحظه تغییر می‌کند.',
    'Language and layout direction change instantly.',
  );
  String get appearance => t('ظاهر', 'Appearance');
  String get darkAppearance => t('حالت تیره', 'Dark appearance');
  String get lightAppearance => t('حالت روشن', 'Light appearance');
  String get appearanceDescription => t(
    'انتخاب ظاهر روی همین دستگاه ذخیره می‌شود.',
    'Your appearance choice is saved on this device.',
  );

  String get addSymbolTitle => t('افزودن نماد', 'Add symbol');
  String get addSymbolDescription => t(
    'نماد Futures بیتیونیکس را وارد کن؛ مثلاً XRP یا XRPUSDT.',
    'Enter a Bitunix Futures symbol, such as XRP or XRPUSDT.',
  );
  String get symbol => t('نماد', 'Symbol');
  String get symbolRequired => t('نماد را وارد کن.', 'Enter a symbol.');
  String get cancel => t('انصراف', 'Cancel');
  String get verifyAndAdd => t('بررسی و افزودن', 'Verify and add');
  String get add => t('افزودن', 'Add');
  String removeSymbol(String symbol) => t('حذف $symbol', 'Remove $symbol');

  String get liveMarketData => t('داده بازار واقعی', 'Real market data');
  String get unstableConnection => t('اتصال ناپایدار', 'Unstable connection');
  String get connecting => t('در حال اتصال', 'Connecting');
  String get refreshing => t('در حال به‌روزرسانی', 'Refreshing');
  String get delayedData => t('داده با تأخیر', 'Delayed data');
  String get unavailable => t('دردسترس نیست', 'Unavailable');
  String get liveBoundary => t(
    'بازار عمومی Bitunix · بدون API Key · به‌روزرسانی هر ۶۰ ثانیه هنگام باز بودن اپ · بدون سفارش واقعی',
    'Public Bitunix market · no API key · refreshes every 60 seconds while open · no real orders',
  );
  String staleSuffix(String message) => t(
    '$message داده قبلی روی صفحه مانده است.',
    '$message The previous snapshot remains on screen.',
  );
  String get retry => t('تلاش دوباره', 'Retry');
  String get tryAgain => t('دوباره تلاش کن', 'Try again');
  String get initialLoading => t(
    'در حال دریافت کندل‌ها و تحلیل واچ‌لیست…',
    'Loading candles and analyzing the watchlist…',
  );
  String get noValidMarketData => t(
    'هنوز داده معتبر بازار دریافت نشده است.',
    'No valid market data has been received yet.',
  );

  String get opportunitiesRadar => t('رادار موقعیت‌ها', 'Opportunity radar');
  String get noOpportunity => t('بدون موقعیت', 'No setup');
  String opportunityCount(int count) =>
      t('${integer(count)} موقعیت', '$count setups');
  String get emptyRadarDescription => t(
    'در اسکن فعلی هیچ نمادی هم‌زمان روند، ناحیه ابطال و نسبت سود به زیان کافی ندارد.',
    'No symbol currently has sufficient trend, invalidation and risk-to-reward evidence.',
  );
  String get radarDescription => t(
    'فرصت‌ها براساس قدرت ساختار مرتب شده‌اند؛ قبل از هر تصمیم، صفحه تحلیل را بررسی کن.',
    'Setups are ranked by structure strength. Review the analysis before any decision.',
  );
  String lastScan(Duration age) =>
      t('آخرین اسکن: ${relativeAge(age)}', 'Last scan: ${relativeAge(age)}');
  String relativeAge(Duration age) {
    final safe = age.isNegative ? Duration.zero : age;
    if (safe.inSeconds < 60) {
      return t(
        '${integer(safe.inSeconds)} ثانیه پیش',
        '${safe.inSeconds}s ago',
      );
    }
    if (safe.inMinutes < 60) {
      return t(
        '${integer(safe.inMinutes)} دقیقه پیش',
        '${safe.inMinutes}m ago',
      );
    }
    return t('${integer(safe.inHours)} ساعت پیش', '${safe.inHours}h ago');
  }

  String get noSetupSemantic => t(
    'در حال حاضر موقعیت قابل بررسی وجود ندارد',
    'There is no setup to review right now',
  );
  String get wait => t('فعلاً صبر', 'Wait for now');
  String checkedSymbols(int count) => t(
    'هر ${integer(count)} نماد بررسی شدند؛ نداشتن معامله یک خروجی معتبر سیستم است.',
    'All $count symbols were checked. No trade is a valid system outcome.',
  );
  String setupSemantic(String label, String symbol) =>
      t('$label برای $symbol', '$label for $symbol');
  String get score => t('امتیاز', 'Score');
  String get entry => t('ورود', 'Entry');
  String get stopLoss => t('حد ضرر', 'Stop loss');
  String get riskReward => t('ریسک به بازده', 'Risk to reward');
  String get inspectChart => t('بررسی روی نمودار', 'Inspect on chart');
  String get hourlyCoverage =>
      t('پوشش اسکن یک‌ساعته', 'One-hour scan coverage');
  String get safetyBoundary => t('مرز ایمنی', 'Safety boundary');
  String get safetyDescription => t(
    'Quantara داده عمومی واقعی را می‌خواند و سناریوی تحلیلی می‌سازد. کلید صرافی، سفارش واقعی و برداشت در این نسخه وجود ندارد.',
    'Quantara reads real public data and builds analytical scenarios. Exchange keys, real orders and withdrawals are not available in this version.',
  );

  String get myWatchlist => t('واچ‌لیست من', 'My watchlist');
  String get futuresLimit => t(
    'نمادهای Futures بیتیونیکس · حداکثر ۱۲ مورد',
    'Bitunix Futures symbols · up to 12',
  );
  String get timeframe => t('تایم‌فریم', 'Timeframe');
  String get chartAttribution => t(
    'نمودار Android با Lightweight Charts™ از TradingView · داده بازار از Bitunix و تحلیل Quantara روی آخرین کندل بسته‌شده است.',
    'Android chart powered by TradingView Lightweight Charts™ · market data from Bitunix and Quantara analysis on the latest closed candle.',
  );
  String chartSemantic({
    required String symbol,
    required String timeframe,
    required String direction,
    required String close,
    required int zones,
  }) => t(
    'نمودار $symbol در $timeframe؛ جهت $direction، آخرین قیمت بسته‌شدن $close و ${integer(zones)} ناحیه مهم.',
    '$symbol $timeframe chart; $direction direction, latest close $close and $zones key zones.',
  );
  String get multiTimeframe =>
      t('هم‌سویی چندتایم‌فریمی', 'Multi-timeframe alignment');
  String get riskPlan => t('پیشنهاد مدیریت سرمایه', 'Risk management plan');
  String get entryRange => t('محدوده ورود', 'Entry range');
  String get firstTarget => t('هدف اول', 'First target');
  String get positionSize => t('حجم پیشنهادی', 'Suggested size');
  String get unitsNoLeverage =>
      t('تعداد واحد دارایی؛ بدون اهرم', 'Asset units; no leverage');
  String get maximumLoss => t('حداکثر زیان', 'Maximum loss');
  String get maximumLossCaption => t(
    'برآورد مدیریت ریسک؛ سقف واقعی تضمین نمی‌شود',
    'Risk estimate; actual loss is not guaranteed',
  );
  String get estimatedCost => t('هزینه تخمینی', 'Estimated cost');
  String get estimatedCostCaption => t(
    'کارمزد و لغزش فرضی رفت‌وبرگشت',
    'Assumed round-trip fees and slippage',
  );
  String invalidation(String value) =>
      t('شرط ابطال: $value', 'Invalidation: $value');
  String get priceZones =>
      t('حمایت و مقاومت روی نمودار', 'Support and resistance on chart');
  String get noZones => t(
    'ناحیه‌ای با حداقل شواهد لازم پیدا نشد.',
    'No zone has enough supporting evidence.',
  );
  String get support => t('حمایت', 'Support');
  String get resistance => t('مقاومت', 'Resistance');
  String get decisionZone => t('ناحیه تصمیم', 'Decision zone');
  String strength(int percent) => t('قدرت $percent٪', 'Strength $percent%');

  String direction(String name) => switch (name) {
    'bullish' => t('صعودی', 'Bullish'),
    'bearish' => t('نزولی', 'Bearish'),
    _ => t('خنثی', 'Sideways'),
  };
  String idea(String name) => switch (name) {
    'long' => t('موقعیت خرید', 'Long setup'),
    'short' => t('موقعیت فروش', 'Short setup'),
    _ => wait,
  };
  String structureSummary({
    required String timeframe,
    required String direction,
    required int strength,
    required int zones,
  }) => t(
    'ساختار $timeframe $direction است؛ $strength٪ قدرت و $zones ناحیه تأییدشده دارد.',
    '$timeframe structure is $direction, with $strength% strength and $zones confirmed zones.',
  );

  String get profileTitle => t('پروفایل و تنظیمات', 'Profile & settings');
  String get profileSubtitle => t(
    'تنظیمات این نسخه فقط روی همین دستگاه ذخیره می‌شود.',
    'Settings in this version are stored only on this device.',
  );
  String get localProfile => t('پروفایل محلی', 'Local profile');
  String get noCloudAccount =>
      t('بدون ورود و همگام‌سازی ابری', 'No sign-in or cloud sync');
  String get connections => t('اتصال‌ها', 'Connections');
  String get bitunixFutures => 'Bitunix Futures';
  String get publicMarketConnection =>
      t('اتصال عمومی بازار', 'Public market connection');
  String get active => t('فعال', 'Active');
  String get limited => t('محدود', 'Limited');
  String get publicConnectionDescription => t(
    'قیمت و کندل عمومی واقعی دریافت می‌شود؛ این اتصال به حساب شخصی تو دسترسی ندارد.',
    'Real public prices and candles are received. This connection cannot access your account.',
  );
  String get privateAccount =>
      t('حساب خصوصی و اجرای سفارش', 'Private account and order execution');
  String get futureVersion => t('نسخه آینده', 'Future version');
  String get privateConnectionDescription => t(
    'کلید API در Android وارد یا ذخیره نمی‌شود. اتصال خصوصی بعداً فقط از Backend رمزنگاری‌شده و ابتدا به‌صورت Read-only اضافه می‌شود.',
    'API keys are never entered or stored on Android. Private access will later use an encrypted backend and begin as read-only.',
  );
  String get addPrivateDisabled =>
      t('افزودن حساب خصوصی (غیرفعال)', 'Add private account (disabled)');
  String get backgroundMonitoring =>
      t('پایش پس‌زمینه', 'Background monitoring');
  String get backgroundMonitoringOff => t(
    'غیرفعال؛ اسکن فقط هنگام باز بودن اپ انجام می‌شود.',
    'Off; scanning runs only while the app is open.',
  );

  String get riskSettings =>
      t('تنظیمات مدیریت سرمایه', 'Risk management settings');
  String get riskSettingsDescription => t(
    'حجم پیشنهادی براساس سرمایه فرضی، فاصله واقعی تا حد ضرر و ۰٫۲۰٪ هزینه تخمینی رفت‌وبرگشت محاسبه می‌شود.',
    'Suggested size uses assumed capital, actual stop distance and 0.20% estimated round-trip costs.',
  );
  String get baseCapital => t('سرمایه مبنا', 'Base capital');
  String get change => t('تغییر', 'Change');
  String riskPerSetup(String value) =>
      t('ریسک هر موقعیت: $value٪', 'Risk per setup: $value%');
  String maximumCalculatedLoss(String value) => t(
    'حداکثر زیان محاسباتی هر سناریو: $value',
    'Maximum calculated loss per scenario: $value',
  );
  String get lossEstimateWarning => t(
    'این سقف برآوردی است؛ جهش قیمت و نقدشوندگی پایین می‌تواند زیان واقعی را بیشتر کند.',
    'This is an estimate; price gaps and low liquidity can increase actual loss.',
  );
  String get capitalDialogTitle =>
      t('سرمایه مبنای محاسبه', 'Calculation capital');
  String get capitalHelper => t(
    'این عدد فرضی است و از حساب صرافی خوانده نمی‌شود.',
    'This is an assumed amount and is not read from an exchange account.',
  );
  String get save => t('ذخیره', 'Save');

  String get securityAndPrivacy =>
      t('امنیت و حریم خصوصی', 'Security & privacy');
  String get securityDescription => t(
    'هیچ API Key یا مجوز معامله‌ای در اپ وجود ندارد. Quantara در این نسخه فقط مشاهده و تحلیل می‌کند.',
    'The app contains no API key or trading permission. This version of Quantara only observes and analyzes.',
  );
  String get about => t('درباره اپ', 'About');
  String get version => t('نسخه ۰٫۴٫۰ اندروید', 'Android version 0.4.0');

  // Legacy cockpit strings remain available while its unused routes are retained.
  String get cockpit => t('مرکز کنترل', 'Cockpit');
  String get markets => t('بازارها', 'Markets');
  String get research => t('پژوهش', 'Research');
  String get paperAccount => t('حساب کاغذی', 'Paper account');
  String get demoEnvironment => t('محیط آزمایشی', 'Demo environment');
  String get demoDescription => t(
    'تمام قیمت‌ها و نتایج این صفحه نمایشی هستند و هیچ سفارش واقعی ارسال نمی‌شود.',
    'All prices and results on this screen are simulated. No real order is sent.',
  );
  String get marketOverview => t('نمای کلی بازار', 'Market overview');
  String get explainableAnalysis =>
      t('تحلیل قابل توضیح', 'Explainable analysis');
  String get noTrade => t('عدم معامله', 'No trade');
  String get confidence => t('اطمینان مدل', 'Model confidence');
  String get marketRegime => t('وضعیت بازار', 'Market regime');
  String get uncertain => t('نامطمئن', 'Uncertain');
  String get whyThisDecision =>
      t('چرا این تصمیم گرفته شد؟', 'Why this decision?');
  String get reconsideration =>
      t('شرط بازبینی تحلیل', 'Analysis reconsideration');
  String get paperBalance => t('ارزش حساب آزمایشی', 'Paper equity');
  String get available => t('موجودی آزاد', 'Available');
  String get usedMargin => t('وجه تضمین درگیر', 'Used margin');
  String get dailyPnl => t('سود و زیان امروز', 'Daily P&L');
  String get openPositions => t('موقعیت‌های باز', 'Open positions');
  String get dailyRisk => t('ریسک روزانه', 'Daily risk');
  String get price => t('قیمت', 'Price');
  String get spread => t('اسپرد', 'Spread');
  String get freshness => t('تازگی داده', 'Freshness');
  String get loading => t('در حال آماده‌سازی...', 'Preparing...');
  String get dataError => t(
    'داده نمایشی در دسترس نیست. دوباره تلاش کنید.',
    'Demo data is unavailable. Please retry.',
  );
  String get lockedRealMoney =>
      t('معامله با پول واقعی قفل است', 'Real-money trading is locked');
}
