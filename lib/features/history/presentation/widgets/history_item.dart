import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/history/data/models/history_model.dart';

class HistoryItem extends StatelessWidget {
  final HistoryModel historyItem;
  final VoidCallback onTap;

  const HistoryItem({
    Key? key,
    required this.historyItem,
    required this.onTap,
    required String subtitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final formattedDate = dateFormat.format(historyItem.completedDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.successColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      historyItem.survey.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Completada: $formattedDate',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
