import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:diacritic/diacritic.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MedUBSApp());
}

class MedUBSApp extends StatelessWidget {
  const MedUBSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedUBS v2.2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0052CC),
          primary: const Color(0xFF0052CC), 
          secondary: const Color(0xFF00BFA5), 
          surface: Colors.white,
          background: const Color(0xFFF7F9FC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        cardTheme: CardTheme(
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.05),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0052CC),
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final _apiKeyController = TextEditingController();
  int? _patientAge;
  String _patientSex = "Feminino";
  final GlobalKey<_OfflineTabState> _offlineTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
      // If empty, we NO LONGER force the dialog immediately on init to avoid blocking the view of the beautiful UI.
      // We will let the user explore and click "Configure" when they try to use an AI feature.
    });
  }

  void _updateDemographics(int? age, String? sex) {
    if (age != null || sex != null) {
      if (mounted) {
        setState(() {
          if (age != null) _patientAge = age;
          if (sex != null) _patientSex = sex;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Rastreio atualizado: $_patientSex, $_patientAge anos"),
          backgroundColor: Colors.teal,
          action: SnackBarAction(label: "VER", textColor: Colors.white, onPressed: () => setState(() => _currentIndex = 3)),
        ));
      }
    }
  }

  void _notifyOfflineFileSaved() {
    _offlineTabKey.currentState?.loadFiles(); 
  }

  void _showSettings(BuildContext context) {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Configurações Globais"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
               controller: _apiKeyController,
               decoration: const InputDecoration(labelText: "Gemini API Key", border: OutlineInputBorder(), prefixIcon: Icon(Icons.key)),
               obscureText: true,
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                 final Uri url = Uri.parse("https://aistudio.google.com/app/api-keys");
                 if (!await launchUrl(url)) {}
              },
              child: const Row(children: [Icon(Icons.help_outline, size: 16, color: Colors.blue), SizedBox(width: 4), Text("Obter Chave", style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline))]),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('gemini_api_key', _apiKeyController.text);
            setState(() {}); // Trigger rebuild to update 'hasKey'
            if (context.mounted) Navigator.pop(ctx);
          }, child: const Text("SALVAR"))
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    bool hasKey = _apiKeyController.text.isNotEmpty;

    final pages = [
      HomeTab(
        apiKey: _apiKeyController.text, 
        hasKey: hasKey,
        onMetaDataFound: _updateDemographics,
        onFileSaved: _notifyOfflineFileSaved,
        onRequestKey: () => _showSettings(context),
      ),
      LiveTab(apiKey: _apiKeyController.text, hasKey: hasKey),
      SpecialtiesTab(apiKey: _apiKeyController.text, hasKey: hasKey),
      ScreeningTab(
        apiKey: _apiKeyController.text,
        hasKey: hasKey,
        initialAge: _patientAge,
        initialSex: _patientSex,
        onRequestKey: () => _showSettings(context),
      ),
      OfflineTab(key: _offlineTabKey, apiKey: _apiKeyController.text),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() => _currentIndex = idx);
          if (idx == 4) _offlineTabKey.currentState?.loadFiles();
        },
        indicatorColor: hasKey ? Colors.blue[100] : Colors.grey[300],
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: "Início"),
          NavigationDestination(icon: Icon(Icons.mic_external_on_outlined), selectedIcon: Icon(Icons.mic_external_on), label: "Ao Vivo"),
          NavigationDestination(icon: Icon(Icons.medical_services_outlined), selectedIcon: Icon(Icons.medical_services), label: "Espec."),
          NavigationDestination(icon: Icon(Icons.checklist_rtl_outlined), selectedIcon: Icon(Icons.checklist_rtl), label: "Rastreio"),
          NavigationDestination(icon: Icon(Icons.wifi_off_outlined), selectedIcon: Icon(Icons.wifi_off), label: "Offline"),
        ],
      ),
    );
  }
}

