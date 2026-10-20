import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/fuel_transaction.dart';
import '../models/fuel_type.dart';
import '../models/transaction_status.dart';

/// Error raised when the backend cannot be reached or returns an error.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.statusCode});

  /// 'NETWORK' | 'TIMEOUT' | 'BAD_RESPONSE' | server-provided error code.
  final String code;
  final String message;
  final int? statusCode;

  bool get isNetwork =>
      code == 'NETWORK' || code == 'TIMEOUT' || code == 'BAD_RESPONSE';

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

/// Snapshot of `/api/transactions/:id/status`.
class StatusSnapshot {
  const StatusSnapshot({
    required this.transactionId,
    required this.status,
    required this.mode,
    this.paymentProvider,
    this.statusReason,
    this.updatedAt,
  });

  final String transactionId;
  final TransactionStatus status;
  final PaymentMode mode;
  final String? paymentProvider;
  final String? statusReason;
  final DateTime? updatedAt;

  factory StatusSnapshot.fromJson(Map<String, dynamic> json) => StatusSnapshot(
        transactionId: json['transactionId'] as String? ?? '',
        status: TransactionStatus.fromWire(json['status'] as String),
        mode: PaymentMode.fromWire(json['mode'] as String?),
        paymentProvider: json['paymentProvider'] as String?,
        statusReason: json['statusReason'] as String?,
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.tryParse(json['updatedAt'] as String),
      );
}

/// Capabilities reported by GET /api/payment-provider.
class PaymentProviderInfo {
  const PaymentProviderInfo({
    required this.provider,
    required this.simulate,
    required this.production,
  });

  final String provider;
  final bool simulate;
  final bool production;

  factory PaymentProviderInfo.fromJson(Map<String, dynamic> json) {
    final caps = json['capabilities'] as Map<String, dynamic>? ?? {};
    return PaymentProviderInfo(
      provider: json['provider'] as String? ?? 'unknown',
      simulate: caps['simulate'] as bool? ?? false,
      production: caps['production'] as bool? ?? false,
    );
  }
}

/// Thin REST client for the FuelPay backend.
///
/// All calls are short-timeout (tablets live on a LAN demo). Network
/// failures surface as [ApiException] with `isNetwork == true` so callers
/// can fall back to local-only operation.
class FuelPayApiClient {
  FuelPayApiClient({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 4),
  })  : _baseUrl = _normalize(baseUrl),
        _client = client ?? http.Client();

  static const String defaultBaseUrl = 'http://192.168.1.5:3000';

  String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  static String _normalize(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  String get baseUrl => _baseUrl;

  set baseUrl(String url) => _baseUrl = _normalize(url);

  Uri _uri(String path, [Map<String, String>? query]) {
    final Uri uri;
    try {
      uri = Uri.parse('$_baseUrl$path');
    } on FormatException {
      throw ApiException('BAD_URL', 'Invalid backend URL: $_baseUrl');
    }
    return query == null
        ? uri
        : uri.replace(queryParameters: {
            ...uri.queryParameters,
            ...query,
          });
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = _uri(path, query);
    try {
      final http.Response response;
      final headers = {'content-type': 'application/json'};
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers).timeout(timeout);
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(timeout);
        default:
          throw UnsupportedError('method $method');
      }
      final dynamic json;
      try {
        json =
            response.body.isEmpty ? null : jsonDecode(response.body) as dynamic;
      } on FormatException {
        throw ApiException('BAD_RESPONSE', 'Server returned malformed JSON',
            statusCode: response.statusCode);
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json;
      }
      final error = json is Map && json['error'] is Map
          ? json['error'] as Map<String, dynamic>
          : <String, dynamic>{};
      throw ApiException(
        error['code'] as String? ?? 'HTTP_${response.statusCode}',
        error['message'] as String? ??
            'Request failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } on TimeoutException {
      throw ApiException('TIMEOUT',
          'Backend did not respond at $uri within ${timeout.inSeconds}s');
    } on ApiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw ApiException(
          'NETWORK', 'Cannot reach backend at $uri (${e.message})');
    } on FormatException catch (e) {
      throw ApiException('BAD_URL', 'Invalid backend URL: $uri (${e.message})');
    }
  }

  // ------------------------------------------------------------ endpoints

  /// Escape hatch used by the offline sync queue to replay arbitrary
  /// method+path combinations recorded earlier.
  Future<dynamic> raw(String method, String path,
          {Map<String, dynamic>? body}) =>
      _request(method, path, body: body);

  Future<bool> health() async {
    final json = await _request('GET', '/api/health');
    return json is Map && json['status'] == 'ok';
  }

  Future<PaymentProviderInfo> paymentProvider() async {
    final json = await _request('GET', '/api/payment-provider');
    return PaymentProviderInfo.fromJson(json as Map<String, dynamic>);
  }

  Future<FuelTransaction> createTransaction({
    required String transactionId,
    required FuelType fuelType,
    required int amount,
  }) async {
    final json = await _request('POST', '/api/transactions', body: {
      'transactionId': transactionId,
      'fuelType': fuelType.wireName,
      'amount': amount,
      'currency': 'INR',
      'mode': PaymentMode.demo.wireName,
    });
    return FuelTransaction.fromJson(
        (json as Map<String, dynamic>)['transaction'] as Map<String, dynamic>);
  }

  Future<FuelTransaction> getTransaction(String id) async {
    final json = await _request('GET', '/api/transactions/$id');
    return FuelTransaction.fromJson(
        (json as Map<String, dynamic>)['transaction'] as Map<String, dynamic>);
  }

  Future<StatusSnapshot> getStatus(String id) async {
    final json = await _request('GET', '/api/transactions/$id/status');
    return StatusSnapshot.fromJson(json as Map<String, dynamic>);
  }

  /// Generic validated transition (payment outcomes are rejected server-side).
  Future<FuelTransaction> transition(
    String id,
    TransactionStatus status, {
    String? reason,
  }) async {
    final json = await _request('POST', '/api/transactions/$id/status', body: {
      'status': status.wireName,
      if (reason != null) 'reason': reason,
    });
    return FuelTransaction.fromJson(
        (json as Map<String, dynamic>)['transaction'] as Map<String, dynamic>);
  }

  /// Demo payment simulation. Returns the updated transaction.
  /// Throws 409 with code ALREADY_FINALIZED on conflicting replays; callers
  /// should treat an identical-outcome replay as success.
  Future<FuelTransaction> simulateDemoPayment(String id,
      {required bool success}) async {
    final json =
        await _request('POST', '/api/demo-payments/$id/simulate', body: {
      'outcome': success ? 'SUCCESS' : 'FAILED',
    });
    return FuelTransaction.fromJson(
        (json as Map<String, dynamic>)['transaction'] as Map<String, dynamic>);
  }

  Future<List<FuelTransaction>> listTransactions({
    TransactionStatus? status,
    FuelType? fuelType,
    int limit = 100,
    int offset = 0,
  }) async {
    final json = await _request('GET', '/api/transactions', query: {
      if (status != null) 'status': status.wireName,
      if (fuelType != null) 'fuelType': fuelType.wireName,
      'limit': '$limit',
      'offset': '$offset',
    });
    final list =
        (json as Map<String, dynamic>)['transactions'] as List<dynamic>;
    return list
        .map((e) => FuelTransaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void dispose() => _client.close();
}
