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

void main() {
  runApp(const MedUBSApp());
}

class MedUBSApp extends StatelessWidget {
  const MedUBSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedUBS v2.5',
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
      _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
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
            setState(() {}); 
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
        activeSpecialty: _activeSpecialty,
        onClearSpecialty: _clearSpecialty,
        onMetaDataFound: _updateDemographics,
        onFileSaved: _notifyOfflineFileSaved,
        onRequestKey: () => _showSettings(context),
      ),
      LiveTab(apiKey: _apiKeyController.text, hasKey: hasKey),
      SpecialtiesTab(
        apiKey: _apiKeyController.text, 
        hasKey: hasKey,
        onSpecialtySelected: _activateSpecialty,
      ),
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
  final String? activeSpecialty;
  final VoidCallback onClearSpecialty;
  final Function(int?, String?) onMetaDataFound;
  final VoidCallback onFileSaved;
  final VoidCallback onRequestKey;

  const HomeTab({
    super.key, 
    required this.apiKey, 
    required this.hasKey,
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
  String _processingStep = ""; // New: Progress Step
  String? _currentAudioPath;
  Map<String, dynamic>? _analysisResult;
  String _statusText = "Pronto";
  List<String> _dbRemumeNames = [];
  List<String> _dbRenameNames = [];
  List<String> _dbAltoCustoNames = [];

  @override
  void initState() {
    super.initState();
    _loadDatabases();
  }

  // ... (Keep _loadDatabases and _saveToSafeStorage as is)

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
  
  // Robust Helpers
  List<String> _safeStringList(dynamic list) {
    if (list is! List) return [];
    return list.map((e) {
      if (e is String) return e;
      if (e is Map) return e['nome']?.toString() ?? e.values.first.toString();
      return e.toString();
    }).toList();
  }

  String _safeString(dynamic v) {
     if (v is String) return v;
     if (v is Map) return v.values.join("\n");
     return v?.toString() ?? "";
  }

  Future<void> _analyze() async {
    if (!widget.hasKey) { widget.onRequestKey(); return; }
    if (_currentAudioPath == null) return;
    
    setState(() { _isProcessing = true; _processingStep = "1/4 Preparando Áudio..."; });
    
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: widget.apiKey);
      final bytes = await File(_currentAudioPath!).readAsBytes();
      
      setState(() => _processingStep = "2/4 Consultando API IA...");
      
      String specialtyContext = "";
      if (widget.activeSpecialty != null) {
        specialtyContext = "MODO ESPECIALISTA ATIVADO: ${widget.activeSpecialty}. Focar exames, diagnósticos e condutas específicas desta área.";
      }

      final content = [Content.multi([
        TextPart('''
          ATUE COMO MÉDICO DE FAMÍLIA. $specialtyContext
          Gere JSON SOAP. Metadados 'paciente': {'idade': int, 'sexo': 'Masculino'/'Feminino'}.
          Critica TÉCNICA apenas.
          { "soap": {"s":"", "o":"", "a":"", "p":""}, "criticas": {"s":"", "o":"", "a":"", "p":""}, "medicamentos": [], "paciente": {} }
        '''),
        DataPart('audio/mp4', bytes)
      ])];
      
      var response = await model.generateContent(content);
      
      setState(() => _processingStep = "3/4 Processando Dados...");
      
      final clean = response.text!.replaceAll('```json','').replaceAll('```','').trim();
      final data = json.decode(clean);
      if (data.containsKey('paciente')) {
        widget.onMetaDataFound(data['paciente']['idade'], data['paciente']['sexo']);
      }
      
      setState(() => _processingStep = "4/4 Concluindo...");
      
      // Safe parsing
      data['medicamentos'] = _safeStringList(data['medicamentos']);
      var soap = data['soap'] ?? {};
      soap['s'] = _safeString(soap['s']);
      soap['o'] = _safeString(soap['o']);
      soap['a'] = _safeString(soap['a']);
      soap['p'] = _safeString(soap['p']);
      
      data['audit'] = _auditMedicines(List<String>.from(data['medicamentos']));
      setState(() { _analysisResult = data; _isProcessing = false; _statusText = "Análise Pronta."; });

    } catch (e) {
      setState(() { _isProcessing = false; _statusText = "Falha no Envio."; });
      if(mounted) showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text("Erro na Análise IA", style: TextStyle(color: Colors.red)),
        content: SingleChildScrollView(child: Text("Ocorreu um erro ao conectar com o Gemini.\n\nDetalhe técnico:\n$e\n\nVerifique:\n1. Sua Internet\n2. Se a API Key é válida")),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      ));
    }
  }

  Map<String, dynamic> _auditMedicines(List<String> meds) {
    bool chk(List<String> db, String q) {
      final query = removeDiacritics(q.toLowerCase());
      return db.any((e) => removeDiacritics(e.toLowerCase()).contains(query));
    }
    return {"items": meds.map((m) => {"term": m, "remume": chk(_dbRemumeNames,m), "rename": chk(_dbRenameNames,m), "alto": chk(_dbAltoCustoNames,m)}).toList()};
  }
  
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
    final crit = _analysisResult!['criticas'] ?? {};
    final meds = _analysisResult!['audit']?['items'] as List? ?? [];
    
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Header(level: 0, child: pw.Text("Relatório da Consulta - MedUBS", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800))),
        pw.SizedBox(height: 20),
        
        _pdfSection("Subjetivo", soap['s'], crit['s']),
        _pdfSection("Objetivo", soap['o'], crit['o']),
        _pdfSection("Avaliação", soap['a'], crit['a']),
        _pdfSection("Plano", soap['p'], crit['p']),
        
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

  pw.Widget _pdfSection(String title, String? content, String? critique) {
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
         if (critique != null && critique.isNotEmpty)
           pw.Padding(padding: const pw.EdgeInsets.only(top: 5, left: 10), child: pw.Text("Nota Técnica: $critique", style: pw.TextStyle(fontSize: 10, color: PdfColors.red700, fontStyle: pw.FontStyle.italic)))
      ])
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Consultório"),
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
    final crit = _analysisResult!['criticas'] ?? {};
    final meds = _analysisResult!['audit']?['items'] as List? ?? [];

    return ListView(padding: const EdgeInsets.all(16), children: [ 
       _card("S", "Subjetivo", soap['s']?.toString() ?? "", crit['s']?.toString(), Colors.blue),
       _card("O", "Objetivo", soap['o']?.toString() ?? "", crit['o']?.toString(), Colors.teal),
       _card("A", "Avaliação", soap['a']?.toString() ?? "", crit['a']?.toString(), Colors.orange),
       _card("P", "Plano", soap['p']?.toString() ?? "", crit['p']?.toString(), Colors.purple),
       
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

  Widget _card(String l, String t, String c, String? critique, Color col) => Card(
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
        if (critique != null && critique.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red[100]!)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 const Icon(Icons.info_outline, color: Colors.red, size: 20),
                 const SizedBox(width: 8),
                 Expanded(child: Text("Observação Técnica: $critique", style: TextStyle(color: Colors.red[900], fontSize: 13, fontStyle: FontStyle.italic)))
              ],
            )
          )
        ]
      ]),
    )
  );
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

