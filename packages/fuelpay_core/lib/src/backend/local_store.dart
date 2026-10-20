import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/fuel_transaction.dart';
import '../models/fuel_type.dart';
import '../models/transaction_status.dart';
import '../protocol/ble_constants.dart';
import '../validation/transaction_id.dart';
import 'api_client.dart';

/// A queued backend call made while the backend was unreachable.
class SyncJob {
  SyncJob(
      {required this.method,
      required this.path,
      required this.body,
      this.attempts = 0});

  final String method;
  final String path;
  final Map<String, dynamic> body;
  int attempts;

  Map<String, dynamic> toJson() => {
        'method': method,
        'path': path,
        'body': body,
        'attempts': attempts,
      };

  factory SyncJob.fromJson(Map<String, dynamic> json) => SyncJob(
        method: json['method'] as String,
        path: json['path'] as String,
        body: Map<String, dynamic>.from(json['body'] as Map),
        attempts: json['attempts'] as int? ?? 0,
      );
}

/// Persistent local transaction store (SharedPreferences-backed).
///
/// Responsibilities:
///  - restart recovery (active transaction + full history),
///  - "advertisement already played" bookkeeping (once per transaction),
///  - backend URL configuration,
///  - a small offline sync queue for best-effort backend replication.
class LocalTransactionStore {
  LocalTransactionStore._(this._prefs);

  static const String _kTransactions = 'fp_transactions_v1';
  static const String _kActiveId = 'fp_active_transaction_id_v1';
  static const String _kAdPlayed = 'fp_ad_played_v1';
  static const String _kBackendUrl = 'fp_backend_url_v1';
  static const String _kSyncQueue = 'fp_sync_queue_v1';
  static const String _kDeviceAlias = 'fp_device_alias_v1';

  static const int maxStoredTransactions = 300;

  final SharedPreferences _prefs;

