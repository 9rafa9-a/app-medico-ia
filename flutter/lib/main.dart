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
      title: 'MedUBS v2',
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
  final _apiKeyController = TextEditingController(); // Shared Key

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
    });
    if (_apiKeyController.text.isEmpty) {
      Future.delayed(Duration.zero, () => _showSettings(context));
    }
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
            if (context.mounted) Navigator.pop(ctx);
          }, child: const Text("SALVAR"))
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_apiKeyController.text.isEmpty) {
       return Scaffold(
         body: Center(
           child: ElevatedButton(onPressed: () => _showSettings(context), child: const Text("Configurar API Key"))
         )
       );
    }

    final pages = [
      HomeTab(apiKey: _apiKeyController.text),
      LiveTab(apiKey: _apiKeyController.text),
      SpecialtiesTab(apiKey: _apiKeyController.text),
      ScreeningTab(apiKey: _apiKeyController.text),
      OfflineTab(apiKey: _apiKeyController.text),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: "Início"),
          NavigationDestination(icon: Icon(Icons.mic_external_on_outlined), selectedIcon: Icon(Icons.mic_external_on), label: "Ao Vivo"),
          NavigationDestination(icon: Icon(Icons.medical_services_outlined), selectedIcon: Icon(Icons.medical_services), label: "Espec."),
          NavigationDestination(icon: Icon(Icons.checklist_rtl_outlined), selectedIcon: Icon(Icons.checklist_rtl), label: "Rastreio"),
          NavigationDestination(icon: Icon(Icons.cloud_off_outlined), selectedIcon: Icon(Icons.cloud_off), label: "Ronda"),
        ],
      ),
    );
  }
}

// ==========================================
// 1. HOME TAB (Original Logic)
// ==========================================
class HomeTab extends StatefulWidget {
  final String apiKey;
  const HomeTab({super.key, required this.apiKey});
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
  Color _statusColor = Colors.grey;

  // Caches for DB Logic
  List<String> _dbRemumeNames = [];
  List<String> _dbRenameNames = [];
  List<String> _dbAltoCustoNames = [];

  @override
  void initState() {
    super.initState();
    _loadDatabases();
  }

  Future<void> _loadDatabases() async {
    // Same loading logic
    try {
      List<String> extractNames(dynamic json, String source) {
        List<String> names = [];
        if (json is List) {
          for (var item in json) {
            if (item is Map && (item.containsKey('nome') || item.containsKey('nome_completo'))) {
              names.add((item['nome'] ?? item['nome_completo']).toString());
            } else if (item is Map && item.containsKey('itens') && item['itens'] is List) {
               for (var subItem in item['itens']) {
                 if (subItem is Map && subItem.containsKey('nome')) names.add(subItem['nome'].toString());
               }
            }
          }
        }
        return names;
      }
      final remume = json.decode(await rootBundle.loadString('assets/db_remume.json'));
      final rename = json.decode(await rootBundle.loadString('assets/db_rename.json'));
      final alto = json.decode(await rootBundle.loadString('assets/db_alto_custo.json'));
      if(mounted) setState(() {
        _dbRemumeNames = extractNames(remume, "REMUME");
        _dbRenameNames = extractNames(rename, "RENAME");
        _dbAltoCustoNames = extractNames(alto, "ALTO");
      });
    } catch (_) {}
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() { _isRecording = false; _currentAudioPath = path; _statusText = "Gravado"; _statusColor = Colors.green; });
    } else {
      if (await Permission.microphone.request().isGranted) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/home_rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(path: path, encoder: AudioEncoder.aacLc);
        setState(() { _isRecording = true; _statusText = "Gravando Home..."; _statusColor = Colors.red; _analysisResult = null; });
      }
    }
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'm4a', 'wav']);
    if (res!=null) setState(() { _currentAudioPath = res.files.single.path; _statusText = "Arquivo Selecionado"; _analysisResult = null;});
  }

  Future<void> _analyze() async {
    if (_currentAudioPath == null) return;
    setState(() => _isProcessing = true);
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: widget.apiKey);
      final bytes = await File(_currentAudioPath!).readAsBytes();
      
      final content = [Content.multi([
        TextPart('''
          Gere um JSON SOAP. Críticas TÉCNICAS.
          { "soap": {"s":"", "o":"", "a":"", "p":""}, "criticas": {"s":"", "o":"", "a":"", "p":""}, "medicamentos": [] }
        '''),
        DataPart('audio/mp4', bytes)
      ])];
      
      var response = await model.generateContent(content);
      // Clean and Parse
      final clean = response.text!.replaceAll('```json','').replaceAll('```','').trim();
      final data = json.decode(clean);
      data['audit'] = _auditMedicines(List<String>.from(data['medicamentos']??[]));
      
      setState(() { _analysisResult = data; _isProcessing = false; });
    } catch (e) {
      setState(() { _isProcessing = false; _statusText = "Erro: $e"; });
    }
  }

  Map<String, dynamic> _auditMedicines(List<String> meds) {
    // Audit logic
    return {"items": meds.map((m) => {"term": m, "remume": _dbRemumeNames.contains(m), "rename": _dbRenameNames.contains(m), "alto": _dbAltoCustoNames.contains(m)}).toList()};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Consultório")),
      body: Column(
        children: [
          Expanded(child: _analysisResult == null ? Center(child: Text(_statusText)) : _buildResultList()),
          Container(
             padding: const EdgeInsets.all(16),
             child: Row(children: [
                IconButton(onPressed: _pickFile, icon: const Icon(Icons.upload)),
                Expanded(child: ElevatedButton.icon(
                  onPressed: _toggleRecording, 
                  icon: Icon(_isRecording?Icons.stop:Icons.mic), 
                  label: Text(_isRecording?"PARAR":"GRAVAR"),
                  style: ElevatedButton.styleFrom(backgroundColor: _isRecording?Colors.red:Colors.blue, foregroundColor: Colors.white),
                )),
                IconButton(onPressed: _analyze, icon: const Icon(Icons.send)),
             ]),
          )
        ],
      ),
    );
  }

  Widget _buildResultList() {
    final soap = _analysisResult!['soap'];
    return ListView(children: [ 
       ListTile(title: Text("S: ${soap['s']}")),
       ListTile(title: Text("O: ${soap['o']}")),
       ListTile(title: Text("A: ${soap['a']}")),
       ListTile(title: Text("P: ${soap['p']}")),
    ]);
  }
}

