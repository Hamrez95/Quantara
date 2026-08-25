from pathlib import Path

path = Path(
    'src/client/quantara_app/lib/features/trading_journal/presentation/trading_journal_view.dart'
)
text = path.read_text()
import_anchor = "import '../domain/trading_journal_projection.dart';\n"
replay_import = "import '../domain/trading_journal_replay.dart';\n"
if replay_import not in text:
    if import_anchor not in text:
        raise SystemExit('journal projection import anchor missing')
    text = text.replace(import_anchor, import_anchor + replay_import, 1)

old = """    final symbolKey = projection.symbol.trim().toUpperCase();
    final requestedTimeframe = projection.timeframe.trim();
    final requestedKey = '$symbolKey|$requestedTimeframe';
    var liveAnalysis = widget.liveAnalyses[requestedKey];
    var liveIdea = widget.liveIdeas[requestedKey];
    if (liveAnalysis == null) {
      for (final fallbackTimeframe in const ['1h', '15m', '5m', '4h']) {
        final fallbackKey = '$symbolKey|$fallbackTimeframe';
        final fallbackAnalysis = widget.liveAnalyses[fallbackKey];
        if (fallbackAnalysis == null) continue;
        liveAnalysis = fallbackAnalysis;
        liveIdea = widget.liveIdeas[fallbackKey];
        break;
      }
    }
    if (liveAnalysis == null) {
      for (final entry in widget.liveAnalyses.entries) {
        if (!entry.key.startsWith('$symbolKey|')) continue;
        liveAnalysis = entry.value;
        liveIdea = widget.liveIdeas[entry.key];
        break;
      }
    }
"""
new = """    final historicalAnalysis = TradingJournalReplay.decisionChart(
      projection.plan,
    );
"""
if old not in text:
    raise SystemExit('live journal resolver block missing or changed')
text = text.replace(old, new, 1)

old_call = """          analysis: liveAnalysis,
          currentIdea: liveIdea,
"""
new_call = """          analysis: historicalAnalysis,
          currentIdea: null,
"""
if old_call not in text:
    raise SystemExit('journal chart call anchor missing')
text = text.replace(old_call, new_call, 1)

replacements = {
    'برای این رکورد پلن تصمیم‌گیری قابل اتکا ثبت نشده است؛ نمودار زنده چیزی را حدس نمی‌زند.': 'برای این رکورد پلن تصمیم‌گیری قابل اتکا ثبت نشده است؛ بازپخش تاریخی چیزی را حدس نمی‌زند.',
    'No attributable decision plan is stored for this record; the live chart will not invent one.': 'No attributable decision plan is stored for this record; historical replay will not invent one.',
    'پلن ورود ثابت مانده؛ داده زنده این نماد/تایم‌فریم فعلاً در اسنپ‌شات بازار موجود نیست.': 'برای این رکورد اسنپ‌شات معتبر لحظه تصمیم ذخیره نشده است؛ داده زنده جایگزین تاریخچه نمی‌شود.',
    'The entry plan remains frozen; live market data for this symbol/timeframe is not currently available.': 'No valid decision-time chart snapshot is stored for this record; newer live data is never substituted for history.',
    "'حمایت زنده' : 'Live support'": "'حمایت لحظه تصمیم' : 'Decision-time support'",
    "'مقاومت زنده' : 'Live resistance'": "'مقاومت لحظه تصمیم' : 'Decision-time resistance'",
    "'پیوت زنده' : 'Live pivot'": "'پیوت لحظه تصمیم' : 'Decision-time pivot'",
    "title: persian ? 'نمودار زنده پوزیشن' : 'Live position chart'": "title: persian ? 'بازپخش نمودار لحظه تصمیم' : 'Decision-time chart replay'",
    'کندل‌ها و نواحی، زنده‌اند؛ Entry / SL / TP از پلن تغییرناپذیر لحظه ورود می‌آیند.': 'کندل‌ها، نواحی و Entry / SL / TP همگی از اسنپ‌شات تغییرناپذیر همان تصمیم می‌آیند.',
    'Candles and zones are live; Entry / SL / TP come from the immutable decision-time plan.': 'Candles, zones and Entry / SL / TP all come from the immutable snapshot captured for this decision.',
    "'قیمت فعلی' : 'Current'": "'بسته‌شدن آخر اسنپ‌شات' : 'Snapshot close'",
    "persian ? 'نواحی فعلی بازار' : 'Current market zones'": "persian ? 'نواحی لحظه تصمیم' : 'Decision-time zones'",
}
for before, after in replacements.items():
    if before not in text:
        raise SystemExit(f'presentation text anchor missing: {before}')
    text = text.replace(before, after, 1)

path.write_text(text)