  static Future<LocalTransactionStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalTransactionStore._(prefs);
  }

  // ------------------------------------------------------------ transactions

  List<FuelTransaction> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) =>
              FuelTransaction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on Exception {
      return [];
    }
  }

  Future<void> saveTransaction(FuelTransaction tx) async {
    final list = _decodeList(_prefs.getString(_kTransactions));
    final index = list.indexWhere((t) => t.transactionId == tx.transactionId);
    if (index >= 0) {
      list[index] = tx;
    } else {
      list.insert(0, tx);
    }
    if (list.length > maxStoredTransactions) {
      list.removeRange(maxStoredTransactions, list.length);
    }
    await _prefs.setString(
        _kTransactions, jsonEncode(list.map((t) => t.toJson()).toList()));
  }

  List<FuelTransaction> transactions(
      {TransactionStatus? status, FuelType? fuelType}) {
    var list = _decodeList(_prefs.getString(_kTransactions));
    if (status != null) list = list.where((t) => t.status == status).toList();
    if (fuelType != null)
      list = list.where((t) => t.fuelType == fuelType).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  FuelTransaction? transaction(String id) {
    final list = _decodeList(_prefs.getString(_kTransactions));
    for (final t in list) {
      if (t.transactionId == id) return t;
    }
    return null;
  }

  bool hasTransaction(String id) => transaction(id) != null;

  bool get hasAnyTransaction => _prefs.containsKey(_kTransactions);

  // -------------------------------------------------------- active pointer

  String? get activeTransactionId {
    final id = _prefs.getString(_kActiveId);
    if (id == null || !TransactionId.isValid(id)) return null;
    return transaction(id) == null ? null : id;
  }

  Future<void> setActiveTransactionId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kActiveId);
    } else {
      await _prefs.setString(_kActiveId, id);
    }
  }

  /// Returns the active transaction when it is still in a non-terminal state
  /// (used for restart recovery).
  FuelTransaction? recoverActiveTransaction() {
    final id = activeTransactionId;
    if (id == null) return null;
    final tx = transaction(id);
    if (tx == null || tx.status.isTerminal) return null;
    return tx;
  }

  // -------------------------------------------------------------- ad marker

  Set<String> _adPlayed() {
    final raw = _prefs.getString(_kAdPlayed);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } on Exception {
      return <String>{};
    }
  }

  /// True when the five-second advertisement already played for this
  /// transaction (prevents double playback across restarts).
  bool hasPlayedAdvertisement(String transactionId) =>
      _adPlayed().contains(transactionId);

  Future<void> markAdvertisementPlayed(String transactionId) async {
    final set = _adPlayed()..add(transactionId);
    while (set.length > 50) {
      set.remove(set.first);
    }
    await _prefs.setString(_kAdPlayed, jsonEncode(set.toList()));
  }

  // ----------------------------------------------------------- backend URL

  String get backendUrl =>
      _prefs.getString(_kBackendUrl) ?? FuelPayApiClient.defaultBaseUrl;

  Future<void> setBackendUrl(String url) async {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    await _prefs.setString(_kBackendUrl, u);
  }

  // ------------------------------------------------------------ device alias

  /// Stable short BLE alias of this device (e.g. "FP-7A3C"). Generated once
  /// and reused so customers always see the same pump identity.
  String? get deviceAlias {
    final alias = _prefs.getString(_kDeviceAlias);
    return FuelPayBle.isValidAlias(alias) ? alias : null;
  }

  Future<void> setDeviceAlias(String alias) async {
    if (!FuelPayBle.isValidAlias(alias)) {
      throw ArgumentError.value(alias, 'alias', 'Invalid FuelPay alias');
    }
    await _prefs.setString(_kDeviceAlias, alias);
  }

  // ------------------------------------------------------------ sync queue

  List<SyncJob> get pendingSyncJobs {
    final raw = _prefs.getString(_kSyncQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => SyncJob.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on Exception {
      return [];
    }
  }

  Future<void> _writeSyncJobs(List<SyncJob> jobs) async {
    await _prefs.setString(
        _kSyncQueue, jsonEncode(jobs.map((j) => j.toJson()).toList()));
  }

  Future<void> enqueueSync(SyncJob job) async {
    final jobs = pendingSyncJobs;
    // Collapse duplicates (same method+path+body) — only latest is kept.
    jobs.removeWhere((j) =>
        j.method == job.method &&
        j.path == job.path &&
        j.body.toString() == job.body.toString());
    jobs.add(job);
    if (jobs.length > 60) jobs.removeRange(0, jobs.length - 60);
    await _writeSyncJobs(jobs);
  }

  Future<void> removeSyncJob(SyncJob job) async {
    final jobs = pendingSyncJobs;
    jobs.removeWhere((j) =>
        j.method == job.method &&
        j.path == job.path &&
        j.body.toString() == job.body.toString());
    await _writeSyncJobs(jobs);
  }

  Future<void> replaceSyncJob(SyncJob oldJob, SyncJob newJob) async {
    final jobs = pendingSyncJobs;
    final index = jobs.indexWhere((j) =>
        j.method == oldJob.method &&
        j.path == oldJob.path &&
        j.body.toString() == oldJob.body.toString());
    if (index >= 0) {
      jobs[index] = newJob;
    } else {
      jobs.add(newJob);
    }
    await _writeSyncJobs(jobs);
  }

  Future<void> clearAll() async {
    for (final key in [_kTransactions, _kActiveId, _kAdPlayed, _kSyncQueue]) {
      await _prefs.remove(key);
    }
  }
}

/// Best-effort flush of queued backend calls.
///
/// 4xx responses mean the server already knows (duplicate) or rejects the
/// job permanently — drop it. Network problems keep the job for later.
Future<int> flushSyncQueue(
    FuelPayApiClient api, LocalTransactionStore store) async {
  var flushed = 0;
  final jobs = List<SyncJob>.from(store.pendingSyncJobs);
  for (final job in jobs) {
    try {
      await api.raw(job.method, job.path, body: job.body);
      await store.removeSyncJob(job);
      flushed++;
    } on ApiException catch (e) {
      if (e.statusCode != null && e.statusCode! >= 400 && e.statusCode! < 500) {
        // Permanent server-side rejection (or already applied) — drop.
        await store.removeSyncJob(job);
      } else {
        job.attempts += 1;
        if (job.attempts > 8) {
          await store.removeSyncJob(job);
        } else {
          await store.replaceSyncJob(job, job);
        }
      }
    } catch (_) {
      break; // backend still unreachable — stop trying
    }
  }
  return flushed;
}
