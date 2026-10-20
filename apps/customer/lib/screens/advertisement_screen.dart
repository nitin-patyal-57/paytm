import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';
import 'package:video_player/video_player.dart';

import '../services/transaction_flow.dart';

/// Stage 7: the five-second post-payment advertisement (success only).
///
/// Plays `assets/ads/promo.mp4` when present; falls back to a branded
/// motion card when the asset is missing. Marked as played per transaction
/// so it can never run twice for the same payment.
class AdvertisementScreen extends StatefulWidget {
  const AdvertisementScreen({super.key, required this.flow});

  final CustomerTransactionFlow flow;

  @override
  State<AdvertisementScreen> createState() => _AdvertisementScreenState();
}

class _AdvertisementScreenState extends State<AdvertisementScreen> {
  static const Duration _adDuration = Duration(seconds: 5);

  VideoPlayerController? _video;
  bool _videoReady = false;
  Timer? _timer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final tx = widget.flow.active;
    if (tx == null || widget.flow.advertisementPlayed) {
      // Never replay an advertisement for the same transaction.
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return;
    }
    _timer = Timer(_adDuration, _finish);
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.asset('assets/ads/promo.mp4');
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = controller;
        _videoReady = true;
      });
    } catch (_) {
      // Asset missing or unsupported — the branded fallback stays visible.
      _videoReady = false;
    }
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    final tx = widget.flow.active;
    if (tx != null) {
      await widget.flow.store.markAdvertisementPlayed(tx.transactionId);
    }
    if (mounted) widget.flow.resetTransaction();
  }

  @override
  void dispose() {
    _timer?.cancel();
    final video = _video;
    if (video != null) {
      video.pause();
      video.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FuelPayColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              if (_videoReady && _video != null) ...[
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
                    child: AspectRatio(
                      aspectRatio: _video!.value.aspectRatio == 0
                          ? 16 / 9
                          : _video!.value.aspectRatio,
                      child: VideoPlayer(_video!),
                    ),
                  ),
                ),
              ] else
                const _FallbackAd(),
              const SizedBox(height: 32),
              const Text(
                'Advertisement',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: _adDuration,
                curve: Curves.linear,
                builder: (context, value, _) => Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _finish,
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Branded fallback shown when the promo video asset is unavailable.
class _FallbackAd extends StatelessWidget {
  const _FallbackAd();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1.06),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeInOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              Icons.local_gas_station_rounded,
              size: 76,
              color: FuelPayColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'FuelPay',
          style: TextStyle(
            color: Colors.white,
            fontSize: 44,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Fill up. Tap. Go.',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'Skip the queue — pay from your tablet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