// ---------------- SCREENING (Auto) ---------------- (Optimized)
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
  void didUpdateWidget(ScreeningTab old) { 
    super.didUpdateWidget(old); 
    // Logic: Only update if demographics actually CHANGED and we have a key.
    if(widget.initialAge!=old.initialAge || widget.initialSex!=old.initialSex) { 
      _upd(); 
      // Prevention: Don't auto-run if we already have a result or are loading.
      if(widget.initialAge!=null && widget.hasKey && _result.isEmpty && !_loading) _check(); 
    } 
  }

  void _upd() { if(widget.initialAge!=null) _ageCtrl.text=widget.initialAge.toString(); if(widget.initialSex!=null) _sex=widget.initialSex!; }

  Future<void> _check() async {
    if (!widget.hasKey) { widget.onRequestKey(); return; }
    if (_loading) return;
    
    setState(() => _loading = true);
    try {
       // Using gemini-2.5-flash as standard
       final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: widget.apiKey);
       final res = await model.generateContent([Content.text("Atue como médico. Paciente $_sex, ${_ageCtrl.text} anos. Liste APENAS os rastreamentos (screening) indicados pelo Ministério da Saúde do Brasil em tópicos curtos.")]);
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
      appBar: AppBar(title: const Text("Rastreio (Auto)")),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
         Row(children: [Expanded(child: TextField(controller: _ageCtrl, decoration: const InputDecoration(labelText: "Idade", border: OutlineInputBorder()))), const SizedBox(width: 10), Expanded(child: DropdownButtonFormField(value: _sex, items: ["Feminino","Masculino"].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(), onChanged:(v)=>setState(()=>_sex=v!), decoration: const InputDecoration(labelText:"Sexo",border:OutlineInputBorder())))]),
         const SizedBox(height: 10),
         SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _loading?null:_check, child: Text(_loading ? "Consultando Gemini 1.5..." : (widget.hasKey ? "Verificar Protocolos" : "Configurar Key")))),
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
