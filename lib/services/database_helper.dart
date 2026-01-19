import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:surveygo/features/surveys/data/models/survey_question_model.dart';
import 'package:surveygo/features/surveys/data/models/survey_response_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'surveygo.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDb,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE encuestas(
        id INTEGER PRIMARY KEY,
        nombre_encuesta TEXT,
        tipo TEXT,
        fecha_creacion TEXT,
        id_rol INTEGER,
        id_fuente INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE preguntas(
        id INTEGER PRIMARY KEY,
        id_encuesta INTEGER,
        c_campo TEXT,
        c_pregunta TEXT,
        c_tipo TEXT,
        j_opciones TEXT,
        FOREIGN KEY (id_encuesta) REFERENCES encuestas (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE survey_responses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_encuesta TEXT NOT NULL,
        id_pregunta TEXT NOT NULL,
        c_tipo_pregunta TEXT NOT NULL,
        c_respuesta TEXT,
        c_nombre_file TEXT,
        c_extension TEXT,
        glgis TEXT,
        response_set_id TEXT,
        fecha_creacion TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  // Insertar una encuesta
  Future<int> insertSurvey(SurveyRolModel survey) async {
    final db = await database;
    return await db.insert(
      'encuestas',
      survey.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Insertar múltiples encuestas
  Future<void> insertSurveys(List<SurveyRolModel> surveys) async {
    final db = await database;
    Batch batch = db.batch();

    for (var survey in surveys) {
      batch.insert(
        'encuestas',
        survey.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // Obtener todas las encuestas
  Future<List<SurveyRolModel>> getSurveys() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('encuestas');

    return List.generate(maps.length, (i) {
      return SurveyRolModel(
        id: maps[i]['id'],
        cNombreEncuesta: maps[i]['nombre_encuesta'],
        cTipo: maps[i]['tipo'],
        dFechaCreacion: DateTime.parse(maps[i]['fecha_creacion']),
        idRol: maps[i]['id_rol'],
        idFuente: maps[i]['id_fuente'],
      );
    });
  }

  // Eliminar todas las encuestas
  Future<int> deleteAllSurveys() async {
    final db = await database;
    return await db.delete('encuestas');
  }

  // Insertar preguntas de una encuesta
  Future<void> insertQuestions(List<SurveyQuestionModel> questions) async {
    final db = await database;
    Batch batch = db.batch();

    for (var question in questions) {
      batch.insert(
        'preguntas',
        question.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // Obtener preguntas de una encuesta
  Future<List<SurveyQuestionModel>> getQuestions(int surveyId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'preguntas',
      where: 'id_encuesta = ?',
      whereArgs: [surveyId],
    );

    return List.generate(maps.length, (i) {
      return SurveyQuestionModel.fromMap(maps[i]);
    });
  }

  // Eliminar todas las preguntas
  Future<int> deleteAllQuestions() async {
    final db = await database;

    // Verificar si la tabla existe antes de intentar eliminarla
    var tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='preguntas';");
    if (tables.isEmpty) {
      // La tabla no existe, así que no hay nada que eliminar
      print('La tabla preguntas no existe, creándola...');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS preguntas(
          id INTEGER PRIMARY KEY,
          id_encuesta INTEGER,
          c_campo TEXT,
          c_pregunta TEXT,
          c_tipo TEXT,
          j_opciones TEXT,
          FOREIGN KEY (id_encuesta) REFERENCES encuestas (id) ON DELETE CASCADE
        )
      ''');
      return 0;
    }

    return await db.delete('preguntas');
  }

  Future<int> insertResponse(Map<String, dynamic> response) async {
    final db = await database;

    // Si no tiene response_set_id, le asignamos uno basado en la fecha actual
    if (!response.containsKey('response_set_id') ||
        response['response_set_id'] == null) {
      response['response_set_id'] =
          DateTime.now().millisecondsSinceEpoch.toString();
    }

    return await db.insert('survey_responses', response);
  }

  Future<List<Map<String, dynamic>>> getResponsesBySurvey(
      String surveyId) async {
    final db = await database;
    return await db.query(
      'survey_responses',
      where: 'id_encuesta = ?',
      whereArgs: [surveyId],
    );
  }

  Future<int> deleteResponsesBySurvey(String surveyId,
      {String? responseSetId}) async {
    final db = await database;

    if (responseSetId != null) {
      // Si se proporciona un responseSetId, solo eliminar ese conjunto de respuestas
      return await db.delete(
        'survey_responses',
        where: 'id_encuesta = ? AND response_set_id = ?',
        whereArgs: [surveyId, responseSetId],
      );
    } else {
      // Comportamiento anterior: eliminar todas las respuestas de la encuesta
      return await db.delete(
        'survey_responses',
        where: 'id_encuesta = ?',
        whereArgs: [surveyId],
      );
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