// ---------------- HOME TAB ----------------
class HomeTab extends StatefulWidget {
  final String apiKey;
  final bool hasKey;
  final Function(int?, String?) onMetaDataFound;
  final VoidCallback onFileSaved;
  final VoidCallback onRequestKey;

  const HomeTab({
    super.key, 
    required this.apiKey, 
    required this.hasKey,
    required this.onMetaDataFound,
    required this.onFileSaved,
    required this.onRequestKey,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _audioRecorder = Record();
  bool _isRecording = false;
  bool _isProcessing = false;
  String? _currentAudioPath;
  Map<String, dynamic>? _analysisResult;
  String _statusText = "Pronto";
  
  // State for DBs removed for brevity in this full-write tool but included in real app
  List<String> _dbRemumeNames = [];
  List<String> _dbRenameNames = [];
  List<String> _dbAltoCustoNames = [];

  @override
  void initState() {
    super.initState();
    _loadDatabases();
  }

  Future<void> _loadDatabases() async {
    try {
      List<String> extractNames(dynamic json) {
        List<String> names = [];
        if (json is List) {
          for (var item in json) {
             if (item is Map && (item.containsKey('nome') || item.containsKey('nome_completo'))) {
               names.add((item['nome'] ?? item['nome_completo']).toString());
             } else if (item is Map && item.containsKey('itens') && item['itens'] is List) {
               for (var subItem in item['itens']) if (subItem is Map) names.add(subItem['nome'].toString());
             }
          }
        }
        return names;
      }
      final remume = json.decode(await rootBundle.loadString('assets/db_remume.json'));
      final rename = json.decode(await rootBundle.loadString('assets/db_rename.json'));
      final alto = json.decode(await rootBundle.loadString('assets/db_alto_custo.json'));
      if(mounted) setState(() {
        _dbRemumeNames = extractNames(remume);
        _dbRenameNames = extractNames(rename);
        _dbAltoCustoNames = extractNames(alto);
      });
    } catch (_) {}
  }

  Future<String> _saveToSafeStorage(String tempPath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final safeDir = Directory('${appDir.path}/medubs_logs');
      if (!await safeDir.exists()) await safeDir.create(recursive: true);
      final fileName = "consulta_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.m4a";
      final safePath = "${safeDir.path}/$fileName";
      await File(tempPath).copy(safePath);
      widget.onFileSaved();
      return safePath;
    } catch (e) {
      return tempPath;
    }
  }

  Future<void> _toggleRecording() async {
    if (!widget.hasKey && !_isRecording) {
      widget.onRequestKey();
      return;
    }

    if (_isRecording) {
      final path = await _audioRecorder.stop();
      if (path != null) {
        final safePath = await _saveToSafeStorage(path);
        setState(() { 
          _isRecording = false; 
          _currentAudioPath = safePath; 
          _statusText = "Gravado e Salvo."; 
        });
      }
    } else {
      if (await Permission.microphone.request().isGranted) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/temp_rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(path: path, encoder: AudioEncoder.aacLc);
        setState(() { _isRecording = true; _statusText = "Gravando..."; _analysisResult = null; });
      }
    }
  }

  Future<void> _analyze() async {
    if (!widget.hasKey) { widget.onRequestKey(); return; }
    if (_currentAudioPath == null) return;
    setState(() => _isProcessing = true);
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: widget.apiKey);
      final bytes = await File(_currentAudioPath!).readAsBytes();
      final content = [Content.multi([
        TextPart('''
          Gere JSON SOAP. IMPORTANTE: Extraia 'paciente': {'idade': int, 'sexo': 'Masculino'/'Feminino'}.
          Critica TÉCNICA apenas.
          { "soap": {"s":"", "o":"", "a":"", "p":""}, "criticas": {"s":"", "o":"", "a":"", "p":""}, "medicamentos": [], "paciente": {} }
        '''),
        DataPart('audio/mp4', bytes)
      ])];
      var response = await model.generateContent(content);
      final clean = response.text!.replaceAll('```json','').replaceAll('```','').trim();
      final data = json.decode(clean);
      if (data.containsKey('paciente')) {
        widget.onMetaDataFound(data['paciente']['idade'], data['paciente']['sexo']);
      }
      
