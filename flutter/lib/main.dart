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
import 'package:open_file/open_file.dart';
import 'package:http/http.dart' as http; // Novo Import

import 'database/database_helper.dart'; // Novo Import
import 'services/api_service.dart';     // Novo Import
import 'widgets/mission_card.dart';     // Novo Import
import 'screens/stock_screen.dart';     // Novo Import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializa o banco de dados antes de rodar o app
  await DatabaseHelper().database;
  runApp(const MedUBSApp());
}

class MedUBSApp extends StatelessWidget {
  const MedUBSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedUBS v3.0 Híbrido',
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
  
  // Multi-Key System
  final List<TextEditingController> _keyControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController()
  ];
  int _activeKeyIndex = 0;
  
  final _serverUrlController = TextEditingController(text: "https://medubs-backend.onrender.com");
  String _selectedModel = 'gemini-2.5-flash';
  int? _patientAge;
  String _patientSex = "Feminino";
  List<String> _patientKeywords = [];
  String? _activeSpecialty;
  final GlobalKey<_OfflineTabState> _offlineTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _keyControllers[0].text = prefs.getString('gemini_key_0') ?? '';
      _keyControllers[1].text = prefs.getString('gemini_key_1') ?? '';
      _keyControllers[2].text = prefs.getString('gemini_key_2') ?? '';
      _activeKeyIndex = prefs.getInt('active_key_index') ?? 0;
      
      _serverUrlController.text = prefs.getString('api_base_url') ?? 'https://medubs-backend.onrender.com';
      _selectedModel = prefs.getString('gemini_model') ?? 'gemini-2.5-flash';
    });
  }

  String get _activeKey => _keyControllers[_activeKeyIndex].text;

  void _updateDemographics(int? age, String? sex, List<String>? keywords) {
    if (age != null || sex != null || keywords != null) {
      if (mounted) {
        setState(() {
          if (age != null) _patientAge = age;
          if (sex != null) _patientSex = sex;
          if (keywords != null) _patientKeywords = keywords;
        });
        
        String kwMsg = (keywords != null && keywords.isNotEmpty) ? "+ Contexto Clínico" : "";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Rastreio: $_patientSex, $_patientAge anos $kwMsg"),
          backgroundColor: Colors.teal,
          action: SnackBarAction(label: "VER", textColor: Colors.white, onPressed: () => setState(() => _currentIndex = 2)),
        ));
      }
    }
  }

  void _notifyOfflineFileSaved() {
    _offlineTabKey.currentState?.loadFiles(); 
  }

  void _activateSpecialty(String name) {
    setState(() {
      _activeSpecialty = name;
      _currentIndex = 0; // Switch to Home
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Modo $name Ativado! O prompt será ajustado."),
      backgroundColor: Colors.indigo,
    ));
  }

  void _clearSpecialty() {
    setState(() => _activeSpecialty = null);
  }

  // --- FUNÇÕES DE UPLOAD (Novas) ---
  
  Future<void> _uploadEstoque() async {
    // 1. Pede nome da lista
    String nomeLista = "";
    await showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Nome da Lista de Medicamentos"),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: "Ex: REMUME Foz 2025"),
          onChanged: (v) => nomeLista = v,
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      )
    );
    
    if (nomeLista.isEmpty) return;
    await _uploadMedicamento(nomeLista, context);
  }

  Future<void> _uploadMedicamento(String nomeLista, BuildContext context) async {
    if (nomeLista.isEmpty) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      if (!_validateKey(context)) return;

      // START PROCESS
      await _executeUpload(File(result.files.single.path!), nomeLista, context, false);
    }
  }

  Future<void> _executeUpload(File file, String nomeLista, BuildContext context, bool forceAi) async {
      // UX: Granular Log System
      final ValueNotifier<List<String>> logs = ValueNotifier(["📄 Arquivo selecionado."]);
      void addLog(String text) => logs.value = [...logs.value, text];

      showDialog(
        context: context, 
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(forceAi ? "Processando com IA" : "Lendo Documento"),
          content: SizedBox(
            width: double.maxFinite,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: logs,
              builder: (context, value, child) => ListView.builder(
                shrinkWrap: true,
                itemCount: value.length + 1, 
                itemBuilder: (context, index) {
                  if (index == value.length) {
                    return const Padding(padding: EdgeInsets.all(8.0), child: Center(child: LinearProgressIndicator()));
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(child: Text(value[index], style: const TextStyle(fontSize: 13))),
                    ]
                  );
                },
              ),
            ),
          ),
        )
      );

      try {
        addLog("Tamanho: ${(file.lengthSync() / 1024).toStringAsFixed(1)} KB");
        
        // Fase 1: Envio
        if (forceAi) {
           addLog("🤖 Modo AI Forçado: Enviando para Gemini...");
        } else {
           addLog("⚡ Modo Rápido: Tentando leitura estruturada...");
        }
        
        // Call Service
        Map<String, dynamic> response = await ApiService.uploadMedicamento(
            file, nomeLista, _activeKey, _selectedModel, forceAi: forceAi
        );
        
        Navigator.pop(context); // Close Spinner Dialog

        String status = response['status'] ?? 'error';
        List<dynamic> meds = response['items'] ?? [];
        Map<String, dynamic>? debug = response['debug'];

        if (status == 'heuristic_failed' && !forceAi) {
           // FALLBACK DIALOG
           showDialog(
             context: context,
             builder: (ctx) => AlertDialog(
               title: const Text("Leitura Automática Falhou"),
               content: const Text("O sistema não conseguiu ler o PDF diretamente. Provavelmente é uma imagem escaneada.\n\nDeseja usar a Inteligência Artificial para ler? (Consome cota da API)."),
               actions: [
                 TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
                 FilledButton(onPressed: () {
                   Navigator.pop(ctx);
                   _executeUpload(file, nomeLista, context, true); // RETRY WITH FORCE AI
                 }, child: const Text("Sim, usar IA"))
               ],
             )
           );
           return;
        }

        if (meds.isEmpty) {
           // Show Report
           showDialog(context: context, builder: (ctx) => AlertDialog(
             title: const Text("Nenhum medicamento encontrado"),
             content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Tente novamente ou verifique o PDF.", style: TextStyle(color: Colors.red)),
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: Text("Status: $status\nDebug: $debug", style: const TextStyle(fontFamily: 'monospace', fontSize: 10))
                )
             ])),
             actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
           ));
           return;
        }
        
        // Success
        final batch = meds.map((e) => Map<String, dynamic>.from(e)).toList();
        await DatabaseHelper().inserirLoteMedicamentos(batch);
        
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sucesso! ${meds.length} itens importados via ${forceAi?'IA':'Leitura Rápida'}."), backgroundColor: Colors.green));
        
      } catch (e) {
        Navigator.pop(context); // Close
        showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Erro Fatal"), content: Text(e.toString())));
      }
  }

  bool _validateKey(BuildContext context) {
    if (_activeKey.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Chave Necessária"),
          content: const Text("Para processar documentos com Inteligência Artificial, você precisa configurar sua API Key do Gemini primeiro."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text("Entendi")
            )
          ],
        )
      );
      return false;
    }
    return true;
  }

  Future<void> _uploadDiretriz() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.single.path != null) {
      if (!_validateKey(context)) return;

      // UX: Granular Logs
      final ValueNotifier<List<String>> logs = ValueNotifier(["📄 Protocolo selecionado."]);
      void addLog(String text) => logs.value = [...logs.value, text];

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Enviando Diretriz"),
           content: SizedBox(
            width: double.maxFinite,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: logs,
              builder: (context, value, child) => ListView.builder(
                shrinkWrap: true,
                itemCount: value.length + 1,
                itemBuilder: (context, index) {
                  if (index == value.length) return const Padding(padding: EdgeInsets.all(8.0), child: Center(child: LinearProgressIndicator()));
                  return Row(children: [const Icon(Icons.check, size: 16, color: Colors.blue), const SizedBox(width: 8), Expanded(child: Text(value[index]))]);
                },
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR"))]
        )
      );

      try {
        File file = File(result.files.single.path!);
        addLog("Tamanho: ${(file.lengthSync() / 1024).toStringAsFixed(1)} KB");
        addLog("🛫 Enviando para Base de Conhecimento...");
        
        bool ok = await ApiService.uploadDiretriz(file, _activeKey);
        
        if (ok) {
           addLog("✅ Sucesso! Protocolo indexado.");
           await Future.delayed(const Duration(seconds: 1)); // UX pause
           Navigator.pop(context);
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Diretriz salva na Base de Conhecimento!"), backgroundColor: Colors.green));
        } else {
           Navigator.pop(context);
           showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Falha"), content: const Text("O servidor retornou erro. Verifique a chave e a conexão.")));
        }
      } catch (e) {
        Navigator.pop(context);
        showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Erro"), content: Text(e.toString())));
      }
    }
  }

  void _showSettings(BuildContext context) {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Configurações Globais"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Container( 
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: Colors.green[100], borderRadius: BorderRadius.circular(4)),
  void _showSettings(BuildContext context) {
    // Local state for radio selection inside dialog
    int dialogKeyIndex = _activeKeyIndex; 

    showDialog(
      context: context, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("Configurações Globais"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Container( 
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: Colors.green[100], borderRadius: BorderRadius.circular(4)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min, 
                    children: [
                      Icon(Icons.circle, color: Colors.green, size: 10), 
                      SizedBox(width: 5), 
                      Text("Servidor: Online", style: TextStyle(fontSize: 12, color: Colors.green))
                    ]
                  ),
                ),
                TextField(
                   controller: _serverUrlController,
                   decoration: const InputDecoration(
                     labelText: "URL do Servidor (Backend)", 
                     border: OutlineInputBorder(), 
                     prefixIcon: Icon(Icons.cloud_queue),
                     hintText: "http://192.168.X.X:8000"
                   ),
                   keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 15),
                const Text("Chaves de Acesso (Gemini API)", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                
                // Key 1
                _buildKeyField(0, "Chave Principal", dialogKeyIndex, (v) => setStateDialog(() => dialogKeyIndex = v)),
                // Key 2
                _buildKeyField(1, "Chave Reserva 1", dialogKeyIndex, (v) => setStateDialog(() => dialogKeyIndex = v)),
                // Key 3
                _buildKeyField(2, "Chave Reserva 2", dialogKeyIndex, (v) => setStateDialog(() => dialogKeyIndex = v)),
                
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: _selectedModel,
                  decoration: const InputDecoration(labelText: "Modelo AI", border: OutlineInputBorder(), prefixIcon: Icon(Icons.psychology)),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'gemini-2.5-flash', child: Text('Gemini 2.5 Flash (Padrão/Rápido)')),
                    DropdownMenuItem(value: 'gemini-2.0-flash', child: Text('Gemini 2.0 Flash (Novo)')),
                    DropdownMenuItem(value: 'gemini-2.0-flash-lite', child: Text('Gemini 2.0 Flash-Lite (Super Rápido)')),
                    DropdownMenuItem(value: 'gemini-3-pro-preview', child: Text('Gemini 3.0 Pro (Experimental)')),
                    DropdownMenuItem(value: 'gemini-2.5-pro', child: Text('Gemini 2.5 Pro (Alta Precisão)')),
                  ], 
                  onChanged: (v) { if(v!=null) _selectedModel = v; }
                ),
                const SizedBox(height: 20),
                const Divider(),
                const Text("Administração de Dados", style: TextStyle(fontWeight: FontWeight.bold)),
                ListTile(
                  leading: const Icon(Icons.medication, color: Colors.blue),
                  title: const Text("Atualizar Estoque (PDF)"),
                  subtitle: const Text("Importar REMUME/RENAME"),
                  onTap: () { Navigator.pop(ctx); _uploadEstoque(); },
                ),
                ListTile(
                  leading: const Icon(Icons.book, color: Colors.orange),
                  title: const Text("Adicionar Diretriz (PDF)"),
                  subtitle: const Text("Protocolos para RAG"),
                  onTap: () { Navigator.pop(ctx); _uploadDiretriz(); },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              
              // Salva todas as chaves
              await prefs.setString('gemini_key_0', _keyControllers[0].text);
              await prefs.setString('gemini_key_1', _keyControllers[1].text);
              await prefs.setString('gemini_key_2', _keyControllers[2].text);
              await prefs.setInt('active_key_index', dialogKeyIndex);
              
              await prefs.setString('api_base_url', _serverUrlController.text);
              await prefs.setString('gemini_model', _selectedModel);
              
              ApiService.baseUrl = _serverUrlController.text;

              setState(() { _activeKeyIndex = dialogKeyIndex; }); 
              if (context.mounted) Navigator.pop(ctx);
            }, child: const Text("SALVAR"))
          ],
        )
      )
    );
  }

  Widget _buildKeyField(int index, String label, int groupValue, Function(int) onChanged) {
    bool isSelected = groupValue == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: isSelected ? Colors.green : Colors.grey[300]!),
        color: isSelected ? Colors.green[50] : null,
        borderRadius: BorderRadius.circular(8)
      ),
      child: Row(
        children: [
          Radio<int>(
            value: index, 
            groupValue: groupValue, 
            onChanged: (v) => onChanged(v!),
            activeColor: Colors.green,
          ),
          Expanded(
            child: TextField(
              controller: _keyControllers[index],
              decoration: InputDecoration(
                labelText: label, 
                border: InputBorder.none,
                hintText: "Coloque a API Key aqui",
                isDense: true
              ),
              obscureText: true,
              style: TextStyle(color: isSelected ? Colors.green[900] : Colors.black),
            )
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool hasKey = _activeKey.isNotEmpty;

    final List<Widget> pages = [
      HomeTab(
        apiKey: _activeKey, 
        hasKey: hasKey,
        selectedModel: _selectedModel,
        activeSpecialty: _activeSpecialty,
        onClearSpecialty: _clearSpecialty,
        onMetaDataFound: _updateDemographics,
        onFileSaved: _notifyOfflineFileSaved,
        onRequestKey: () => _showSettings(context),
      ),
      // LiveTab removida temporariamente
      SpecialtiesTab(
        apiKey: _activeKey, 
        hasKey: hasKey,
        onSpecialtySelected: _activateSpecialty,
      ),
      ScreeningTab(
        apiKey: _activeKey,
        hasKey: hasKey,
        selectedModel: _selectedModel,
        initialAge: _patientAge,
        initialSex: _patientSex,
        onRequestKey: () => _showSettings(context),
      ),
      // OfflineTab(key: _offlineTabKey, apiKey: _activeKey),
      const StockScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() => _currentIndex = idx);
          // if (idx == 3) _offlineTabKey.currentState?.loadFiles(); 
        },
        indicatorColor: hasKey ? Colors.blue[100] : Colors.grey[300],
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: "Consulta"),
          NavigationDestination(icon: Icon(Icons.medical_services_outlined), selectedIcon: Icon(Icons.medical_services), label: "Espec."),
          NavigationDestination(icon: Icon(Icons.checklist_rtl_outlined), selectedIcon: Icon(Icons.checklist_rtl), label: "Rastreio"),
          // NavigationDestination(icon: Icon(Icons.wifi_off_outlined), selectedIcon: Icon(Icons.wifi_off), label: "Offline"),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: "Estoque"),
        ],
      ),
    );
  }
}

