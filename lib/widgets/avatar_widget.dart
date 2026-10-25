import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants.dart';

class AvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;
  final double size;
  final bool isOnline;

  const AvatarWidget({
    super.key,
    this.avatarUrl,
    required this.displayName,
    this.size = 48,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    
    // Consistent color derived from name hash
    final hash = displayName.codeUnits.fold(0, (acc, c) => acc + c);
    final colors = [
      Colors.teal,
      Colors.blueGrey,
      Colors.indigo,
      Colors.deepPurple,
      Colors.blue,
      Colors.cyan,
      Colors.amber.shade900,
    ];
    final bgColor = colors[hash % colors.length];

    Widget avatarContent;
    if (avatarUrl != null && avatarUrl!.startsWith('http')) {
      avatarContent = CachedNetworkImage(
        imageUrl: avatarUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: size,
          height: size,
          color: bgColor,
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: size,
          height: size,
          color: bgColor,
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      );
    } else {
      avatarContent = Container(
        width: size,
        height: size,
        color: bgColor,
        alignment: Alignment.center,
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: avatarContent,
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: const Color(AppConstants.primaryColorHex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(AppConstants.backgroundColorHex),
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
