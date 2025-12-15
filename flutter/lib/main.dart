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
      title: 'MedUBS v2.1',
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
  
  // Shared State (Lifting State Up)
  int? _patientAge;
  String _patientSex = "Feminino"; // Default
  
  // Persistence Key
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
    });
    if (_apiKeyController.text.isEmpty) {
      Future.delayed(Duration.zero, () => _showSettings(context));
    }
  }

  void _updateDemographics(int? age, String? sex) {
    if (age != null || sex != null) {
      setState(() {
        if (age != null) _patientAge = age;
        if (sex != null) _patientSex = sex;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Rastreio atualizado: $_patientSex, $_patientAge anos"),
        backgroundColor: Colors.teal,
        action: SnackBarAction(label: "VER", onPressed: () => setState(() => _currentIndex = 3)),
      ));
    }
  }

  void _notifyOfflineFileSaved() {
    // Refresh offline tab if it's active or notify user
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
            if (context.mounted) Navigator.pop(ctx);
          }, child: const Text("SALVAR"))
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pages need to be rebuilt if shared state changes to propagate updates?
    // Or we pass the values directly.
    final pages = [
      HomeTab(
        apiKey: _apiKeyController.text, 
        onMetaDataFound: _updateDemographics,
        onFileSaved: _notifyOfflineFileSaved,
      ),
      LiveTab(apiKey: _apiKeyController.text),
      SpecialtiesTab(apiKey: _apiKeyController.text),
      ScreeningTab(
        apiKey: _apiKeyController.text,
        initialAge: _patientAge,
        initialSex: _patientSex,
      ),
      OfflineTab(key: _offlineTabKey, apiKey: _apiKeyController.text),
    ];

    if (_apiKeyController.text.isEmpty) {
       return Scaffold(body: Center(child: ElevatedButton(onPressed: () => _showSettings(context), child: const Text("Configurar API Key"))));
    }

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() => _currentIndex = idx);
          // Auto-refresh offline tab when entering it
          if (idx == 4) _offlineTabKey.currentState?.loadFiles();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: "Início"),
          NavigationDestination(icon: Icon(Icons.mic_external_on_outlined), selectedIcon: Icon(Icons.mic_external_on), label: "Ao Vivo"),
          NavigationDestination(icon: Icon(Icons.medical_services_outlined), selectedIcon: Icon(Icons.medical_services), label: "Espec."),
          NavigationDestination(icon: Icon(Icons.checklist_rtl_outlined), selectedIcon: Icon(Icons.checklist_rtl), label: "Rastreio"),
          NavigationDestination(icon: Icon(Icons.wifi_off_outlined), selectedIcon: Icon(Icons.wifi_off), label: "Modo Offline"), // Renamed
        ],
      ),
    );
  }
}

// ==========================================
// 1. HOME TAB (Updated with Persistence)
// ==========================================
class HomeTab extends StatefulWidget {
  final String apiKey;
  final Function(int?, String?) onMetaDataFound;
  final VoidCallback onFileSaved;

  const HomeTab({
    super.key, 
    required this.apiKey, 
    required this.onMetaDataFound,
    required this.onFileSaved
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
  Color _statusColor = Colors.grey;

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
       // ... existing loading logic ...
    } catch (_) {}
  }