// ---------------- HOME TAB ----------------
class HomeTab extends StatefulWidget {
  final String apiKey;
  final bool hasKey;
  final String selectedModel;
  final String? activeSpecialty;
  final VoidCallback onClearSpecialty;
  final Function(int?, String?, List<String>?) onMetaDataFound;
  final VoidCallback onFileSaved;
  final VoidCallback onRequestKey;

  const HomeTab({
    super.key, 
    required this.apiKey, 
    required this.hasKey,
    required this.selectedModel,
    this.activeSpecialty,
    required this.onClearSpecialty,
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
  String _processingStep = ""; 
  String? _currentAudioPath;
  Map<String, dynamic>? _analysisResult;
  String _statusText = "Pronto";

  // Removed Local Lists (_dbRemumeNames, etc)

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
          _statusText = "Salvo. Toque em Enviar ->"; 
        });
      }
    } else {
      if (await Permission.microphone.request().isGranted) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(path: path, encoder: AudioEncoder.aacLc);
        setState(() { _isRecording = true; _statusText = "Gravando..."; _analysisResult = null; });
      }
    }
  }
  
  // Nova lógica de Auditoria assíncrona com SQLite
  Future<Map<String, dynamic>> _auditMedicines(List<String> meds) async {
    List<Map<String, dynamic>> items = [];
    
    for (var m in meds) {
      var result = await DatabaseHelper().checarMedicamento(m);
      items.add({
        "term": m,
        "remume": result['remume'] == true,
        "rename": result['rename'] == true,
        "alto": result['alto_custo'] == true,
        "listas": result['listas_detalhe']
      });
    }
    
    return {"items": items};
  }

  // Robust Helpers
  List<String> _safeStringList(dynamic list) {
    if (list is! List) return [];
    return list.map((e) {
      if (e is String) return e;
      if (e is Map) return e['nome']?.toString() ?? e.values.first.toString();
      return e.toString();
    }).toList();
  }

  Future<void> _analyze() async {
    if (!widget.hasKey) { widget.onRequestKey(); return; }
    if (_currentAudioPath == null) return;
    
    setState(() { _isProcessing = true; _processingStep = "1/4 Transcrevendo..."; });
    
    try {
      // ETAPA 1: Transcrição Local (ou via Gemini simples apenas para áudio->texto)
      // Aqui usamos o Gemini SDK apenas para pegar o texto, já que o backend espera texto
      // (Isso economiza banda de upload de áudio para o nosso backend Python que pode ser lento)
      
      final model = GenerativeModel(
        model: widget.selectedModel, 
        apiKey: widget.apiKey,
      );
      final bytes = await File(_currentAudioPath!).readAsBytes();
      
      final content = [Content.multi([
        TextPart('Transcreva este áudio de consulta médica literalmente.'),
        DataPart('audio/mp4', bytes)
      ])];
      
      var response = await model.generateContent(content);
      String transcript = response.text ?? "";
      
      setState(() => _processingStep = "2/4 Consultando Servidor RAG...");
      
      // ETAPA 2: Envia para Backend Python (RAG + Análise Estruturada) via API
      Map<String, dynamic> apiData = await ApiService.consultarIA(
        transcript, 
        widget.apiKey, 
        model: widget.selectedModel
      );
      
      setState(() => _processingStep = "3/4 Realizando Auditoria Local...");
      
      // ETAPA 3: Processa Resultados
      List<String> meds = _safeStringList(apiData['medicamentos']);
      var auditResult = await _auditMedicines(meds);
      
      apiData['audit'] = auditResult;
      
      // Auto-Screening Logic (Keywords + Patient)
      if (apiData.containsKey('paciente') || apiData.containsKey('keywords')) {
         var p = apiData['paciente'];
         int? age;
         String? sex;
         
         if (p is Map) {
           if (p['idade'] is int && p['idade'] > 0) age = p['idade'];
           if (p['sexo'] is String) sex = p['sexo'];
         }
         
         List<String> kws = [];
         if (apiData['keywords'] is List) {
            kws = (apiData['keywords'] as List).map((e) => e.toString()).toList();
         }
         
         if (age != null || sex != null || kws.isNotEmpty) {
            widget.onMetaDataFound(age, sex, kws);
         }
      }
      
      // Adiciona ID da consulta (timestamp simples para demo) nas missões para persistência
      String consultaId = DateTime.now().millisecondsSinceEpoch.toString();
      apiData['consulta_id'] = consultaId;
      
      setState(() { 
        _analysisResult = apiData; 
        _isProcessing = false; 
        _statusText = "Análise Pronta."; 
      });

    } catch (e) {
      setState(() { _isProcessing = false; _statusText = "Falha no Envio."; });
      if(mounted) showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text("Erro na Análise", style: TextStyle(color: Colors.red)),
        content: SingleChildScrollView(child: Text("Erro: $e")),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      ));
    }
  }

  // ... (Keep existing helpers like _pickAudioFile, _generatePdf)
  // Mas atenção: o _generatePdf precisará ser ajustado se a estrutura de dados mudar muito,
  // mas como mantivemos 'soap' e 'audit', deve funcionar.

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _currentAudioPath = result.files.single.path;
        _statusText = "Arquivo Carregado. Pronto para Enviar.";
        _analysisResult = null;
        _isRecording = false;
      });
    }
  }
   Future<void> _generatePdf() async {
    if (_analysisResult == null) return;
    final doc = pw.Document();
    final soap = _analysisResult!['soap'] ?? {};
    final meds = _analysisResult!['audit']?['items'] as List? ?? [];
    
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Header(level: 0, child: pw.Text("Relatório da Consulta - MedUBS", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800))),
        pw.SizedBox(height: 20),
        
        _pdfSection("Subjetivo", soap['s']),
        _pdfSection("Objetivo", soap['o']),
        _pdfSection("Avaliação", soap['a']),
        _pdfSection("Plano", soap['p']),
        
        if (meds.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Text("Auditoria de Medicamentos", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
          pw.SizedBox(height: 10),
          ...meds.map((m) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 5),
            padding: const pw.EdgeInsets.all(5),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
            child: pw.Row(children: [
               pw.Expanded(child: pw.Text(m['term']?? "", style: const pw.TextStyle(fontSize: 12))),
               if(m['remume']==true) pw.Text(" [REMUME] ", style: const pw.TextStyle(color: PdfColors.green)),
               if(m['rename']==true) pw.Text(" [RENAME] ", style: const pw.TextStyle(color: PdfColors.blue)),
               if(m['alto']==true) pw.Text(" [ALTO CUSTO] ", style: const pw.TextStyle(color: PdfColors.red)),
            ])
          ))
        ],
        pw.Footer(title: pw.Text("Gerado por IA - MedUBS", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)))
      ]
    ));
    
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  pw.Widget _pdfSection(String title, dynamic content) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 15),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
         pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue700)),
         pw.Container(
           width: double.infinity,
           padding: const pw.EdgeInsets.all(8),
           decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(4)),
           child: pw.Text(content?.toString() ?? "", style: const pw.TextStyle(fontSize: 11))
         ),
      ])
    );
  }

  // --- WIDGET BUILDER ---

  Widget _buildSpecialtyBanner() {
    if (widget.activeSpecialty == null) return const SizedBox.shrink();
    return Container(
      color: Colors.indigo,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [const Icon(Icons.star, color: Colors.white, size: 16), const SizedBox(width: 8), Text("Modo: ${widget.activeSpecialty}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
          InkWell(onTap: widget.onClearSpecialty, child: const Icon(Icons.close, color: Colors.white, size: 20))
        ],
      )
    );
  } 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Consultório Híbrido"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings), 
            onPressed: widget.onRequestKey,
            tooltip: "Configurar API Key",
          )
        ],
      ),
      body: Column(children: [
        _buildSpecialtyBanner(),
        Expanded(child: _analysisResult == null ? 
           Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _isProcessing 
                ? const CircularProgressIndicator()
                : Icon(Icons.mic, size: 64, color: widget.hasKey ? Colors.blue[100] : Colors.grey[300]),
              const SizedBox(height: 10),
              Text(
                _isProcessing ? _processingStep : (widget.hasKey ? _statusText : "Configure a Key para usar a IA"), 
                style: TextStyle(color: _isProcessing ? Colors.blue : Colors.grey, fontWeight: _isProcessing ? FontWeight.bold : FontWeight.normal)
              ),
              if (_currentAudioPath != null && !_isProcessing) ...[
                 const SizedBox(height: 20),
                 const Text("✅ Áudio pronto! Toque no avião para enviar.", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))
              ]
           ])) 
           : _buildResultList()),
        const SizedBox(height: 10),
        Padding(padding: const EdgeInsets.all(16), child: 
          widget.hasKey 
          ? Row(children: [
              IconButton.outlined(onPressed: _isProcessing ? null : _pickAudioFile, icon: const Icon(Icons.upload), tooltip: "Upload Arquivo"), 
              const SizedBox(width: 8),
              if (_analysisResult != null) ...[
                  IconButton.outlined(onPressed: _generatePdf, icon: const Icon(Icons.picture_as_pdf, color: Colors.red), tooltip: "Gerar PDF"),
                  const SizedBox(width: 8),
              ],
              Expanded(child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _toggleRecording, 
                icon: Icon(_isRecording?Icons.stop:Icons.mic), 
                label: Text(_isRecording?"PARAR":"GRAVAR"),
                style: ElevatedButton.styleFrom(backgroundColor: _isRecording?Colors.red:Colors.blue[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15))
              )),
              const SizedBox(width: 10),
              IconButton.filled(onPressed: _isProcessing ? null : _analyze, icon: const Icon(Icons.send), tooltip: "Enviar para IA")
            ])
          : SizedBox(width: double.infinity, child: ElevatedButton(onPressed: widget.onRequestKey, child: const Text("CONFIGURAR GOOGLE API KEY")))
        )
      ]),
    );
  }

  Widget _buildResultList() {
    final soap = _analysisResult!['soap'] ?? {};
    final meds = _analysisResult!['audit']?['items'] as List? ?? [];
    final jsonMissoes = _analysisResult!['missoes'];
    String consultaId = _analysisResult!['consulta_id'] ?? DateTime.now().toString();

    // Converte jsonMissoes para List<dynamic> seguro
    List missoes = [];
    if (jsonMissoes is List) missoes = jsonMissoes;

    return ListView(padding: const EdgeInsets.all(16), children: [ 
       // --- NOVO COMPONENTE: MISSÕES ---
       if (missoes.isNotEmpty)
         MissionWidget(missoesIniciais: missoes, consultaId: consultaId),
       
       // Cards SOAP Normais
       _card("S", "Subjetivo", soap['s']?.toString() ?? "", Colors.blue),
       _card("O", "Objetivo", soap['o']?.toString() ?? "", Colors.teal),
       _card("A", "Avaliação", soap['a']?.toString() ?? "", Colors.orange),
       _card("P", "Plano", soap['p']?.toString() ?? "", Colors.purple),
       
       if (meds.isNotEmpty) ...[
         const SizedBox(height: 20),
         const Text("💊 Auditoria de Medicamentos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
         const SizedBox(height: 10),
         ...meds.map((m) => Card(
           margin: const EdgeInsets.only(bottom: 8),
           child: ListTile(
             contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
             title: Text(m['term'] ?? "", style: const TextStyle(fontWeight: FontWeight.w500)),
             subtitle: Wrap(spacing: 8, runSpacing: 4, children: [
               if(m['remume']==true) _badge("REMUME", Colors.green),
               if(m['rename']==true) _badge("RENAME", Colors.blue),
               if(m['alto']==true) _badge("ALTO CUSTO", Colors.red),
               if(m['remume']!=true && m['rename']!=true && m['alto']!=true) _badge("NÃO ENCONTRADO", Colors.grey),
             ]),
           ),
         ))
       ]
    ]);
  }

  Widget _badge(String text, Color col) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: col.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: col)),
    child: Text(text, style: TextStyle(fontSize: 10, color: col, fontWeight: FontWeight.bold)),
  );

  Widget _card(String l, String t, String c, Color col) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(backgroundColor: col.withOpacity(0.1), child: Text(l, style: TextStyle(color: col, fontWeight: FontWeight.bold))),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 16))),
          IconButton(
            icon: const Icon(Icons.copy, size: 20, color: Colors.grey), 
            onPressed: () {
               Clipboard.setData(ClipboardData(text: c));
               if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copiado!"), duration: Duration(milliseconds: 500)));
            }
          )
        ]),
        const Divider(),
        Text(c, style: const TextStyle(fontSize: 15, height: 1.4)),
      ]),
    )
  );
}

