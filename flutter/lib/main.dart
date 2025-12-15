import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:record/record.dart'; // v4.4.4
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
  runApp(const MedUBSApp());
}

class MedUBSApp extends StatelessWidget {
  const MedUBSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedUBS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1), // Blue 900
          secondary: const Color(0xFF00BFA5), // Teal Accent
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          elevation: 4,
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
  // State
  final _apiKeyController = TextEditingController();
  final _audioRecorder = Record(); // v4 Class
  
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
        
        // v4 Syntax
        await _audioRecorder.start(
          path: path,
          encoder: AudioEncoder.aacLc,
        );
        
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
    if (!mounted) return;

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
      final file = File(_currentAudioPath!);
      final bytes = await file.readAsBytes();

      final model = GenerativeModel(
        model: 'gemini-1.5-flash', // Fallback to 1.5 if 2.0 is risky, but let's try 1.5 for stability
        apiKey: apiKey,
        safetySettings: [
          SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
          SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
          SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
          SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
        ]
      );

      final prompt = TextPart('''
      Você é um assistente médico especialista (Dr. MedUBS).
      Sua tarefa é ouvir o áudio da consulta e gerar um JSON estruturado.
      
      IMPORTANTE:
      1. Identifique a estrutura SOAP (Subjetivo, Objetivo, Avaliação, Plano).
      2. Cruze os medicamentos citados com os bancos de dados fornecidos (REMUME, RENAME, ALTO CUSTO).
      3. CRÍTICA: Identifique o que faltou perguntar (ex: alergias, histórico familiar).
      
      BANCOS DE DADOS (Referência):
      REMUME: $_dbRemume
      RENAME: $_dbRename
      ALTO CUSTO: $_dbAltoCusto
      
      FORMATO DE RESPOSTA (JSON PURO):
      {
        "soap": {
          "s": "...",
          "o": "...",
          "a": "...",
          "p": "..."
        },
        "audit": {
          "items": [
             {"name": "Amoxicilina", "status": "REMUME", "obs": "Disponível na UBS"}
          ]
        },
        "critique": [
           "Faltou perguntar sobre alergia a penicilina.",
           "Não verificou pressão arterial."
        ]
      }
      ''');

      final content = [
        Content.multi([prompt, DataPart('audio/mp4', bytes)]) // m4a is mp4 container
      ];

      final response = await model.generateContent(content);
      
      if (response.text == null) throw Exception("Resposta vazia da IA");

      // Extract JSON from markdown code block if present
      String jsonString = response.text!;
      if (jsonString.contains('```json')) {
        jsonString = jsonString.split('```json')[1].split('```')[0];
      } else if (jsonString.contains('```')) {
        jsonString = jsonString.split('```')[1].split('```')[0];
      }

      final data = json.decode(jsonString);

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
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // --- LOGIC: PDF ---
  Future<void> _generatePdf() async {
    if (_analysisResult == null) return;
    
    final pdf = pw.Document();
    final soap = _analysisResult!['soap'] as Map;
    final audit = _analysisResult!['audit']['items'] as List;
    final critique = _analysisResult!['critique'] as List;

    final image = await imageFromAssetBundle('assets/icon.png'); // Ensure you have an icon

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Relatório Clínico - MedUBS', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Image(image, width: 40),
                ],
              ),
            ),
            pw.Divider(),
            pw.SizedBox(height: 10),
            
            _buildPdfSection('Subjetivo', soap['s']),
            _buildPdfSection('Objetivo', soap['o']),
            _buildPdfSection('Avaliação', soap['a']),
            _buildPdfSection('Plano', soap['p']),
            
            pw.SizedBox(height: 20),
            pw.Text('Auditoria de Medicamentos', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Table.fromTextArray(
              headers: ['Medicamento', 'Status', 'Obs'],
              data: audit.map((e) => [e['name'], e['status'], e['obs'] ?? '']).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            
            pw.SizedBox(height: 20),
            pw.Text('Crítica da IA (Pontos de Atenção)', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
            ...critique.map((e) => pw.Bullet(text: e.toString())),
            
            pw.Footer(
              leading: pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
              trailing: pw.Text('Gerado por MedUBS AI'),
            ),
          ];
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Relatorio_MedUBS.pdf');
  }

  pw.Widget _buildPdfSection(String title, String content) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.Text(content, style: const pw.TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // --- UI HELPER ---
  String check(dynamic list) {
    if (list is List) return "Carregado (${list.length} itens)";
    return "Erro";
  }

  @override
  Widget build(BuildContext context) {
    final rRemume = check(_dbRemume);
    final rRename = check(_dbRename);
    final rAlto = check(_dbAltoCusto);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MedUBS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showDialog(context: context, builder: (context) => AlertDialog(
                title: const Text('Configurações'),
                content: TextField(
                  controller: _apiKeyController,
                  decoration: const InputDecoration(labelText: 'Gemini API Key'),
                  obscureText: true,
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
              ));
            },
          )
        ],
      ),
      body: Container(
        color: Colors.grey[100],
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Status Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 12, color: _statusColor),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_statusText, style: const TextStyle(fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            
            // Database Status (Debug)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text("REMUME: $rRemume", style: const TextStyle(fontSize: 10)),
                Text("RENAME: $rRename", style: const TextStyle(fontSize: 10)),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Big Button
            SizedBox(
              width: double.infinity,
              height: 120,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.red : const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isProcessing ? null : _toggleRecording,
                icon: Icon(_isRecording ? Icons.stop : Icons.mic, size: 40),
                label: Text(_isRecording ? "PARAR GRAVAÇÃO" : "INICIAR CONSULTA", style: const TextStyle(fontSize: 18)),
              ),
            ),
            
            const SizedBox(height: 10),
            
            if (_currentAudioPath != null && !_isRecording && !_isProcessing)
              ElevatedButton.icon(
                onPressed: _runAnalysis,
                icon: const Icon(Icons.psychology),
                label: const Text("ANALISAR AGORA"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[800],
                  foregroundColor: Colors.white,
                ),
              ),

            // Results Area
            Expanded(
              child: _analysisResult == null 
              ? Center(child: Icon(Icons.medical_services_outlined, size: 64, color: Colors.grey[300]))
              : ListView(
                  children: [
                    const Divider(),
                    if (_analysisResult!['critique'] != null)
                      _buildCritiqueCard(_analysisResult!['critique']),
                    
                    _buildSection("Subjetivo", _analysisResult!['soap']['s'], Icons.person),
                    _buildSection("Objetivo", _analysisResult!['soap']['o'], Icons.visibility),
                    _buildSection("Avaliação", _analysisResult!['soap']['a'], Icons.analytics),
                    _buildSection("Plano", _analysisResult!['soap']['p'], Icons.assignment_turned_in),
                    
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _generatePdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text("GERAR PDF / IMPRIMIR"),
                    )
                  ],
                ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content, IconData icon) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0D47A1)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(content),
      ),
    );
  }

  Widget _buildCritiqueCard(List<dynamic> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warning_amber, color: Colors.red[900]),
              const SizedBox(width: 8),
              Text("CRÍTICA DA IA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[900])),
            ]),
            const SizedBox(height: 8),
            ...items.map((e) => Text("• $e", style: TextStyle(color: Colors.red[900]))),
          ],
        ),
      ),
    );
  }
}
