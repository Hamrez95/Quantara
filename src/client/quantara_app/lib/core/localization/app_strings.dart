import 'package:flutter/widgets.dart';

final class AppStrings {
  const AppStrings._(this._isPersian);

  final bool _isPersian;

  static AppStrings of(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return AppStrings._(languageCode == 'fa');
  }

  String get appName => 'Quantara';
  String get cockpit => _isPersian ? 'مرکز کنترل' : 'Cockpit';
  String get markets => _isPersian ? 'بازارها' : 'Markets';
  String get research => _isPersian ? 'پژوهش' : 'Research';
  String get paperAccount => _isPersian ? 'حساب کاغذی' : 'Paper account';
  String get settings => _isPersian ? 'تنظیمات' : 'Settings';
  String get demoEnvironment =>
      _isPersian ? 'محیط آزمایشی' : 'Demo environment';
  String get demoDescription => _isPersian
      ? 'تمام قیمت‌ها و نتایج این صفحه نمایشی هستند و هیچ سفارش واقعی ارسال نمی‌شود.'
      : 'All prices and results on this screen are simulated. No real order is sent.';
  String get marketOverview =>
      _isPersian ? 'نمای کلی بازار' : 'Market overview';
  String get explainableAnalysis =>
      _isPersian ? 'تحلیل قابل توضیح' : 'Explainable analysis';
  String get noTrade => _isPersian ? 'عدم معامله' : 'No trade';
  String get confidence => _isPersian ? 'اطمینان مدل' : 'Model confidence';
  String get marketRegime => _isPersian ? 'وضعیت بازار' : 'Market regime';
  String get uncertain => _isPersian ? 'نامطمئن' : 'Uncertain';
  String get whyThisDecision =>
      _isPersian ? 'چرا این تصمیم گرفته شد؟' : 'Why this decision?';
  String get invalidation =>
      _isPersian ? 'شرط بازبینی تحلیل' : 'Analysis reconsideration';
  String get paperBalance => _isPersian ? 'ارزش حساب آزمایشی' : 'Paper equity';
  String get available => _isPersian ? 'موجودی آزاد' : 'Available';
  String get usedMargin => _isPersian ? 'وجه تضمین درگیر' : 'Used margin';
  String get dailyPnl => _isPersian ? 'سود و زیان امروز' : 'Daily P&L';
  String get openPositions => _isPersian ? 'موقعیت‌های باز' : 'Open positions';
  String get dailyRisk => _isPersian ? 'ریسک روزانه' : 'Daily risk';
  String get watchlist => _isPersian ? 'فهرست پیگیری' : 'Watchlist';
  String get price => _isPersian ? 'قیمت' : 'Price';
  String get change => _isPersian ? 'تغییر' : 'Change';
  String get spread => _isPersian ? 'اسپرد' : 'Spread';
  String get freshness => _isPersian ? 'تازگی داده' : 'Freshness';
  String get retry => _isPersian ? 'تلاش دوباره' : 'Retry';
  String get loading => _isPersian ? 'در حال آماده‌سازی...' : 'Preparing...';
  String get dataError => _isPersian
      ? 'داده نمایشی در دسترس نیست. دوباره تلاش کنید.'
      : 'Demo data is unavailable. Please retry.';
  String get lockedRealMoney => _isPersian
      ? 'معامله با پول واقعی قفل است'
      : 'Real-money trading is locked';
}
