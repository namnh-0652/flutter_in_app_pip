import 'package:flutter/material.dart';
import 'package:flutter_in_app_pip/flutter_in_app_pip.dart';

class InAppPip extends StatelessWidget {
  const InAppPip({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          const AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.amber,
            ),
          ),
          ColoredBox(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => PictureInPicture.stopPiP(),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(
                Icons.close,
                size: 24,
                color: Colors.white,
              ),
              onPressed: () => PictureInPicture.stopPiP(),
            ),
          ),
        ],
      ),
    );
  }
}
