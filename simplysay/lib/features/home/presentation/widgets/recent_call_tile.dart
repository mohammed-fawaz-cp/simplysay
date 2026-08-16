import 'package:flutter/material.dart';
import '../../domain/models/call_record.dart';

class RecentCallTile extends StatelessWidget {
  final CallRecord record;
  final VoidCallback onTap;

  const RecentCallTile({
    super.key,
    required this.record,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMissed = record.type == CallType.missed;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            // User Avatar / Profile Image
            CircleAvatar(
              radius: 24,
              backgroundColor: isMissed
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.secondaryContainer,
              backgroundImage: (record.avatarUrl != null && record.avatarUrl!.isNotEmpty)
                  ? NetworkImage(record.avatarUrl!)
                  : null,
              child: (record.avatarUrl == null || record.avatarUrl!.isEmpty)
                  ? Text(
                      record.initials,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isMissed
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onSecondaryContainer,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),

            // Call Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isMissed
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _getCallIcon(record.type, theme),
                      if (record.type != CallType.message)
                        const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          record.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isMissed
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Timestamp & Call Action Button
            Text(
                  record.timestamp,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _getCallIcon(CallType type, ThemeData theme) {
    switch (type) {
      case CallType.missed:
        return Icon(Icons.call_missed, size: 16, color: theme.colorScheme.error);
      case CallType.incoming:
        return Icon(Icons.call_received, size: 16, color: theme.colorScheme.onSurfaceVariant);
      case CallType.outgoing:
        return Icon(Icons.call_made, size: 16, color: theme.colorScheme.onSurfaceVariant);
      case CallType.message:
        return const SizedBox.shrink();
    }
  }
}
