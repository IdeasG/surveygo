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
    final typeUpper = survey.type.toUpperCase();
    IconData typeIcon = Icons.assignment_outlined;
    Color typeColor = AppColors.primaryColor;
    String typeBadge = 'General';

    if (typeUpper.contains('POLYGON') || typeUpper.contains('PREDIO') || typeUpper.contains('AREA')) {
      typeIcon = Icons.crop_square;
      typeColor = const Color(0xFF2E7D32); // Verde esmeralda
      typeBadge = 'Áreas / Polígonos';
    } else if (typeUpper.contains('LINE') || typeUpper.contains('RUTA') || typeUpper.contains('VIA')) {
      typeIcon = Icons.timeline;
      typeColor = const Color(0xFFE65100); // Naranja cálido
      typeBadge = 'Rutas / Distancias';
    } else if (typeUpper.contains('POINT') || typeUpper.contains('PUNTO') || typeUpper.contains('GPS')) {
      typeIcon = Icons.place;
      typeColor = const Color(0xFF1565C0); // Azul
      typeBadge = 'Puntos GPS';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          survey.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                typeBadge,
                                style: TextStyle(
                                  color: typeColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '•  ${survey.questions.length} preguntas',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (survey.description.isNotEmpty && survey.description != 'Tipo: ${survey.type}') ...[
                const SizedBox(height: 10),
                Text(
                  survey.description,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.offline_bolt, size: 16, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'Listo offline',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Iniciar Ficha'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: onTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}