import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/connectivity_service.dart';

class NetworkStatusBanner extends StatefulWidget {
  const NetworkStatusBanner({super.key});

  @override
  State<NetworkStatusBanner> createState() => _NetworkStatusBannerState();
}

class _NetworkStatusBannerState extends State<NetworkStatusBanner> {
  final ConnectivityService _connectivity = ConnectivityService();
  StreamSubscription<ConnectivityStatus>? _sub;

  ConnectivityStatus _status = ConnectivityStatus.online;
  bool _showRestoredBanner = false;
  bool _dismissedSlow = false;
  Timer? _restoredTimer;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _status = _connectivity.status;
    _sub = _connectivity.statusStream.listen((newStatus) {
      if (!mounted) return;
      if (_status == ConnectivityStatus.offline &&
          newStatus == ConnectivityStatus.online) {
        _showRestoredBanner = true;
        _restoredTimer?.cancel();
        _restoredTimer = Timer(const Duration(milliseconds: 2800), () {
          if (mounted) {
            setState(() {
              _showRestoredBanner = false;
            });
          }
        });
      }
      if (newStatus == ConnectivityStatus.slow) {
        _dismissedSlow = false;
        _slowTimer?.cancel();
        _slowTimer = Timer(const Duration(milliseconds: 3500), () {
          if (mounted) {
            setState(() {
              _dismissedSlow = true;
            });
          }
        });
      }
      setState(() {
        _status = newStatus;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _restoredTimer?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOffline = _status == ConnectivityStatus.offline;
    final isSlow = _status == ConnectivityStatus.slow && !_dismissedSlow;
    final showBanner = isOffline || isSlow || _showRestoredBanner;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          axis: Axis.vertical,
          child: child,
        );
      },
      child: showBanner
          ? SafeArea(
              bottom: false,
              child: Container(
                key: ValueKey('banner_${_status}_$_showRestoredBanner'),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: isOffline
                      ? const Color(0xFF991B1B)
                      : (isSlow
                          ? const Color(0xFFB45309)
                          : const Color(0xFF065F46)),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      isOffline
                          ? Icons.wifi_off_rounded
                          : (isSlow
                              ? Icons.network_check_rounded
                              : Icons.wifi_rounded),
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isOffline
                            ? 'No internet connection - operating offline'
                            : (isSlow
                                ? 'Slow connection - streaming may buffer'
                                : 'Back online - connection restored'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isOffline)
                      GestureDetector(
                        onTap: () => _connectivity.checkConnectivity(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if (isSlow)
                      GestureDetector(
                        onTap: () => setState(() => _dismissedSlow = true),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('empty_banner')),
    );
  }
}
