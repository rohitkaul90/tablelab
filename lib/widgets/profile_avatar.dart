import 'package:flutter/material.dart';

/// A circular profile avatar that shows a network image when one is available
/// and falls back to the user's initials otherwise — including when the image
/// **fails to load** (e.g. offline / DNS lookup failure).
///
/// Why a dedicated widget: a bare `CircleAvatar(backgroundImage: NetworkImage(…))`
/// rethrows the load error during paint when there's no `onBackgroundImageError`,
/// which crashes the app the next time the avatar is painted while offline
/// (Crashlytics crash-issues-10, on the Google `lh3.googleusercontent.com`
/// avatar). Handling the error here flips to the initials fallback instead.
class ProfileAvatar extends StatefulWidget {
  final String? imageUrl;
  final String initials;
  final double radius;
  final Color backgroundColor;
  final TextStyle? initialsStyle;

  const ProfileAvatar({
    super.key,
    required this.imageUrl,
    required this.initials,
    required this.radius,
    required this.backgroundColor,
    this.initialsStyle,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  bool _imageFailed = false;

  @override
  void didUpdateWidget(ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new URL (e.g. account switch) deserves a fresh load attempt.
    if (oldWidget.imageUrl != widget.imageUrl) _imageFailed = false;
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;
    final showImage = url != null && url.isNotEmpty && !_imageFailed;
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      backgroundImage: showImage ? NetworkImage(url) : null,
      // The callback fires asynchronously when the image load fails, so
      // setState here is safe (not during paint). Without it the error would
      // propagate and crash.
      onBackgroundImageError: showImage
          ? (_, _) {
              if (mounted) setState(() => _imageFailed = true);
            }
          : null,
      child: showImage
          ? null
          : Text(widget.initials, style: widget.initialsStyle),
    );
  }
}
