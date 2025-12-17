import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'medubs_v3.db');
    return await openDatabase(
      path,
      version: 2, // Bump Version
      onCreate: _createDB,
      onUpgrade: _onUpgrade, // Handle Migration
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Tabela de Medicamentos Auditáveis (Updated Schema)
    await db.execute('''
      CREATE TABLE medicamentos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        concentracao TEXT,
        forma TEXT,
        lista_origem TEXT NOT NULL,
        data_importacao TEXT NOT NULL
      )
    ''');

    // Tabela de Missões (Gamificação/Checklist)
    await db.execute('''
      CREATE TABLE missoes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        consulta_id TEXT,
        doenca TEXT,
        tarefa TEXT NOT NULL,
        categoria TEXT,
        concluido INTEGER DEFAULT 0
      )
    ''');
  }

  // Safe Migration: Drop & Recreate for dev/cache handling
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS medicamentos');
      await db.execute('''
        CREATE TABLE medicamentos(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          concentracao TEXT,
          forma TEXT,
          lista_origem TEXT NOT NULL,
          data_importacao TEXT NOT NULL
        )
      ''');
    }
  }

  // --- MÉTODOS DE MEDICAMENTOS ---

  Future<Map<String, dynamic>> checarMedicamento(String termo) async {
    final db = await database;
    
    // Busca aproximada sem limitar a 1 para pegar todas as listas
    final List<Map<String, dynamic>> maps = await db.query(
      'medicamentos',
      where: 'nome LIKE ?',
      whereArgs: ['%$termo%'],
    );

    if (maps.isNotEmpty) {
      // Agrega os resultados
      bool emRemume = false;
      bool emRename = false;
      bool emAltoCusto = false;
      String nomeEncontrado = maps.first['nome']; // Assume o primeiro como canônico por enquanto

      for (var item in maps) {
        String lista = (item['lista_origem'] as String).toLowerCase();
        if (lista.contains('remume')) emRemume = true;
        if (lista.contains('rename')) emRename = true;
        if (lista.contains('alto_custo') || lista.contains('estadual')) emAltoCusto = true;
      }

      return {
        'found': true,
        'nome_banco': nomeEncontrado,
        'remume': emRemume,
        'rename': emRename,
        'alto_custo': emAltoCusto,
        'listas_detalhe': maps.map((e) => e['lista_origem']).toList(),
      };
    }
    return {'found': false};
  }
  
  // Método auxiliar para inserir medicamentos em lote (para a API popular)
  Future<void> inserirLoteMedicamentos(List<Map<String, dynamic>> batch) async {
    final db = await database;
    final batchOp = db.batch();
    for (var item in batch) {
      batchOp.insert('medicamentos', item, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batchOp.commit(noResult: true);
  }

  // --- MÉTODOS DE MISSÕES ---

  Future<int> adicionarMissao(Map<String, dynamic> missao) async {
    final db = await database;
    return await db.insert('missoes', missao);
  }

  Future<List<Map<String, dynamic>>> getMissoesPendentes() async {
    final db = await database;
    return await db.query(
      'missoes',
      where: 'concluido = ?',
      whereArgs: [0],
      orderBy: 'id DESC',
    );
  }

  Future<int> marcarMissao(int id, bool concluido) async {
    final db = await database;
    return await db.update(
      'missoes',
      {'concluido': concluido ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> limparMissoesDeConsulta(String consultaId) async {
    final db = await database;
    await db.delete('missoes', where: 'consulta_id = ?', whereArgs: [consultaId]);
  }
}
