import '../../auto_trade/domain/local_live_trade_models.dart';
import '../../autonomy/domain/autonomy_policy_gateway.dart';

enum ExecutionModeAttention { normal, caution, critical }

final class ExecutionModePresentation {
  const ExecutionModePresentation({
    required this.mode,
    required this.title,
    required this.status,
    required this.summary,
    required this.rawState,
    required this.newEntriesEnabled,
    required this.failClosed,
    required this.attention,
  });

  final AutonomyExecutionMode mode;
  final String title;
  final String status;
  final String summary;
  final String rawState;
  final bool newEntriesEnabled;
  final bool failClosed;
  final ExecutionModeAttention attention;

  static ExecutionModePresentation fromLocalLive(
    LocalLiveTradeStatus status, {
    required bool persian,
  }) {
    String text(String fa, String en) => persian ? fa : en;

    if (status.state == LocalLiveTradeState.stopped) {
      return ExecutionModePresentation(
        mode: AutonomyExecutionMode.readOnly,
        title: text('فقط مشاهده · Read Only', 'Read Only'),
        status: text('ورود خودکار خاموش', 'Automatic entry off'),
        summary: text(
          'تحلیل و مشاهده فعال است؛ این صفحه اکنون مجوز ارسال سفارش جدید ندارد.',
          'Analysis and observation remain available; this surface currently has no authority to submit a new order.',
        ),
        rawState: status.state.name,
        newEntriesEnabled: false,
        failClosed: false,
        attention: ExecutionModeAttention.normal,
      );
    }

    final entriesEnabled =
        status.state == LocalLiveTradeState.running && status.entriesEnabled;
    final critical =
        status.state == LocalLiveTradeState.circuitBreaker ||
        status.state == LocalLiveTradeState.error;
    final summary = switch (status.state) {
      LocalLiveTradeState.starting => text(
        'Guarded Auto در حال آماده‌سازی است؛ تا پایان بررسی‌ها ورود جدید مجاز نیست.',
        'Guarded Auto is preparing; new entries remain blocked until checks complete.',
      ),
      LocalLiveTradeState.running when entriesEnabled => text(
        'Guarded Auto فعال است؛ ورود فقط داخل session صریح و همه gateهای ایمنی مجاز است.',
        'Guarded Auto is active; entry is allowed only inside the explicit session and every safety gate.',
      ),
      LocalLiveTradeState.running => text(
        'سرویس فعال است، اما ورود جدید fail-closed مانده است.',
        'The service is active, but new entry remains fail-closed.',
      ),
      LocalLiveTradeState.managingOnly => text(
        'فقط مدیریت پوزیشن‌های موجود فعال است؛ ورود جدید مجاز نیست.',
        'Only existing-position management is active; new entry is not authorized.',
      ),
      LocalLiveTradeState.circuitBreaker => text(
        'مدار ایمنی فعال است؛ ورود جدید مسدود و فقط اقدام حفاظتی مجاز است.',
        'The safety circuit is active; new entry is blocked and only protective action is allowed.',
      ),
      LocalLiveTradeState.error => text(
        'وضعیت اجرا نامطمئن است؛ سیستم به‌صورت fail-closed ورود جدید را مسدود کرده است.',
        'Execution state is uncertain; the system has fail-closed and blocked new entry.',
      ),
      LocalLiveTradeState.stopped => throw StateError('Handled above.'),
    };

    return ExecutionModePresentation(
      mode: AutonomyExecutionMode.guardedAuto,
      title: 'Guarded Auto',
      status: entriesEnabled
          ? text('ورود مشروط فعال', 'Conditional entry active')
          : text('ورود مسدود', 'Entry blocked'),
      summary: summary,
      rawState: status.state.name,
      newEntriesEnabled: entriesEnabled,
      failClosed: !entriesEnabled,
      attention: critical
          ? ExecutionModeAttention.critical
          : entriesEnabled
          ? ExecutionModeAttention.normal
          : ExecutionModeAttention.caution,
    );
  }
}
