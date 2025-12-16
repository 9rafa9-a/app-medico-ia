import 'package:flutter/material.dart';
import '../database/database_helper.dart';

class MissionWidget extends StatefulWidget {
  final List<dynamic> missoesIniciais;
  final String consultaId;

  const MissionWidget({
    Key? key,
    required this.missoesIniciais,
    required this.consultaId,
  }) : super(key: key);

  @override
  State<MissionWidget> createState() => _MissionWidgetState();
}

class _MissionWidgetState extends State<MissionWidget> {
  List<Map<String, dynamic>> _tarefas = [];
  bool _isExpanded = true;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _inicializarMissoes();
  }

  Future<void> _inicializarMissoes() async {
    // Mescla missões iniciais com o que pode já estar no banco para esta consulta
    // Por simplificação do MVP, vamos assumir que as iniciais são novas
    // e apenas convertê-las para o formato local com status
    
    List<Map<String, dynamic>> temp = [];
    
    for (var m in widget.missoesIniciais) {
      // Tenta salvar no banco para ter persistência e ID
      Map<String, dynamic> nova = {
        'consulta_id': widget.consultaId,
        'doenca': m['doenca'] ?? 'Geral',
        'tarefa': m['tarefa'],
        'categoria': m['categoria'] ?? 'Geral',
        'concluido': 0
      };
      
      int id = await DatabaseHelper().adicionarMissao(nova);
      nova['id'] = id;
      nova['concluido'] = false; // logicamente para UI
      temp.add(nova);
    }

    if (mounted) {
      setState(() {
        _tarefas = temp;
        _calcularProgresso();
      });
    }
  }

  void _calcularProgresso() {
    if (_tarefas.isEmpty) {
      _progress = 0;
      return;
    }
    int done = _tarefas.where((t) => t['concluido'] == true || t['concluido'] == 1).length;
    _progress = done / _tarefas.length;
  }

  Future<void> _toggleTask(int index, bool? val) async {
    setState(() {
      _tarefas[index]['concluido'] = val == true;
      _calcularProgresso();
    });
    
    int id = _tarefas[index]['id'];
    await DatabaseHelper().marcarMissao(id, val == true);
  }

  @override
  Widget build(BuildContext context) {
    if (_tarefas.isEmpty) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            leading: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.orange[100],
                  color: Colors.orange[800],
                  strokeWidth: 3,
                ),
                Text(
                  "${(_progress * 100).toInt()}%",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange[900]),
                ),
              ],
            ),
            title: Text(
              "Protocolos Ativos (${_tarefas.length})",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[900]),
            ),
            subtitle: Text(
              _isExpanded ? "Toque para recolher" : "Toque par ver tarefas",
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Icon(
              _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.orange[900],
            ),
          ),
          if (_isExpanded)
            Column(
              children: _tarefas.asMap().entries.map((entry) {
                int idx = entry.key;
                Map task = entry.value;
                bool isDone = task['concluido'] == true || task['concluido'] == 1;

                return CheckboxListTile(
                  value: isDone,
                  onChanged: (val) => _toggleTask(idx, val),
                  title: Text(
                    task['tarefa'],
                    style: TextStyle(
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      color: isDone ? Colors.grey : Colors.black87,
                    ),
                  ),
                  subtitle: Text("${task['categoria']} • ${task['doenca']}", style: const TextStyle(fontSize: 11)),
                  activeColor: Colors.orange,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                );
              }).toList(),
            )
        ],
      ),
    );
  }
}
