class SurveyModel {
  final int id;
  final String title;
  final String description;
  final String type;
  final String workspace;
  final String layer;
  final List<QuestionModel> questions;
  final bool isCompleted;

  SurveyModel({
    required this.id,
    required this.title,
    required this.description,
    this.type = '',
    this.workspace = '',
    this.layer = '',
    required this.questions,
    this.isCompleted = false,
  });

  factory SurveyModel.fromJson(Map<String, dynamic> json) {
    return SurveyModel(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] ?? '',
      workspace: json['workspace'] ?? '',
      layer: json['layer'] ?? '',
      questions: (json['questions'] as List? ?? [])
          .map((q) => QuestionModel.fromJson(q))
          .toList(),
      isCompleted: json['is_completed'] ?? false,
    );
  }
}

class QuestionModel {
  final int id;
  final String text;
  final String type; // 'multiple_choice', 'text', etc.
  final List<OptionModel> options;
  String? answer;

  QuestionModel({
    required this.id,
    required this.text,
    required this.type,
    required this.options,
    this.answer,
  });

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      id: json['id'] ?? 0,
      text: json['text'] ?? '',
      type: json['type'] ?? 'text',
      options: (json['options'] as List? ?? [])
          .map((o) => OptionModel.fromJson(o))
          .toList(),
      answer: json['answer'],
    );
  }
}

class OptionModel {
  final int id;
  final String text;

  OptionModel({
    required this.id,
    required this.text,
  });

  factory OptionModel.fromJson(Map<String, dynamic> json) {
    return OptionModel(
      id: json['id'] ?? 0,
      text: json['text'] ?? '',
    );
  }
}