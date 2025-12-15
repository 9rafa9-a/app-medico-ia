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
      title: 'MedUBS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0052CC), // Medical Blue
          primary: const Color(0xFF0052CC), 
          secondary: const Color(0xFF00BFA5), // Teal
          tertiary: const Color(0xFFFF6D00), // Orange for alerts
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
          scrolledUnderElevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _apiKeyController = TextEditingController();
  final _audioRecorder = Record();
  
  bool _isRecording = false;
  bool _isProcessing = false;
  
  String _statusText = "Toque para iniciar";
  Color _statusColor = Colors.grey;
  
  String? _currentAudioPath;
  Map<String, dynamic>? _analysisResult;

  // Databases
  List<String> _dbRemumeNames = [];
  List<String> _dbRenameNames = [];
  List<String> _dbAltoCustoNames = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadDatabases();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
      if (_apiKeyController.text.isEmpty) {
        // Delay to allow context to be ready
        Future.delayed(Duration.zero, () => _showSettings(context));
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', _apiKeyController.text);
  }

  Future<void> _loadDatabases() async {
    try {
      List<String> extractNames(dynamic json, String source) {
        List<String> names = [];
        if (json is List) {
          for (var item in json) {
            if (item is Map && (item.containsKey('nome') || item.containsKey('nome_completo'))) {
              names.add((item['nome'] ?? item['nome_completo']).toString());
            } else if (item is Map && item.containsKey('itens') && item['itens'] is List) {
               for (var subItem in item['itens']) {
                 if (subItem is Map && subItem.containsKey('nome')) {
                   names.add(subItem['nome'].toString());
                 }
               }
            }
          }
        }
        return names;
      }

      final remumeJson = json.decode(await rootBundle.loadString('assets/db_remume.json'));
      final renameJson = json.decode(await rootBundle.loadString('assets/db_rename.json'));
      final altoCustoJson = json.decode(await rootBundle.loadString('assets/db_alto_custo.json'));

      setState(() {
        _dbRemumeNames = extractNames(remumeJson, "REMUME");
        _dbRenameNames = extractNames(renameJson, "RENAME");
        _dbAltoCustoNames = extractNames(altoCustoJson, "ALTO CUSTO");
      });
    } catch (e) {
      print("Erro DB: $e");
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _currentAudioPath = path;
        _statusText = "Áudio Gravado.";
        _statusColor = Colors.green;
      });
    } else {
      if (await Permission.microphone.request().isGranted) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(path: path, encoder: AudioEncoder.aacLc);
        
        setState(() {
          _isRecording = true;
          _statusText = "Gravando... (Toque para parar)";
          _statusColor = Colors.red;
          _analysisResult = null;
        });
      }
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
      );

      if (result != null) {
        setState(() {
          _currentAudioPath = result.files.single.path;
          _statusText = "Arquivo: ${result.files.single.name}";
          _statusColor = Colors.blue;
          _analysisResult = null;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e")));
    }
  }

  Future<void> _runAnalysis() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSettings(context);
      return;
    }
    await _saveSettings();

    if (_currentAudioPath == null) return;

    setState(() {
      _isProcessing = true;
      _statusText = "Analisando com Gemini 2.5...";
      _statusColor = Theme.of(context).primaryColor;
    });

    try {
      final file = File(_currentAudioPath!);
      final bytes = await file.readAsBytes();
      
      // Explicitly requested model
      const modelName = 'gemini-2.5-flash'; 
      var model = GenerativeModel(model: modelName, apiKey: apiKey);

      final content = [
        Content.multi([
          TextPart('''
            Atue como um Especialista em Saúde da Família (Medicina). 
            Analise o áudio da consulta e gere um JSON.
            
            ESTRUTURA:
            Use o formato SOAP. Preencha cada campo com detalhes técnicos.
            Dr. House Mode ON: Para cada seção (S, O, A, P), se identificar erros, negligências, faltas de perguntas sobre alergias ou riscos, inclua uma crítica.
            IMPORTANTE: A crítica deve ser EXCLUSIVAMENTE TÉCNICA, OBJETIVA E BASEADA EM EVIDÊNCIAS. Evite tom emocional, sarcasmo desnecessário ou julgamento moral. Foque no erro clínico.
            
            SAÍDA JSON OBRIGATÓRIA:
            {
              "soap": { 
                "s": "Texto do Subjetivo...", 
                "o": "Texto do Objetivo...", 
                "a": "Texto da Avaliação...", 
                "p": "Texto do Plano..." 
              },
              "criticas": {
                "s": "Crítica específica para o Subjetivo (ex: faltou perguntar histórico)",
                "o": "Crítica para o Objetivo (ex: esqueceu de aferir PA)",
                "a": "Crítica para Avaliação",
                "p": "Crítica para Plano (ex: interação medicamentosa ignorada)"
              },
              "medicamentos": ["nome_generico_1", "nome_generico_2"]
            }
          '''),
          DataPart('audio/mp4', bytes)
        ])
      ];

      GenerateContentResponse? response;
      try {
         response = await model.generateContent(content);
      } catch (e) {
         // Fallback logic
         print("Model $modelName falhou, tentando 2.0-flash: $e");
         final fallback = GenerativeModel(model: 'gemini-2.0-flash', apiKey: apiKey);
         response = await fallback.generateContent(content);
      }
      
      if (response == null || response.text == null) throw "Sem resposta da IA";

      String cleanJson = response.text!
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
          
      final data = json.decode(cleanJson);
      
      // Audit Meds
      final medsRaw = List<String>.from(data['medicamentos'] ?? []);
      final audit = _auditMedicines(medsRaw);
      data['audit'] = audit;

      setState(() {
        _analysisResult = data;
        _statusText = "Análise Pronta!";
        _statusColor = Colors.teal;
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = "Erro na análise";
          _statusColor = Colors.red;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e")));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Map<String, dynamic> _auditMedicines(List<String> meds) {
    List<Map<String, dynamic>> results = [];
    int remumeCount = 0;
    int renameCount = 0;

    bool searchIn(List<String> db, String query) {
      final q = removeDiacritics(query.toLowerCase());
      return db.any((element) {
        final e = removeDiacritics(element.toLowerCase());
        return e.contains(q) || q.contains(e);
      });
    }

    for (var med in meds) {
      final inRemume = searchIn(_dbRemumeNames, med);
      final inRename = searchIn(_dbRenameNames, med);
      final inAlto = searchIn(_dbAltoCustoNames, med);

      if (inRemume) remumeCount++;
      if (inRename) renameCount++;

      results.add({
        "term": med,
        "remume": inRemume,
        "rename": inRename,
        "alto": inAlto
      });
    }

    return {
      "items": results,
      "counts": {"remume": remumeCount, "rename": renameCount}
    };
  }

  // --- PDF EXPORT ---
  Future<void> _generatePdf() async {
    if (_analysisResult == null) return;
    final pdf = pw.Document();
    
    // Extract Data
    final soap = _analysisResult!['soap']; // Map
    final criticas = _analysisResult!['criticas'] ?? {};
    final audit = _analysisResult!['audit']['items'] as List;

    final fontBold = await PdfGoogleFonts.poppinsBold();
    final fontReg = await PdfGoogleFonts.poppinsRegular();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text("MedUBS AI Report", style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.blue900)),
              pw.Text(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()), style: pw.TextStyle(font: fontReg, fontSize: 10)),
            ])
          ),
          pw.SizedBox(height: 20),
          
          _pdfSection("SUBJETIVO", soap['s'], criticas['s'], fontBold, fontReg, PdfColors.blue700),
          _pdfSection("OBJETIVO", soap['o'], criticas['o'], fontBold, fontReg, PdfColors.teal700),
          _pdfSection("AVALIAÇÃO", soap['a'], criticas['a'], fontBold, fontReg, PdfColors.orange700),
          _pdfSection("PLANO", soap['p'], criticas['p'], fontBold, fontReg, PdfColors.purple700),

          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text("AUDITORIA DE MEDICAMENTOS", style: pw.TextStyle(font: fontBold, fontSize: 12)),
          pw.SizedBox(height: 10),
          
           pw.Table.fromTextArray(
            headers: ["Medicamento", "REMUME", "RENAME", "Alto Custo"],
            data: audit.map((e) => [
              e['term'].toString().toUpperCase(),
              e['remume'] ? "SIM" : "-",
              e['rename'] ? "SIM" : "-",
              e['alto'] ? "SIM" : "-"
            ]).toList(),
            headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.center, 2: pw.Alignment.center, 3: pw.Alignment.center}
          )
        ]
      )
    );
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'MedUBS_Relatorio.pdf');
  }

  pw.Widget _pdfSection(String title, String? content, String? critique, pw.Font bold, pw.Font reg, PdfColor color) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 11, color: color)),
        pw.Text(content ?? "-", style: pw.TextStyle(font: reg, fontSize: 10)),
        if (critique != null && critique.isNotEmpty)
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 4),
            padding: const pw.EdgeInsets.all(5),
            decoration: pw.BoxDecoration(color: PdfColors.red50, border: pw.Border.all(color: PdfColors.red200)),
            child: pw.Row(children: [
               pw.Text("ALERTA: ", style: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.red900)),
               pw.Expanded(child: pw.Text(critique, style: pw.TextStyle(font: reg, fontSize: 8, color: PdfColors.red900)))
            ])
          )
      ])
    );
  }

  // --- UI WIDGETS ---

  @override
  Widget build(BuildContext context) {
    final hasKey = _apiKeyController.text.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monitor_heart, color: Color(0xFF0052CC)),
            SizedBox(width: 8),
            Text("MedUBS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: Colors.grey[700]),
            onPressed: () => _showSettings(context),
          )
        ],
      ),
      body: Column(
        children: [
          // Header Status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDbChip("REMUME", _dbRemumeNames.length),
                const SizedBox(width: 8),
                _buildDbChip("RENAME", _dbRenameNames.length),
                const SizedBox(width: 8),
                _buildDbChip("ALTO CUSTO", _dbAltoCustoNames.length),
              ],
            ),
          ),
          
          Expanded(child: _buildBody(hasKey)),
          
          _buildBottomBar(hasKey),
        ],
      ),
    );
  }

  Widget _buildBody(bool hasKey) {
    if (!hasKey) {
       return Center(
         child: Column(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
             Icon(Icons.key_off, size: 64, color: Colors.grey[300]),
             const SizedBox(height: 16),
             const Text("Configure a API Key para começar"),
             TextButton(onPressed: () => _showSettings(context), child: const Text("Configurar agora"))
           ],
         ),
       );
    }
    
    if (_analysisResult == null) {
      if (_isProcessing) return const Center(child: CircularProgressIndicator());
      
      // Placeholder state
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue.withOpacity(0.05)),
                child: Icon(Icons.mic, size: 64, color: Colors.blue[200]),
              ),
              const SizedBox(height: 24),
              Text("Pronto para Ouvir", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey[800])),
              const SizedBox(height: 8),
              Text("Grave uma consulta ou envie um áudio", style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    // Results List
    final soap = _analysisResult!['soap'];
    final criticas = _analysisResult!['criticas'] ?? {};
    final audit = _analysisResult!['audit']['items'] as List;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard("Subjetivo", "S", soap['s'], criticas['s'], Colors.blue),
        _buildSectionCard("Objetivo", "O", soap['o'], criticas['o'], Colors.teal),
        _buildSectionCard("Avaliação", "A", soap['a'], criticas['a'], Colors.orange),
        _buildSectionCard("Plano", "P", soap['p'], criticas['p'], Colors.purple),
        
        const SizedBox(height: 16),
        _buildDebugPanel(audit),
      ],
    );
  }

  Widget _buildSectionCard(String title, String letter, String? content, String? critique, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16, 
                  backgroundColor: color.withOpacity(0.1),
                  child: Text(letter, style: TextStyle(color: color, fontWeight: FontWeight.bold))
                ),
                const SizedBox(width: 12),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
            Text(
              content ?? "Não informado.",
              style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
            ),
            
            if (critique != null && critique.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50], 
                  border: Border.all(color: Colors.red[100]!),
                  borderRadius: BorderRadius.circular(8)
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                       Icon(Icons.gavel, size: 16, color: Colors.red[800]),
                       const SizedBox(width: 8),
                       Text("CRÍTICA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red[900]))
                    ]),
                    const SizedBox(height: 4),
                    Text(critique, style: TextStyle(fontSize: 13, color: Colors.red[900], fontStyle: FontStyle.italic)),
                  ],
                ),
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildDebugPanel(List items) {
     return ExpansionTile(
       title: const Text("Auditoria de Medicamentos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
       leading: const Icon(Icons.bug_report, size: 20),
       children: items.map<Widget>((item) {
         final foundAny = item['remume'] || item['rename'] || item['alto'];
         final icon = foundAny ? Icons.check_circle : Icons.cancel;
         final color = foundAny ? Colors.green : Colors.red;
         
         return ListTile(
            dense: true,
            leading: Icon(icon, color: color, size: 18),
            title: Text(item['term'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Row(
               children: [
                 _miniTag("REMUME", item['remume']),
                 _miniTag("RENAME", item['rename']),
                 _miniTag("ALTO CUSTO", item['alto']),
               ],
            ),
         );
       }).toList(),
     );
  }

  Widget _miniTag(String text, bool active) {
    if (!active) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.grey[200], 
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.grey[400]!)
      ),
      child: Text(text, style: const TextStyle(fontSize: 9, color: Colors.black)),
    );
  }

  Widget _buildDbChip(String label, int count) {
    return Container(
       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
       decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
       child: Text("$label: $count", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[800])),
    );
  }

  Widget _buildBottomBar(bool hasKey) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0,-5))],
      ),
      child: SafeArea( // iPhone home bar safe
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_statusText.isNotEmpty)
              Padding(
                 padding: const EdgeInsets.only(bottom: 12),
                 child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(_statusText, style: TextStyle(color: _statusColor, fontWeight: FontWeight.bold))
                 ]),
              ),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_isProcessing || _isRecording) ? null : _pickAudioFile,
                    icon: const Icon(Icons.upload_file), 
                    label: const Text("Upload"),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: hasKey ? _toggleRecording : null,
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                    label: Text(_isRecording ? "PARAR GRAVAÇÃO" : "GRAVAR CONSULTA"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.red : Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                 if (_analysisResult != null)
                   IconButton.filled(
                      onPressed: _generatePdf, 
                      icon: const Icon(Icons.picture_as_pdf),
                      tooltip: "Baixar PDF",
                   )
                 else
                   IconButton.filledTonal(
                     onPressed: _currentAudioPath != null && !_isProcessing ? _runAnalysis : null,
                     icon: const Icon(Icons.auto_awesome),
                   )
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Configurações"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Insira sua Gemini API Key para utilizar o aplicativo.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: "API Key", 
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key)
              ),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            
            // HELP LINK (Added as requested)
            InkWell(
              onTap: () async {
                 final Uri url = Uri.parse("https://aistudio.google.com/app/api-keys");
                 if (!await launchUrl(url)) {
                   if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Não foi possível abrir o link")));
                 }
              },
              child: const Row(
                children: [
                   Icon(Icons.help_outline, size: 16, color: Colors.blue),
                   SizedBox(width: 4),
                   Text("Onde conseguir minha chave?", style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Center(child: Text("Modelo: Gemini 2.5 Flash (BETA)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("SALVAR"))
        ],
      )
    );
  }
}
