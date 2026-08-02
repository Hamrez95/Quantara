import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/candidate_audit_models.dart';
import '../domain/realtime_candidate_models.dart';
import '../domain/realtime_market_event_models.dart';

abstract final class CandidateAuditCodec {
  static const schemaVersion = 1;
  static const maximumEncodedLength = 2000000;

  static CandidateAuditRecord fromAuditEvent(
    CandidateRegistryAuditEvent event,
  ) {
    final canonicalIdentity = jsonEncode({
      'eventId': event.eventId,
      'setupId': event.setupId,
      'symbol': event.streamKey.symbol,
      'timeframe': event.streamKey.timeframe,
      'disposition': event.disposition.name,
      'observedAtUtc': event.observedAtUtc.toUtc().toIso8601String(),
      'previousStage': event.previousStage?.name,
      'currentStage': event.currentStage?.name,
      'transitionReason': event.transitionReason?.name,
      'expectedSequence': event.gap?.expectedSequence,
      'observedSequence': event.gap?.observedSequence,
    });
    final recordId = sha256.convert(utf8.encode(canonicalIdentity)).toString();

    return CandidateAuditRecord(
      recordId: recordId,
      auditSequence: event.auditSequence,
      disposition: event.disposition,
      eventId: event.eventId,
      setupId: event.setupId,
      symbol: event.streamKey.symbol,
      timeframe: event.streamKey.timeframe,
      observedAtUtc: event.observedAtUtc.toUtc(),
      previousStage: event.previousStage,
      currentStage: event.currentStage,
      transitionReason: event.transitionReason,
      expectedSequence: event.gap?.expectedSequence,
      observedSequence: event.gap?.observedSequence,
    );
  }

  static String encode(CandidateAuditLedger ledger) {
    final body = <String, Object?>{
      'schemaVersion': schemaVersion,
      'generation': ledger.generation,
      'records': ledger.records.map(_recordToJson).toList(growable: false),
    };
    final bodyJson = jsonEncode(body);
    return jsonEncode({
      'body': body,
      'checksum': sha256.convert(utf8.encode(bodyJson)).toString(),
    });
  }

  static CandidateAuditLedger? tryDecode(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maximumEncodedLength) {
      return null;
    }
    try {
      final envelope = jsonDecode(value);
      if (envelope is! Map<String, Object?>) return null;
      final body = envelope['body'];
      final checksum = envelope['checksum'];
      if (body is! Map<String, Object?> || checksum is! String) return null;
      final calculated = sha256
          .convert(utf8.encode(jsonEncode(body)))
          .toString();
      if (calculated != checksum || body['schemaVersion'] != schemaVersion) {
        return null;
      }

      final generation = (body['generation'] as num?)?.toInt();
      final rawRecords = body['records'];
      if (generation == null ||
          generation < 0 ||
          rawRecords is! List<Object?>) {
        return null;
      }
      final records = <CandidateAuditRecord>[];
      for (final rawRecord in rawRecords) {
        if (rawRecord is! Map<String, Object?>) return null;
        final record = _tryRecord(rawRecord);
        if (record == null) return null;
        records.add(record);
      }
      return CandidateAuditLedger(generation: generation, records: records);
    } on Object {
      return null;
    }
  }

  static Map<String, Object?> _recordToJson(CandidateAuditRecord record) => {
    'recordId': record.recordId,
    'auditSequence': record.auditSequence,
    'disposition': record.disposition.name,
    'eventId': record.eventId,
    'setupId': record.setupId,
    'symbol': record.symbol,
    'timeframe': record.timeframe,
    'observedAtUtc': record.observedAtUtc.toIso8601String(),
    'previousStage': record.previousStage?.name,
    'currentStage': record.currentStage?.name,
    'transitionReason': record.transitionReason?.name,
    'expectedSequence': record.expectedSequence,
    'observedSequence': record.observedSequence,
  };

  static CandidateAuditRecord? _tryRecord(Map<String, Object?> value) {
    final recordId = value['recordId'];
    final auditSequence = (value['auditSequence'] as num?)?.toInt();
    final disposition = _enumValue(
      StreamEventDisposition.values,
      value['disposition'],
    );
    final eventId = value['eventId'];
    final setupId = value['setupId'];
    final symbol = value['symbol'];
    final timeframe = value['timeframe'];
    final observedAt = value['observedAtUtc'];
    if (recordId is! String ||
        auditSequence == null ||
        disposition == null ||
        eventId is! String ||
        setupId is! String ||
        symbol is! String ||
        timeframe is! String ||
        observedAt is! String) {
      return null;
    }
    final parsedAt = DateTime.tryParse(observedAt)?.toUtc();
    if (parsedAt == null) return null;

    try {
      return CandidateAuditRecord(
        recordId: recordId,
        auditSequence: auditSequence,
        disposition: disposition,
        eventId: eventId,
        setupId: setupId,
        symbol: symbol,
        timeframe: timeframe,
        observedAtUtc: parsedAt,
        previousStage: _nullableEnumValue(
          OpportunityStage.values,
          value['previousStage'],
        ),
        currentStage: _nullableEnumValue(
          OpportunityStage.values,
          value['currentStage'],
        ),
        transitionReason: _nullableEnumValue(
          OpportunityTransitionReason.values,
          value['transitionReason'],
        ),
        expectedSequence: (value['expectedSequence'] as num?)?.toInt(),
        observedSequence: (value['observedSequence'] as num?)?.toInt(),
      );
    } on Object {
      return null;
    }
  }

  static T? _enumValue<T extends Enum>(Iterable<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static T? _nullableEnumValue<T extends Enum>(
    Iterable<T> values,
    Object? raw,
  ) {
    if (raw == null) return null;
    return _enumValue(values, raw);
  }
}
