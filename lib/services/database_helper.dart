import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:surveygo/features/surveys/data/models/survey_question_model.dart';
import 'package:surveygo/features/surveys/data/models/survey_response_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  static Completer<Database>? _dbCompleter;

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    if (_dbCompleter != null) return _dbCompleter!.future;

    _dbCompleter = Completer<Database>();
    try {
      _database = await _initDatabase();
      _dbCompleter!.complete(_database);
    } catch (e) {
      _dbCompleter!.completeError(e);
      _dbCompleter = null; // Re-attempt on error
      rethrow;
    }
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      return await openDatabase(
        'surveygo.db',
        version: 2,
        onCreate: _createDb,
      );
    } else if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      databaseFactory = databaseFactoryFfi;
    }

    String path = join(await getDatabasesPath(), 'surveygo.db');
    return await openDatabase(
      path,
      version: 2,
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
        status TEXT DEFAULT 'COMPLETED',
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
      final dateStr = maps[i]['fecha_creacion']?.toString();
      DateTime date = DateTime.now();
      if (dateStr != null && dateStr.isNotEmpty) {
        date = DateTime.tryParse(dateStr) ?? DateTime.now();
      }

      return SurveyRolModel(
        id: maps[i]['id'] is int
            ? maps[i]['id']
            : (int.tryParse(maps[i]['id']?.toString() ?? '0') ?? 0),
        cNombreEncuesta: maps[i]['nombre_encuesta']?.toString() ?? '',
        cTipo: maps[i]['tipo']?.toString() ?? '',
        dFechaCreacion: date,
        idRol: maps[i]['id_rol'] is int
            ? maps[i]['id_rol']
            : (int.tryParse(maps[i]['id_rol']?.toString() ?? '0') ?? 0),
        idFuente: maps[i]['id_fuente'] is int
            ? maps[i]['id_fuente']
            : (int.tryParse(maps[i]['id_fuente']?.toString() ?? '0') ?? 0),
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

  Future<List<Map<String, dynamic>>> getResponsesBySetId(String responseSetId) async {
    final db = await database;
    return await db.query(
      'survey_responses',
      where: 'response_set_id = ?',
      whereArgs: [responseSetId],
    );
  }

  Future<int> updateResponseSetStatus(String responseSetId, String newStatus) async {
    final db = await database;
    return await db.update(
      'survey_responses',
      {'status': newStatus},
      where: 'response_set_id = ?',
      whereArgs: [responseSetId],
    );
  }

  Future<List<Map<String, dynamic>>> getAllSubmissionsGrouped({String? statusFilter}) async {
    final db = await database;
    String query = '''
      SELECT 
        r.response_set_id,
        r.id_encuesta,
        COALESCE(e.nombre_encuesta, 'Encuesta #' || r.id_encuesta) as nombre_encuesta,
        COALESCE(r.status, 'COMPLETED') as status,
        MIN(r.fecha_creacion) as fecha_creacion,
        COUNT(r.id) as total_respuestas,
        (SELECT glgis FROM survey_responses WHERE response_set_id = r.response_set_id AND glgis IS NOT NULL AND glgis != '' LIMIT 1) as glgis_sample
      FROM survey_responses r
      LEFT JOIN encuestas e ON CAST(r.id_encuesta AS INTEGER) = e.id
    ''';

    List<dynamic> args = [];
    if (statusFilter != null && statusFilter.isNotEmpty) {
      query += ' WHERE COALESCE(r.status, "COMPLETED") = ? ';
      args.add(statusFilter);
    }

    query += ' GROUP BY r.response_set_id, r.id_encuesta, e.nombre_encuesta, r.status ORDER BY fecha_creacion DESC';

    try {
      return await db.rawQuery(query, args);
    } catch (_) {
      // Fallback si la columna status aún no existiera en una BD creada previamente
      return await db.rawQuery('''
        SELECT 
          r.response_set_id,
          r.id_encuesta,
          COALESCE(e.nombre_encuesta, 'Encuesta #' || r.id_encuesta) as nombre_encuesta,
          'COMPLETED' as status,
          MIN(r.fecha_creacion) as fecha_creacion,
          COUNT(r.id) as total_respuestas,
          (SELECT glgis FROM survey_responses WHERE response_set_id = r.response_set_id AND glgis IS NOT NULL LIMIT 1) as glgis_sample
        FROM survey_responses r
        LEFT JOIN encuestas e ON CAST(r.id_encuesta AS INTEGER) = e.id
        GROUP BY r.response_set_id, r.id_encuesta, e.nombre_encuesta
        ORDER BY fecha_creacion DESC
      ''');
    }
  }

  Future<int> deleteResponseSet(String responseSetId) async {
    final db = await database;
    return await db.delete(
      'survey_responses',
      where: 'response_set_id = ?',
      whereArgs: [responseSetId],
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