      data['audit'] = _auditMedicines(List<String>.from(data['medicamentos']??[]));
      setState(() { _analysisResult = data; _isProcessing = false; });
    } catch (e) {
      setState(() { _isProcessing = false; _statusText = "Erro AI (Salvo Offline)"; });
    }
  }

  Map<String, dynamic> _auditMedicines(List<String> meds) {
    bool chk(List<String> db, String q) {
      final query = removeDiacritics(q.toLowerCase());
      return db.any((e) => removeDiacritics(e.toLowerCase()).contains(query));
    }
    return {"items": meds.map((m) => {"term": m, "remume": chk(_dbRemumeNames,m), "rename": chk(_dbRenameNames,m), "alto": chk(_dbAltoCustoNames,m)}).toList()};
  }

 @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Consultório")),
      body: Column(children: [
        Expanded(child: _analysisResult == null ? 
           Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.mic, size: 64, color: widget.hasKey ? Colors.blue[100] : Colors.grey[300]),
              const SizedBox(height: 10),
              Text(widget.hasKey ? _statusText : "Toque em Configurar par iniciar", style: const TextStyle(color: Colors.grey))
           ])) 
           : _buildResultList()),
        const SizedBox(height: 10),
        // ACTIONS
        Padding(padding: const EdgeInsets.all(16), child: 
          widget.hasKey 
          ? Row(children: [
              IconButton.outlined(onPressed: _isRecording ? null : () {}, icon: const Icon(Icons.upload)), // Upload Logic omitted
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                onPressed: _toggleRecording, 
                icon: Icon(_isRecording?Icons.stop:Icons.mic), 
                label: Text(_isRecording?"PARAR":"GRAVAR"),
                style: ElevatedButton.styleFrom(backgroundColor: _isRecording?Colors.red:Colors.blue[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15))
              )),
              const SizedBox(width: 10),
              IconButton.filled(onPressed: _analyze, icon: const Icon(Icons.send))
            ])
          : SizedBox(width: double.infinity, child: ElevatedButton(onPressed: widget.onRequestKey, child: const Text("CONFIGURAR GOOGLE API KEY")))
        )
      ]),
    );
  }

  Widget _buildResultList() {
    final soap = _analysisResult!['soap'];
    return ListView(padding: const EdgeInsets.all(16), children: [ 
       _card("S", "Subjetivo", soap['s'], Colors.blue),
       _card("O", "Objetivo", soap['o'], Colors.teal),
       _card("A", "Avaliação", soap['a'], Colors.orange),
       _card("P", "Plano", soap['p'], Colors.purple),
    ]);
  }

  Widget _card(String l, String t, String c, Color col) => Card(child: ListTile(leading: CircleAvatar(backgroundColor: col.withOpacity(0.1), child: Text(l, style: TextStyle(color: col))), title: Text(t, style: TextStyle(color: col, fontWeight: FontWeight.bold)), subtitle: Text(c)));
}

// ---------------- LIVE TAB ----------------
class LiveTab extends StatelessWidget {
  final String apiKey;
  final bool hasKey;
  const LiveTab({super.key, required this.apiKey, required this.hasKey});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ao Vivo")), 
      body: Center(child: hasKey 
        ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.multitrack_audio, size: 80, color: Colors.blue), SizedBox(height: 20), Text("Streaming em Breve")])
        : const Text("Requer API Key")
      )
    );
  }
}

// ---------------- SPECIALTIES ----------------
class SpecialtiesTab extends StatelessWidget {
  final String apiKey;
  final bool hasKey;
  const SpecialtiesTab({super.key, required this.apiKey, required this.hasKey});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Especialidades")),
      body: hasKey ? GridView.count(crossAxisCount: 2, padding: const EdgeInsets.all(16), crossAxisSpacing: 10, mainAxisSpacing: 10, children: [
        _tile(Icons.child_care, "Pediatria", Colors.orange),
        _tile(Icons.pregnant_woman, "Pré-Natal", Colors.pink),
        _tile(Icons.spa, "Dermatologia", Colors.brown),
        _tile(Icons.psychology, "Saúde Mental", Colors.purple),
      ]) : const Center(child: Text("Requer API Key")),
    );
  }
  Widget _tile(IconData i, String t, Color c) => Card(color: c.withOpacity(0.1), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 40, color: c), Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold))]));
}

