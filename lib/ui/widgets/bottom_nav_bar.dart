import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkCanvas.withValues(alpha: 0.96)
            : AppColors.lightCanvas.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildTab(
            index: 0,
            icon: Icons.home_rounded,
            label: 'Home',
            isActive: currentIndex == 0,
          ),
          _buildTab(
            index: 1,
            icon: Icons.search_rounded,
            label: 'Search',
            isActive: currentIndex == 1,
          ),
          _buildTab(
            index: 2,
            icon: Icons.library_music_rounded,
            label: 'Library',
            isActive: currentIndex == 2,
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required int index,
    required IconData icon,
    required String label,
    required bool isActive,
  }) {
    return InkWell(
      onTap: () => onTabSelected(index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isActive ? AppColors.primary : AppColors.darkTextTertiary,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                color:
                    isActive ? AppColors.primary : AppColors.darkTextTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