// ---------------- SPECIALTIES ----------------
class SpecialtiesTab extends StatelessWidget {
  final String apiKey;
  final bool hasKey;
  final Function(String) onSpecialtySelected;

  const SpecialtiesTab({super.key, required this.apiKey, required this.hasKey, required this.onSpecialtySelected});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Especialidades")),
      body: hasKey ? GridView.count(crossAxisCount: 2, padding: const EdgeInsets.all(16), crossAxisSpacing: 10, mainAxisSpacing: 10, children: [
        _tile(Icons.child_care, "Pediatria", Colors.orange, context),
        _tile(Icons.pregnant_woman, "Pré-Natal", Colors.pink, context),
        _tile(Icons.spa, "Dermatologia", Colors.brown, context),
        _tile(Icons.psychology, "Saúde Mental", Colors.purple, context),
      ]) : const Center(child: Text("Requer API Key")),
    );
  }
  Widget _tile(IconData i, String t, Color c, BuildContext context) => Card(color: c.withOpacity(0.1), child: InkWell(onTap: () => onSpecialtySelected(t), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 40, color: c), Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold))])));
}

// ---------------- LIVE TAB (Restored) ----------------
class LiveTab extends StatelessWidget {
  final String apiKey;
  final bool hasKey;
  const LiveTab({super.key, required this.apiKey, required this.hasKey});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ao Vivo")), 
      body: Center(child: hasKey 
        ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.multitrack_audio, size: 80, color: Colors.blue), SizedBox(height: 20), Text("Conecte ao Servidor Python para Streaming")])
        : const Text("Requer API Key")
      )
    );
  }
}