// ==========================================
// 2. LIVE TAB (Feature 6)
// ==========================================
class LiveTab extends StatelessWidget {
  final String apiKey;
  const LiveTab({super.key, required this.apiKey});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Modo Ao Vivo 🔴")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.multitrack_audio, size: 80, color: Colors.redAccent),
            const SizedBox(height: 20),
            const Text("Transcrição em Tempo Real", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                "Este modo usará o Gemini 2.0 Streaming para transcrever e analisar enquanto você fala. \n(Simulação Visual Ativa)",
                textAlign: TextAlign.center,
              ),
            ),
            ElevatedButton(onPressed: (){}, child: const Text("Iniciar Sessão Live"))
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. SPECIALTIES TAB (Feature 4)
// ==========================================
class SpecialtiesTab extends StatelessWidget {
  final String apiKey;
  const SpecialtiesTab({super.key, required this.apiKey});

  @override
  Widget build(BuildContext context) {
    final specs = [
      {"name": "Pediatria", "icon": Icons.child_care, "color": Colors.orange},
      {"name": "Pré-Natal", "icon": Icons.pregnant_woman, "color": Colors.pink},
      {"name": "Saúde Mental", "icon": Icons.psychology, "color": Colors.purple},
      {"name": "Dermatologia", "icon": Icons.spa, "color": Colors.brown},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Especialidades")),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16),
        itemCount: specs.length,
        itemBuilder: (ctx, i) {
           final s = specs[i];
           return Card(
             color: (s['color'] as Color).withOpacity(0.1),
             child: InkWell(
               onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Modo ${s['name']} Ativado!"))),
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Icon(s['icon'] as IconData, size: 48, color: s['color'] as Color),
                   const SizedBox(height: 10),
                   Text(s['name'] as String, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: s['color'] as Color))
                 ],
               ),
             ),
           );
        },
      ),
    );
  }
}

// ==========================================
// 4. SCREENING TAB (New Feature)
// ==========================================
class ScreeningTab extends StatefulWidget {
  final String apiKey;
  const ScreeningTab({super.key, required this.apiKey});

  @override
  State<ScreeningTab> createState() => _ScreeningTabState();
}

class _ScreeningTabState extends State<ScreeningTab> {
  final _ageCtrl = TextEditingController();
  String _sex = "Feminino";
  String _result = "";
  bool _loading = false;

  Future<void> _check() async {
    setState(() => _loading = true);
    try {
       final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: widget.apiKey);
       final prompt = "Baseado nas diretrizes do Ministério da Saúde do Brasil, quais rastreamentos (screening) são indicados para um paciente sexo $_sex, idade ${_ageCtrl.text} anos? Seja sucinto em tópicos.";
       final res = await model.generateContent([Content.text(prompt)]);
       setState(() => _result = res.text ?? "Sem dados.");
    } catch(e) {
       setState(() => _result = "Erro: $e");
    } finally {
       setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rastreio Clínico")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
             TextField(controller: _ageCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Idade", border: OutlineInputBorder())),
             const SizedBox(height: 10),
             DropdownButtonFormField<String>(
               value: _sex,
               items: ["Feminino", "Masculino"].map((e)=>DropdownMenuItem(value: e, child: Text(e))).toList(),
               onChanged: (v) => setState(() => _sex = v!),
               decoration: const InputDecoration(labelText: "Sexo", border: OutlineInputBorder()),
             ),
             const SizedBox(height: 20),
             ElevatedButton(onPressed: _loading ? null : _check, child: const Text("Verificar Elegibilidade")),
             const SizedBox(height: 20),
             Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(child: Text(_result))),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. OFFLINE TAB (Feature 5)
// ==========================================
class OfflineTab extends StatefulWidget {
  final String apiKey;
  const OfflineTab({super.key, required this.apiKey});

  @override
  State<OfflineTab> createState() => _OfflineTabState();
}

class _OfflineTabState extends State<OfflineTab> {
  // Mock List
  final List<String> _queue = [
    "consulta_joao_silva_rural.m4a",
    "visita_maria_santos_sitio.m4a",
    "ronda_antonio_fazenda.m4a"
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Modo Ronda (Offline)")),
      body: ListView.builder(
        itemCount: _queue.length,
        itemBuilder: (ctx, i) {
          return ListTile(
            leading: const Icon(Icons.audio_file, color: Colors.grey),
            title: Text(_queue[i]),
            subtitle: const Text("Aguardando Conexão..."),
            trailing: IconButton(icon: const Icon(Icons.upload, color: Colors.blue), onPressed: (){
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Buscando conexão para envio...")));
            }),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gravar para Fila Offline..."))),
      ),
    );
  }
}
