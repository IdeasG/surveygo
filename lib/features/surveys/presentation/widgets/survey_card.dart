import 'package:flutter/material.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/surveys/data/models/survey_model.dart';

class SurveyCard extends StatelessWidget {
  final SurveyModel survey;
  final VoidCallback onTap;

  const SurveyCard({
    Key? key,
    required this.survey,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 4,
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
                  const Icon(Icons.assignment, color: AppColors.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      survey.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: survey.isCompleted
                          ? AppColors.successColor
                          : AppColors.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      survey.isCompleted ? 'Completada' : 'Pendiente',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                survey.description,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                '${survey.questions.length} preguntas',
                style: const TextStyle(color: AppColors.primaryColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}