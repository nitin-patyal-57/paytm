import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/ble_central_service.dart';
import '../services/transaction_flow.dart';
import '../widgets/shell.dart';

/// Stage 3: Bluetooth scan + connect. On a successful handshake the flow
/// advances to the QR stage.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.flow, required this.ble});

  final CustomerTransactionFlow flow;
  final BleCentralService ble;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _permissionDenied = false;
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final granted = await _requestPermissions();
    if (!mounted) return;
    setState(() => _permissionDenied = !granted);
    if (granted) {
      await widget.ble.startScan();
    }
  }

  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    final allGranted = statuses.values.every((s) => s.isGranted);
    if (allGranted) return true;
    // Plugin fallback (handles OEM/older Android variants).
    return widget.ble.requestPermissions();
  }

  Future<void> _connect(DiscoveredPump pump) async {
    setState(() => _connectingId = pump.address);
    final ok = await widget.ble.connect(pump);
    if (!mounted) return;
    setState(() => _connectingId = null);
    if (ok) {
      await widget.flow.onPumpConnected();
    }
  }

  Future<void> _leave() async {
    final flow = widget.flow;
    if (flow.active != null && !flow.active!.status.isTerminal) {
      final confirmed = await confirmDiscard(context);
      if (!confirmed || !mounted) return;
      await flow.cancelActive();
    }
    if (mounted) flow.go(FlowStage.amount);
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final ble = widget.ble;
    final pumps = ble.pumps;
    final connecting = ble.phase == BleConnectionPhase.connecting;
    final failed = ble.phase == BleConnectionPhase.error;
    return StageScaffold(
      title: 'Find your pump',
      onBack: _leave,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (flow.error != null) ...[
            ErrorBanner(message: flow.error!, onDismiss: flow.clearError),
            const SizedBox(height: 16),
          ],
          _TransactionSummary(transaction: flow.active),
          const SizedBox(height: 16),
          if (_permissionDenied) ...[
            ErrorBanner(
              message: 'Bluetooth permission is required to find pumps.',
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Open system settings',
              style: AppButtonStyle.outlined,
              onPressed: () => ble.openSystemSettings(),
            ),
            const SizedBox(height: 8),
          ] else if (ble.lastError != null && !connecting) ...[
            ErrorBanner(message: ble.lastError!),
            const SizedBox(height: 12),
          ] else if (failed) ...[
            ErrorBanner(message: ble.lastError ?? 'Connection failed.'),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              ConnectionBadge(
                connected: ble.isConnected,
                busy: connecting,
                label: ble.isConnected
                    ? (flow.pumpName ?? 'Connected')
                    : connecting
                    ? 'Connecting…'
                    : ble.scanning
                    ? 'Scanning…'
                    : 'Not connected',
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: ble.scanning
                    ? ble.stopScan
                    : () async {
                        setState(() => _permissionDenied = false);
                        final granted = await _requestPermissions();
                        if (!mounted) return;
                        setState(() => _permissionDenied = !granted);
                        if (granted) await ble.startScan();
                      },
                icon: Icon(
                  ble.scanning ? Icons.stop : Icons.bluetooth_searching,
                  size: 20,
                ),
                label: Text(ble.scanning ? 'Stop scan' : 'Scan again'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (pumps.isEmpty && !ble.scanning && !_permissionDenied)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No pumps found yet.\nMake sure the pump tablet is '
                  'advertising and tap “Scan again”.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: FuelPayColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            )
          else
            ...pumps.map(
              (pump) => _PumpTile(
                pump: pump,
                connecting: _connectingId == pump.address && connecting,
                enabled: !connecting && !ble.isConnected,
                onConnect: () => _connect(pump),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _TransactionSummary extends StatelessWidget {
  const _TransactionSummary({required this.transaction});

  final FuelTransaction? transaction;

  @override
  Widget build(BuildContext context) {
    if (transaction == null) return const SizedBox.shrink();
    final tx = transaction!;
    return SectionCard(
      child: Row(
        children: [
          StatusChip(tx.status),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '${tx.fuelType.label} · ₹${AmountValidator.format(tx.amount)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: FuelPayColors.textPrimary,
              ),
            ),
          ),
          Text(
            tx.transactionId,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: FuelPayColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PumpTile extends StatelessWidget {
  const _PumpTile({
    required this.pump,
    required this.connecting,
    required this.enabled,
    required this.onConnect,
  });

  final DiscoveredPump pump;
  final bool connecting;
  final bool enabled;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FuelPayColors.surface,
        borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
        border: Border.all(color: FuelPayColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: FuelPayColors.infoBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.local_gas_station_rounded,
              color: FuelPayColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pump.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: FuelPayColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  pump.alias == null
                      ? pump.address
                      : '${pump.alias} · signal ${pump.rssi} dBm',
                  style: const TextStyle(
                    fontSize: 13,
                    color: FuelPayColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (connecting)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            )
          else
            AppButton(
              label: 'Connect',
              expand: false,
              icon: Icons.bluetooth,
              onPressed: enabled ? onConnect : null,
            ),
        ],
      ),
    );
  }
}
