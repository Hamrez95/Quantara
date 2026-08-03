import 'package:flutter/foundation.dart';

@immutable
class LocalLiveAffordabilitySummary {
  const LocalLiveAffordabilitySummary({
    required this.availableMargin,
    required this.minimumMargin,
    required this.symbol,
    required this.shortfall,
  });

  final String availableMargin;
  final String minimumMargin;
  final String symbol;
  final String shortfall;
}

abstract final class LocalLiveMessageLocalizer {
  static final RegExp _affordability = RegExp(
    r'^Available margin is ([0-9.]+) USDT\. The smallest exchange/margin floor among the selected symbols is about ([0-9.]+) USDT \(([^,]+), including three TP quantities and the safety buffer\)\. Shortfall: ([0-9.]+) USDT\. The actual risk and stop distance checks may require more capital\.$',
  );

  static LocalLiveAffordabilitySummary? affordability(String message) {
    final match = _affordability.firstMatch(message.trim());
    if (match == null) return null;
    return LocalLiveAffordabilitySummary(
      availableMargin: match.group(1)!,
      minimumMargin: match.group(2)!,
      symbol: match.group(3)!,
      shortfall: match.group(4)!,
    );
  }

  static String localize(String message, {required bool persian}) {
    final value = message.trim();
    if (!persian || value.isEmpty || _containsPersian(value)) return value;
    final summary = affordability(value);
    if (summary != null) {
      return 'موجودی قابل استفاده ${summary.availableMargin} USDT است؛ حداقل سرمایه لازم برای ${summary.symbol} حدود ${summary.minimumMargin} USDT و کسری سرمایه ${summary.shortfall} USDT است. با توجه به فاصله حد ضرر و کنترل ریسک ممکن است سرمایه بیشتری لازم باشد.';
    }
    const exact = <String, String>{
      'Local live trading is stopped.': 'ترید واقعی محلی متوقف است.',
      'Local live service is starting on this device.':
          'سرویس ترید محلی روی این دستگاه در حال راه‌اندازی است.',
      'Local live trading was already stopped.':
          'ترید محلی از قبل متوقف بوده است.',
      'Local service stopped. Existing exchange SL/TP remains active.':
          'سرویس محلی متوقف شد؛ حد ضرر و حد سود ثبت‌شده در صرافی فعال می‌مانند.',
      'Local service stopped after emergency close requests.':
          'سرویس محلی پس از ارسال درخواست‌های بستن اضطراری متوقف شد.',
      'Local live service started; waiting for in-memory credentials.':
          'سرویس محلی شروع شد و در انتظار دریافت امن اطلاعات اتصال است.',
      'New entries stopped; exchange-native protection remains active.':
          'ورودهای جدید متوقف شده‌اند و حفاظت ثبت‌شده در صرافی فعال است.',
      'Local live service stopped.': 'سرویس ترید محلی متوقف شد.',
      'Android stopped the local live service after a timeout.':
          'اندروید پس از پایان مهلت، سرویس ترید محلی را متوقف کرد.',
      'Local live configuration was missing.': 'تنظیمات ترید محلی پیدا نشد.',
      'Bitunix credentials were unavailable to the local service.':
          'اطلاعات اتصال Bitunix در اختیار سرویس محلی قرار نگرفت.',
      'Local live canary is armed on this Android device.':
          'نسخه Canary ترید محلی روی این دستگاه آماده و فعال است.',
      'New entries stopped; existing exchange SL/TP orders remain active.':
          'ورود جدید متوقف شد و سفارش‌های حد ضرر و حد سود صرافی فعال می‌مانند.',
      'Emergency reduce-only close requests were submitted.':
          'درخواست‌های بستن اضطراری Reduce-only ارسال شدند.',
      'Daily loss cap reached. New entries are blocked.':
          'سقف ضرر روزانه پر شده و ورود جدید مسدود است.',
      'Local live scan and exchange reconciliation completed.':
          'اسکن بازار و تطبیق وضعیت صرافی با موفقیت انجام شد.',
      'Only exchange-protected positions are being reconciled.':
          'فقط پوزیشن‌های دارای حفاظت صرافی در حال پایش و تطبیق هستند.',
      'Three consecutive local execution failures. New entries blocked.':
          'سه خطای پیاپی در اجرای محلی رخ داد و ورود جدید مسدود شد.',
      'Guarded local live trading is available only on Android.':
          'ترید واقعی محلی فقط در نسخه اندروید در دسترس است.',
      'Connect and validate the Bitunix account before starting local live trading.':
          'پیش از شروع ترید محلی، حساب Bitunix را متصل و اعتبارسنجی کن.',
      'Notification permission is required for the visible local execution service.':
          'برای نمایش و کنترل سرویس ترید محلی، اجازه اعلان لازم است.',
      'No available USDT margin is available for a new isolated position.':
          'برای بازکردن پوزیشن Isolated جدید، مارجین USDT قابل استفاده وجود ندارد.',
      'Quantara could not confirm an affordable API-supported symbol from the selected allow-list.':
          'Quantara نتوانست میان نمادهای انتخاب‌شده، نمادی معتبر و متناسب با موجودی تأیید کند.',
      'No actionable setup passed the selected strategy and timeframe filters.':
          'هیچ ستاپ قابل اجرایی از فیلتر استراتژی و تایم‌فریم‌های انتخاب‌شده عبور نکرد.',
      'Actionable setups were skipped because selected timeframes disagreed on direction.':
          'ستاپ‌های قابل بررسی به‌دلیل تضاد جهت در تایم‌فریم‌های انتخاب‌شده رد شدند.',
      'The highest-ranked setup was already executed in this local-live history.':
          'ستاپ برتر قبلاً در تاریخچه ترید محلی اجرا شده و دوباره وارد نمی‌شود.',
      'The highest-ranked setup was expired or missing a complete protected plan.':
          'ستاپ برتر منقضی شده یا برنامه کامل Entry، SL و سه TP را ندارد.',
      'The highest-ranked setup is valid but the live mark price is outside its entry zone.':
          'ستاپ معتبر است، اما قیمت لحظه‌ای هنوز داخل محدوده ورود قرار ندارد.',
      'The selected instrument is closed or unavailable for API futures execution.':
          'نماد انتخاب‌شده بسته است یا اجرای فیوچرز API برای آن در دسترس نیست.',
      'Calculated position size is below the exchange minimum for three protected target tranches.':
          'حجم محاسبه‌شده برای تقسیم ایمن بین سه حد سود، از حداقل صرافی کمتر است.',
      'Available margin is below the protected entry requirement including the safety buffer.':
          'مارجین آزاد برای ورود محافظت‌شده همراه با حاشیه ایمنی کافی نیست.',
      'TP1 largest reduction observed; remaining position moved beyond break-even including costs.':
          'بخش اصلی حجم در TP1 بسته شد و استاپ باقی‌مانده با احتساب هزینه‌ها به محدوده ریسک‌فری منتقل شد.',
    };
    final known = exact[value];
    if (known != null) return known;
    if (value.startsWith('Local cycle failed safely:')) {
      return 'چرخه ترید محلی به‌صورت ایمن متوقف شد. جزئیات در گزارش اجرا ثبت شده است.';
    }
    if (value.startsWith(
      'Android is not running the local execution service.',
    )) {
      return 'سرویس اجرای محلی اندروید فعال نیست؛ سفارش‌های حد ضرر و حد سود ثبت‌شده در صرافی همچنان مرجع هستند.';
    }
    if (value.startsWith('Android foreground service')) {
      return 'راه‌اندازی سرویس پس‌زمینه اندروید ناموفق بود. برنامه را باز نگه دار و اجازه اعلان را بررسی کن.';
    }
    if (value.startsWith('Local live service could not start safely')) {
      return 'سرویس ترید محلی نتوانست به‌صورت ایمن شروع شود.';
    }
    if (value.startsWith('The local stop request failed')) {
      return 'درخواست توقف سرویس محلی ناموفق بود؛ وضعیت سفارش‌های محافظتی صرافی را بررسی کن.';
    }
    return 'سرویس ترید محلی یک وضعیت فنی ثبت کرده است. برای جزئیات، گزارش اجرا را باز کن.';
  }

  static bool _containsPersian(String value) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(value);
}