// ---------------- SCREENING (Auto) ---------------- (Optimized)
class ScreeningTab extends StatefulWidget {
  final String apiKey;
  final bool hasKey;
  final String selectedModel;
  final int? initialAge;
  final String? initialSex;
  final List<String> keywords;
  final VoidCallback onRequestKey;

  const ScreeningTab({super.key, required this.apiKey, required this.hasKey, required this.selectedModel, this.initialAge, this.initialSex, this.keywords = const [], required this.onRequestKey});
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
  void didUpdateWidget(ScreeningTab old) { 
    super.didUpdateWidget(old); 
    // Logic: Only update if demographics OR keywords actually CHANGED and we have a key.
    if(widget.initialAge!=old.initialAge || widget.initialSex!=old.initialSex || widget.keywords != old.keywords) { 
      _upd(); 
      // Prevention: Don't auto-run if we already have a result or are loading, unless forced by new keywords?
      // Better: Auto-run if keywords changed, even if we have result.
      bool kwChanged = widget.keywords.toString() != old.keywords.toString();
      if(widget.initialAge!=null && widget.hasKey && (_result.isEmpty || kwChanged) && !_loading) _check(); 
    } 
  }

  void _upd() { if(widget.initialAge!=null) _ageCtrl.text=widget.initialAge.toString(); if(widget.initialSex!=null) _sex=widget.initialSex!; }

