import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF111811),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon in green rounded-square — matches adaptive icon shape
                _SplashIcon(),
                SizedBox(height: 24),
                Text(
                  'TableLab',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Your edge, quantified.',
                  style: TextStyle(fontSize: 14, color: Colors.white38),
                ),
              ],
            ),
          ),
          // Thin indeterminate bar at the very bottom
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              minHeight: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashIcon extends StatelessWidget {
  const _SplashIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        // Dark to match the adaptive icon + native splash — the logo art is
        // blue-on-black, so a dark square reads seamlessly and avoids the green
        // flash at launch (the green was the only off-brand colour in the chain).
        color: const Color(0xFF111811),
        borderRadius: BorderRadius.circular(26),
      ),
      padding: const EdgeInsets.all(18),
      child: Image.asset(
        'assets/icon/app_icon.png',
        fit: BoxFit.contain,
      ),
    );
  }
}