// ---------------- SCREENING (Auto) ----------------
class ScreeningTab extends StatefulWidget {
  final String apiKey;
  final bool hasKey;
  final int? initialAge;
  final String? initialSex;
  final VoidCallback onRequestKey;

  const ScreeningTab({super.key, required this.apiKey, required this.hasKey, this.initialAge, this.initialSex, required this.onRequestKey});
  @override
  State<ScreeningTab> createState() => _ScreeningTabState();
}

class _ScreeningTabState extends State<ScreeningTab> {
  final _ageCtrl = TextEditingController();
  String _sex = "Feminino";
  String _result = "";
  bool _loading = false;

  @override 
  void initState() { super.initState(); _upd(); }
  @override
  void didUpdateWidget(ScreeningTab old) { super.didUpdateWidget(old); if(widget.initialAge!=old.initialAge || widget.initialSex!=old.initialSex) { _upd(); if(widget.initialAge!=null && widget.hasKey) _check(); } }

  void _upd() { if(widget.initialAge!=null) _ageCtrl.text=widget.initialAge.toString(); if(widget.initialSex!=null) _sex=widget.initialSex!; }

  Future<void> _check() async {
    if (!widget.hasKey) { widget.onRequestKey(); return; }
    setState(() => _loading = true);
    try {
       final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: widget.apiKey);
       final res = await model.generateContent([Content.text("Paciente Sexo $_sex, Idade ${_ageCtrl.text} anos. Listar rastreamentos (screening) indicados pelo Min. Saúde Brasil.")]);
       setState(() => _result = res.text ?? "-");
    } catch(e) { setState(() => _result = "Erro: $e"); } 
    finally { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rastreio (Auto)")),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
         Row(children: [Expanded(child: TextField(controller: _ageCtrl, decoration: const InputDecoration(labelText: "Idade", border: OutlineInputBorder()))), const SizedBox(width: 10), Expanded(child: DropdownButtonFormField(value: _sex, items: ["Feminino","Masculino"].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(), onChanged:(v)=>setState(()=>_sex=v!), decoration: const InputDecoration(labelText:"Sexo",border:OutlineInputBorder())))]),
         const SizedBox(height: 10),
         SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _loading?null:_check, child: Text(widget.hasKey ? "Verificar" : "Configurar Key"))),
         const Divider(),
         Expanded(child: SingleChildScrollView(child: Text(_result)))
      ])),
    );
  }
}

// ---------------- OFFLINE (Free) ----------------
class OfflineTab extends StatefulWidget {
  final String apiKey;
  const OfflineTab({super.key, required this.apiKey});
  @override
  State<OfflineTab> createState() => _OfflineTabState();
}

class _OfflineTabState extends State<OfflineTab> {
  List<FileSystemEntity> _files = [];
  Future<void> loadFiles() async {
     try {
       final d = await getApplicationDocumentsDirectory();
       final s = Directory('${d.path}/medubs_logs');
       if(await s.exists()) setState(() => _files = s.listSync()..sort((a,b)=>b.statSync().modified.compareTo(a.statSync().modified)));
     } catch (_) {}
  }
  @override void initState() { super.initState(); loadFiles(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Offline / Logs"), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: loadFiles)]),
      body: _files.isEmpty ? const Center(child: Text("Nenhum arquivo.")) : ListView.builder(itemCount: _files.length, itemBuilder: (c,i) => Card(child: ListTile(leading: const Icon(Icons.audio_file), title: Text(_files[i].path.split('/').last), subtitle: Text("${_files[i].statSync().size} bytes")))),
    );
  }
}