  Future<void> _check() async {
    if (!widget.hasKey) { widget.onRequestKey(); return; }
    if (_loading) return;
    
    setState(() => _loading = true);
    try {
       // Using user selected model
       final model = GenerativeModel(model: widget.selectedModel, apiKey: widget.apiKey);
       String contextPrompt = widget.keywords.isNotEmpty ? "Contexto clínico: ${widget.keywords.join(', ')}." : "";
       final res = await model.generateContent([Content.text("Atue como médico. Paciente $_sex, ${_ageCtrl.text} anos. $contextPrompt Liste APENAS os rastreamentos (screening) indicados pelo Ministério da Saúde do Brasil em tópicos curtos.")]);
       setState(() => _result = res.text ?? "-");
    } catch(e) { 
       String msg = "Erro: $e";
       if (e.toString().contains("429") || e.toString().contains("quota")) {
         msg = "⚠️ Cota do Gemini excedida. Tente em 1 min.";
       }
       setState(() => _result = msg); 
    } 
    finally { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rastreio e Prevenção")),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
         // Input Area
         Card(
           elevation: 0,
           color: Colors.blue[50], 
           child: Padding(
             padding: const EdgeInsets.all(16),
             child: Column(children: [
               Row(children: [
                 Expanded(child: TextField(controller: _ageCtrl, decoration: const InputDecoration(labelText: "Idade", border: OutlineInputBorder(), prefixIcon: Icon(Icons.cake)), keyboardType: TextInputType.number)), 
                 const SizedBox(width: 10), 
                 Expanded(child: DropdownButtonFormField(value: _sex, items: ["Feminino","Masculino"].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(), onChanged:(v)=>setState(()=>_sex=v!), decoration: const InputDecoration(labelText:"Sexo",border:OutlineInputBorder(), prefixIcon: Icon(Icons.person))))
               ]),
               const SizedBox(height: 10),
               SizedBox(width: double.infinity, child: FilledButton.icon(
                 onPressed: _loading?null:_check, 
                 icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.search),
                 label: Text(_loading ? "Analisando..." : (widget.hasKey ? "Gerar Protocolo de Rastreio" : "Configurar API Key"))
               )),
             ])
           ),
         ),
         const SizedBox(height: 20),
         
         // Result Area
         Expanded(child: _result.isEmpty 
           ? Center(child: Text("Preencha os dados acima para ver\nas diretrizes do MS.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[400])))
           : SingleChildScrollView(
               child: Card(
                 elevation: 2,
                 child: Container(
                   width: double.infinity,
                   padding: const EdgeInsets.all(20),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Row(children: [
                         Icon(Icons.health_and_safety, color: Colors.teal[700]),
                         const SizedBox(width: 10),
                         Text("Protocolo Sugerido", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal[800]))
                       ]),
                       const Divider(height: 30),
                       SelectableText.rich(
                         TextSpan(children: _parseBoldText(_result)), 
                         style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
                       ),
                     ],
                   )
                 ),
               )
             )
         )
      ])),
    );
  }

  // Helper to parse **bold**
  List<TextSpan> _parseBoldText(String text) {
    final List<TextSpan> spans = [];
    final List<String> parts = text.split('**');
    
    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 1) {
        // Odd parts are inside ** ** (Bold)
        spans.add(TextSpan(text: parts[i], style: const TextStyle(fontWeight: FontWeight.bold)));
      } else {
        // Even parts are normal text
        spans.add(TextSpan(text: parts[i]));
      }
    }
    return spans;
  }
}