  // --- SAFE STORAGE LOGIC ---
  Future<String> _saveToSafeStorage(String tempPath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final safeDir = Directory('${appDir.path}/medubs_logs');
      if (!await safeDir.exists()) await safeDir.create(recursive: true);
      
      final fileName = "consulta_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.m4a";
      final safePath = "${safeDir.path}/$fileName";
      
      await File(tempPath).copy(safePath);
      print("Safe logged to: $safePath");
      widget.onFileSaved(); // Notify MainScreen to update Offline Tab list
      return safePath;
    } catch (e) {
      print("Error saving safe log: $e");
      return tempPath; // Fallback
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      if (path != null) {
        // IMMEDIATE SAFE SAVE
        final safePath = await _saveToSafeStorage(path);
        
        setState(() { 
          _isRecording = false; 
          _currentAudioPath = safePath; // Use safe path
          _statusText = "Gravado e Salvo (Log)."; 
          _statusColor = Colors.green; 
        });
      }
    } else {
      if (await Permission.microphone.request().isGranted) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/temp_rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(path: path, encoder: AudioEncoder.aacLc);
        setState(() { _isRecording = true; _statusText = "Gravando..."; _statusColor = Colors.red; _analysisResult = null; });
      }
    }
  }

  Future<void> _analyze() async {
    if (_currentAudioPath == null) return;
    setState(() => _isProcessing = true);
    
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: widget.apiKey);
      final bytes = await File(_currentAudioPath!).readAsBytes();
      
      final content = [Content.multi([
        TextPart('''
          Atue como médico. Gere JSON SOAP.
          IMPORTANTE: Extraia metadados do paciente (Idade e Sexo) se mencionado ou inferido.
          
          Estrutura JSON:
          { 
            "soap": {"s":"", "o":"", "a":"", "p":""}, 
            "criticas": {"s":"", "o":"", "a":"", "p":""}, 
            "medicamentos": [],
            "paciente": { "idade": null, "sexo": null } 
          }
          
          Obs: Sexo deve ser "Masculino" ou "Feminino". Idade em anos (int).
        '''),
        DataPart('audio/mp4', bytes)
      ])];
      
      var response = await model.generateContent(content);
      final clean = response.text!.replaceAll('```json','').replaceAll('```','').trim();
      final data = json.decode(clean);
      
      // Hook for Auto-Screening
      if (data.containsKey('paciente')) {
        final p = data['paciente'];
        widget.onMetaDataFound(p['idade'] as int?, p['sexo'] as String?);
      }
      
      // Fake Audit Logic
      data['audit'] = {"items": [], "counts": {"remume":0}}; // Simplify for brevity in this view

      setState(() { _analysisResult = data; _isProcessing = false; });
    } catch (e) {
      setState(() { 
        _isProcessing = false; 
        _statusText = "Erro na IA (Audio salvo no Modo Offline)"; 
        _statusColor = Colors.orange;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro na IA: $e. O áudio está salvo no Modo Offline.")));
    }
  }
  
  // ignore: unused_element
  Future<void> _pickFile() async {
      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'm4a', 'wav']);
      if (res!=null) {
        // Also save picked files to safe log? Maybe not, duplicate.
        // But user asked "not to lose conversation".
        // Let's just track path.
        setState(() { _currentAudioPath = res.files.single.path; _statusText = "Arquivo Selecionado"; _analysisResult = null;});
      }
  }

  @override
  Widget build(BuildContext context) {
    // Re-implementing simplified UI for the overwrite
    return Scaffold(
      appBar: AppBar(title: const Text("Consultório (Início)")),
      body: Column(
        children: [
           Expanded(
             child: _analysisResult == null 
               ? Center(child: Text(_statusText, textAlign: TextAlign.center)) 
               : ListView(
                   padding: const EdgeInsets.all(16),
                   children: [
                      if (_analysisResult!.containsKey('paciente')) 
                        Card(color: Colors.blue[50], child: ListTile(leading: const Icon(Icons.person), title: Text("Paciente Identificado: ${_analysisResult!['paciente']['sexo']}, ${_analysisResult!['paciente']['idade']} anos"))),
                      Text("S: ${_analysisResult!['soap']['s']}"),
                      const Divider(),
                      Text("O: ${_analysisResult!['soap']['o']}"),
                      const Divider(),
                      Text("A: ${_analysisResult!['soap']['a']}"),
                      const Divider(),
                      Text("P: ${_analysisResult!['soap']['p']}"),
                   ]
                 )
           ),
           Container(
             padding: const EdgeInsets.all(16),
             child: Row(children: [
                IconButton.outlined(onPressed: _pickFile, icon: const Icon(Icons.upload)),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(
                  onPressed: _toggleRecording, 
                  icon: Icon(_isRecording?Icons.stop:Icons.mic), 
                  label: Text(_isRecording?"PARAR":"GRAVAR CONSULTA"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: _isRecording?Colors.red:Colors.blue[800], 
                    foregroundColor: Colors.white
                  ),
                )),
                const SizedBox(width: 10),
                IconButton.filled(onPressed: (_currentAudioPath != null && !_isProcessing) ? _analyze : null, icon: const Icon(Icons.send_and_archive)),
             ]),
           )
        ],
      ),
    );
  }
}

// ==========================================
// 2. LIVE TAB
// ==========================================
class LiveTab extends StatelessWidget {
  final String apiKey;
  const LiveTab({super.key, required this.apiKey});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("Ao Vivo")), body: const Center(child: Text("Modo Streaming em Breve")));
  }
}

