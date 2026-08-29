import '../data/bitunix_local_live_api_client.dart';

abstract final class PartialFillCloseConfirmationPolicy {
  static bool provesFlat({
    required String orderStatus,
    required BitunixLivePosition? position,
  }) => orderStatus.trim().toUpperCase() == 'CANCELED' && position == null;
}