// ---------------- OFFLINE (Free) ----------------
class OfflineTab extends StatefulWidget {
  final String apiKey;
  const OfflineTab({super.key, required this.apiKey}); // Corrigido
  @override
  State<OfflineTab> createState() => _OfflineTabState();
}

class _OfflineTabState extends State<OfflineTab> {
  List<FileSystemEntity> _files = [];
  String? _storagePath;

  Future<void> loadFiles() async {
     try {
       final d = await getApplicationDocumentsDirectory();
       final s = Directory('${d.path}/medubs_logs');
       setState(() => _storagePath = s.path);
       if(await s.exists()) setState(() => _files = s.listSync()..sort((a,b)=>b.statSync().modified.compareTo(a.statSync().modified)));
     } catch (_) {}
  }
  @override void initState() { super.initState(); loadFiles(); }

  Future<void> _openFile(String path) async {
    final result = await OpenFile.open(path);
    if (result.type != ResultType.done) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao abrir: ${result.message}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Offline / Logs"), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: loadFiles)]),
      body: Column(children: [
        if (_storagePath != null) Container(width: double.infinity, color: Colors.grey[200], padding: const EdgeInsets.all(8), child: Text("Local: $_storagePath", style: const TextStyle(fontSize: 10, color: Colors.grey))),
        Expanded(child: _files.isEmpty ? const Center(child: Text("Nenhum arquivo.")) : ListView.builder(itemCount: _files.length, itemBuilder: (c,i) {
           final f = _files[i];
           return Card(child: ListTile(leading: const Icon(Icons.play_circle_fill, color: Colors.blue, size: 32), title: Text(f.path.split('/').last), subtitle: Text("${(f.statSync().size/1024).toStringAsFixed(1)} KB • Toque para Ouvir"), onTap: () => _openFile(f.path)));
        }))
      ]),
    );
  }
}