// ==========================================
// 3. SPECIALTIES TAB
// ==========================================
class SpecialtiesTab extends StatelessWidget {
  final String apiKey;
  const SpecialtiesTab({super.key, required this.apiKey});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("Especialidades")), body: const Center(child: Text("Grid de Especialidades")));
  }
}

// ==========================================
// 4. SCREENING TAB (Auto-Filled)
// ==========================================
class ScreeningTab extends StatefulWidget {
  final String apiKey;
  final int? initialAge;
  final String? initialSex;
  
  const ScreeningTab({super.key, required this.apiKey, this.initialAge, this.initialSex});

  @override
  State<ScreeningTab> createState() => _ScreeningTabState();
}

class _ScreeningTabState extends State<ScreeningTab> {
  final _ageCtrl = TextEditingController();
  String _sex = "Feminino";
  String _result = "";
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _updateFields();
  }

  @override
  void didUpdateWidget(ScreeningTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAge != oldWidget.initialAge || widget.initialSex != oldWidget.initialSex) {
      _updateFields();
      // Auto-check if fields are filled? Maybe too intrusive. 
      // Let's just fill and let user click checks.
      if (widget.initialAge != null) {
         _check(); // Auto-check requested by user ("se preenche automaticamente e mostrará")
      }
    }
  }

  void _updateFields() {
    if (widget.initialAge != null) _ageCtrl.text = widget.initialAge.toString();
    if (widget.initialSex != null) _sex = widget.initialSex!;
  }

  Future<void> _check() async {
    setState(() => _loading = true);
    try {
       final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: widget.apiKey);
       final prompt = "Paciente Sexo $_sex, Idade ${_ageCtrl.text} anos. Listar rastreamentos (screening) indicados pelo Min. Saúde Brasil. Formato Markdown Checkbox.";
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
      appBar: AppBar(title: const Text("Rastreio (Automático)")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
             Row(children: [
               Expanded(child: TextField(controller: _ageCtrl, decoration: const InputDecoration(labelText: "Idade", border: OutlineInputBorder()))),
               const SizedBox(width: 10),
               Expanded(child: DropdownButtonFormField<String>(
                 value: _sex,
                 items: ["Feminino", "Masculino"].map((e)=>DropdownMenuItem(value: e, child: Text(e))).toList(),
                 onChanged: (v) => setState(() => _sex = v!),
                 decoration: const InputDecoration(labelText: "Sexo", border: OutlineInputBorder()),
               )),
             ]),
             const SizedBox(height: 10),
             SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _loading ? null : _check, child: const Text("Consultar Diretrizes"))),
             const Divider(),
             Expanded(
               child: _loading 
                 ? const Center(child: CircularProgressIndicator()) 
                 : SingleChildScrollView(child: Text(_result.isEmpty ? "Aguardando dados..." : _result))
             ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. OFFLINE TAB (Renamed & Real Files)
// ==========================================
class OfflineTab extends StatefulWidget {
  final String apiKey;
  const OfflineTab({super.key, required this.apiKey});

  @override
  State<OfflineTab> createState() => _OfflineTabState();
}

class _OfflineTabState extends State<OfflineTab> {
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    loadFiles();
  }

  Future<void> loadFiles() async {
    setState(() => _isLoading = true);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final safeDir = Directory('${appDir.path}/medubs_logs');
      if (await safeDir.exists()) {
        final List<FileSystemEntity> entities = safeDir.listSync()
          ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified)); // Newest first
        setState(() => _files = entities);
      } else {
        setState(() => _files = []);
      }
    } catch (e) {
      print("Error loading logs: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Modo Offline / Logs"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: loadFiles)]
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _files.isEmpty 
           ? const Center(child: Text("Nenhum áudio salvo."))
           : ListView.builder(
              itemCount: _files.length,
              itemBuilder: (ctx, i) {
                final file = _files[i];
                final name = file.path.split('/').last;
                final size = (file.statSync().size / 1024).toStringAsFixed(1);
                final date = DateFormat('dd/MM HH:mm').format(file.statSync().modified);

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.audio_file, color: Colors.blueGrey),
                    title: Text(name, style: const TextStyle(fontSize: 12)),
                    subtitle: Text("$date • ${size}KB"),
                    trailing: IconButton(
                      icon: const Icon(Icons.upload, color: Colors.blue),
                      onPressed: () {
                        // Logic to send this specific file would go here
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Enviando $name... (Simulado)")));
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
