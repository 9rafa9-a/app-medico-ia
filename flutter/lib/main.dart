import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:diacritic/diacritic.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:intl/intl.dart';

// --- MAIN ENTRYPOINT ---
void main() {
  runApp(const MedUBSApp());
}

// --- APP CONFIG ---
class MedUBSApp extends StatelessWidget {
  const MedUBSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedUBS',
      theme: ThemeData(
        primaryColor: const Color(0xFF0052CC), // Medical Blue
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0052CC)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0052CC),
          foregroundColor: Colors.white,
          elevation: 4,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// --- HOME SCREEN ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // State
  final _apiKeyController = TextEditingController();
  final _audioRecorder = AudioRecorder();
  
  bool _isRecording = false;
  bool _isProcessing = false;
  String _statusText = "Aguardando ação...";
  Color _statusColor = Colors.grey;
  
  String? _currentAudioPath;
  Map<String, dynamic>? _analysisResult;

  // Databases
  List<dynamic> _dbRemume = [];
  List<dynamic> _dbRename = [];
  List<dynamic> _dbAltoCusto = [];

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
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', _apiKeyController.text);
  }

  Future<void> _loadDatabases() async {
    try {
      _dbRemume = json.decode(await rootBundle.loadString('assets/db_remume.json'));
      _dbRename = json.decode(await rootBundle.loadString('assets/db_rename.json'));
      _dbAltoCusto = json.decode(await rootBundle.loadString('assets/db_alto_custo.json'));
    } catch (e) {
      print("Erro DB: $e");
    }
  }

  // --- LOGIC: RECORDING ---
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // STOP
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _currentAudioPath = path;
        _statusText = "Áudio capturado. Pronto para analisar.";
        _statusColor = Colors.green;
      });
    } else {
      // START
      if (await Permission.microphone.request().isGranted) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
          _statusText = "Gravando... (Toque para parar)";
          _statusColor = Colors.red;
          _analysisResult = null; // Clear previous
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de microfone negada.')),
        );
      }
    }
  }

  // --- LOGIC: ANALYSIS ---
  Future<void> _runAnalysis() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insira a API Key do Google Gemini!')),
      );
      return;
    }
    await _saveSettings();

    if (_currentAudioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum áudio para analisar.')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusText = "Enviando para o Dr. House (IA)...";
      _statusColor = Colors.orange;
    });

    try {
      // 1. Read Audio
      final file = File(_currentAudioPath!);
      final bytes = await file.readAsBytes();
      
      // 2. Init Gemini
      final model = GenerativeModel(
        model: 'gemini-2.0-flash', // Using newer fast model
        apiKey: apiKey,
      );

      final prompt = Content.text('''
        Você é um assistente médico sênior e cínico (Dr. House).
        Analise o áudio e gere um JSON VÁLIDO.
        
        Regras:
        1. Responda APENAS o JSON.
        2. Se faltar info crítica (alergias, historico), adicione "[CRITICA CÍNICA]: <texto>" ao final do valor do campo.
        
        Estrutura Obrigatória:
        {
          "soap": { "s": "...", "o": "...", "a": "...", "p": "..." },
          "medicamentos": ["..."],
          "sugestoes": { "s": ["..."], "o": ["..."], "a": ["..."], "p": ["..."] }
        }
      ''');

      final audioPart = DataPart('audio/mp4', bytes); // m4a is typically mp4 container
      
      final response = await model.generateContent([
        Content.multi([prompt.parts.first, audioPart])
      ]);

      final text = response.text;
      if (text == null) throw "Sem resposta da IA";

      // 3. Clean Json
      String jsonStr = text.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = json.decode(jsonStr);

      // 4. Meds Audit
      final medsProcessed = _auditMeds(List<String>.from(data['medicamentos'] ?? []));
      data['audit'] = medsProcessed;

      setState(() {
        _analysisResult = data;
        _statusText = "Análise Concluída.";
        _statusColor = Colors.blue;
      });

    } catch (e) {
      setState(() {
        _statusText = "Erro: $e";
        _statusColor = Colors.red;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Meds Audit Logic
  Map<String, dynamic> _auditMeds(List<String> meds) {
    List<Map<String, dynamic>> items = [];
    int remumeCount = 0;
    int renameCount = 0;

    for (var med in meds) {
      final medNorm = removeDiacritics(med.toLowerCase());
      
      Map<String, dynamic> check(List<dynamic> db) {
        for (var item in db) {
          String name = "";
          if (item is Map) {
             name = item['nome'] ?? item['nome_completo'] ?? "";
          } else {
             name = item.toString();
          }
          final nameNorm = removeDiacritics(name.toLowerCase());
          
          if (medNorm.contains(nameNorm) || nameNorm.contains(medNorm)) {
            return {"found": true, "match": name};
          }
        }
        return {"found": false, "match": null};
      }

      final rRemume = check(_dbRemume);
      final rRename = check(_dbRename);
      final rAlto = check(_dbAltoCusto);

      if (rRemume['found']) remumeCount++;
      if (rRename['found']) renameCount++;

      items.add({
        "ia_term": med,
        "remume": rRemume,
        "rename": rRename,
        "alto_custo": rAlto
      });
    }

    return {
      "items": items,
      "meta": {"count_remume": remumeCount, "count_rename": renameCount}
    };
  }

  // --- PDF GENERATION ---
  Future<void> _generatePdf() async {
    if (_analysisResult == null) return;
    
    final pdf = pw.Document();
    final data = _analysisResult!;
    final soap = data['soap'] ?? {};
    final audit = data['audit']['items'] as List;

    final fontBase = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Center(child: pw.Text("MEDUBS - Relatório Clínico", style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.blue800)))
            ),
            pw.Paragraph(text: "Gerado em: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
            
            // SOAP SECTIONS
            ..._buildPdfSection("Subjetivo", soap['s'] ?? "", fontBold, fontBase),
            ..._buildPdfSection("Objetivo", soap['o'] ?? "", fontBold, fontBase),
            ..._buildPdfSection("Avaliação", soap['a'] ?? "", fontBold, fontBase),
            ..._buildPdfSection("Plano", soap['p'] ?? "", fontBold, fontBase),

            pw.Divider(),
            pw.Text("Prescrição & Auditoria", style: pw.TextStyle(font: fontBold, fontSize: 14)),
            pw.SizedBox(height: 10),
            
            ...audit.map((item) {
              final name = item['ia_term'].toString().toUpperCase();
              List<String> tags = [];
              if (item['remume']['found']) tags.add("REMUME");
              if (item['rename']['found']) tags.add("RENAME");
              if (item['alto_custo']['found']) tags.add("ALTO CUSTO");
              if (tags.isEmpty) tags.add("NÃO CONSTA");

              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                     pw.Text(name, style: pw.TextStyle(font: fontBold)),
                     pw.Text(tags.join(" | "), style: pw.TextStyle(font: fontBase, fontSize: 10, color: PdfColors.blue)),
                  ]
                )
              );
            }).toList(),
          ];
        }
      )
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Relatorio_MedUBS.pdf');
  }

  List<pw.Widget> _buildPdfSection(String title, String content, pw.Font bold, pw.Font base) {
    if (content.isEmpty || content == "-") return [];
    
    // Clean critique from PDF
    final cleanContent = content.split("[CRITICA CÍNICA]:")[0];

    return [
      pw.Container(
        color: PdfColors.grey200,
        padding: const pw.EdgeInsets.all(5),
        width: double.infinity,
        child: pw.Text(title, style: pw.TextStyle(font: bold))
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Text(cleanContent, style: pw.TextStyle(font: base))
      ),
      pw.SizedBox(height: 10),
    ];
  }


  // --- UI START ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MedUBS', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('IA Clínica Inteligente', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettings(context),
          )
        ],
      ),
      body: Column(
        children: [
          // Status Bar
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                Icon(Icons.circle, size: 12, color: _statusColor),
                const SizedBox(width: 8),
                Expanded(child: Text(_statusText, style: const TextStyle(fontWeight: FontWeight.w500))),
              ],
            ),
          ),
          
          // Main Content
          Expanded(
            child: _analysisResult == null
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.medical_services_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text("Pressione GRAVAR para iniciar", style: TextStyle(color: Colors.grey[500]))
                    ],
                  )
                ) 
                : _buildResultsList(),
          ),

          // Controls
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))]
            ),
            child: Column(
              children: [
                 if (_analysisResult != null)
                   SizedBox(
                     width: double.infinity,
                     child: ElevatedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text("GERAR PDF"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[50],
                          foregroundColor: Colors.blue[800],
                        ),
                        onPressed: _generatePdf,
                     ),
                   ),
                 const SizedBox(height: 16),
                 Row(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                      // Record Button
                      GestureDetector(
                        onTap: _isProcessing ? null : _toggleRecording,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 72,
                          width: 72,
                          decoration: BoxDecoration(
                            color: _isRecording ? Colors.red : const Color(0xFF0052CC),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: (_isRecording ? Colors.red : const Color(0xFF0052CC)).withOpacity(0.4), blurRadius: 12, spreadRadius: 2)]
                          ),
                          child: Icon(
                            _isRecording ? Icons.stop : Icons.mic,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 24),
                      
                      // Analyze Button (Visible only if audio exists and not recording)
                      if (_currentAudioPath != null && !_isRecording && !_isProcessing)
                        ElevatedButton.icon(
                          onPressed: _runAnalysis,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text("ANALISAR"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          ),
                        )
                   ],
                 )
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- SETTINGS DIALOG ---
  void _showSettings(BuildContext context) {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Configurações"),
        content: TextField(
          controller: _apiKeyController,
          decoration: const InputDecoration(labelText: "Gemini API Key", border: OutlineInputBorder()),
          obscureText: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Salvar"))
        ],
      )
    );
  }

  // --- RESULT WIDGETS ---
  Widget _buildResultsList() {
    final soap = _analysisResult!['soap'] as Map;
    final audit = _analysisResult!['audit']['items'] as List;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSoapCard("Subjetivo", soap['s'] ?? "", Icons.person, Colors.blue),
        _buildSoapCard("Objetivo", soap['o'] ?? "", Icons.monitor_heart, Colors.green),
        _buildSoapCard("Avaliação", soap['a'] ?? "", Icons.analytics, Colors.orange),
        _buildSoapCard("Plano", soap['p'] ?? "", Icons.medical_services, const Color(0xFF8E24AA)), // Roxo
        
        const SizedBox(height: 24),
        const Text("Prescrição & Auditoria", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Divider(),
        ...audit.map((item) => _buildMedCard(item)),
      ],
    );
  }

  Widget _buildSoapCard(String title, String content, IconData icon, Color color) {
    // Parse Critique
    final parts = content.split("[CRITICA CÍNICA]:");
    final mainText = parts[0];
    final critiqueText = parts.length > 1 ? parts[1].trim() : null;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.5), width: 1)
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color), 
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color))
            ]),
            const Divider(),
            Text(mainText, style: const TextStyle(fontSize: 14, height: 1.4)),
            
            if (critiqueText != null) 
              Container(
                margin: const EdgeInsets.top(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[100]!)
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
                      SizedBox(width: 4),
                      Text("CRÍTICA DA IA", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12))
                    ]),
                    const SizedBox(height: 4),
                    Text(critiqueText, style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic, fontSize: 13))
                  ],
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildMedCard(Map item) {
    final name = item['ia_term'].toString();
    List<Widget> tags = [];
    
    Widget makeTag(String text, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
    );

    if (item['remume']['found']) tags.add(makeTag("REMUME", Colors.green));
    if (item['rename']['found']) tags.add(makeTag("RENAME", Colors.blue));
    if (item['alto_custo']['found']) tags.add(makeTag("ALTO CUSTO", Colors.orange));
    if (tags.isEmpty) tags.add(makeTag("NÃO CONSTA", Colors.red));

    return Card(
      child: ListTile(
        title: Text(name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Wrap(spacing: 4, children: tags),
        trailing: const Icon(Icons.check_circle_outline, color: Colors.grey),
      ),
    );
  }
}
