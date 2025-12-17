import 'package:flutter/material.dart';
import '../database/database_helper.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<Map<String, dynamic>> _meds = [];
  bool _loading = true;
  String _search = "";

  @override
  void initState() {
    super.initState();
    _loadMeds();
  }

  Future<void> _loadMeds() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper().database;
    // Pega todos. Em produção com 10k itens, usar paginação.
    final List<Map<String, dynamic>> res = await db.query('medicamentos', orderBy: 'nome ASC');
    
    if (mounted) {
      setState(() {
        _meds = res;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter
    final filtered = _meds.where((m) {
      final t = _search.toLowerCase();
      final nome = (m['nome'] as String?)?.toLowerCase() ?? "";
      final conc = (m['concentracao'] as String?)?.toLowerCase() ?? "";
      return nome.contains(t) || conc.contains(t);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Estoque de Medicamentos"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
               decoration: const InputDecoration(
                 hintText: "Filtrar (Ex: Dipirona)", 
                 prefixIcon: Icon(Icons.search),
                 filled: true,
                 fillColor: Colors.white,
                 border: OutlineInputBorder()
               ),
               onChanged: (v) => setState(() => _search = v),
            ),
          )
        )
      ),
      body: _loading 
         ? const Center(child: CircularProgressIndicator()) 
         : filtered.isEmpty 
             ? const Center(child: Text("Nenhum medicamento encontrado."))
             : ListView.builder(
                 itemCount: filtered.length,
                 itemBuilder: (ctx, i) {
                   final m = filtered[i];
                   return Card(
                     margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                     child: ExpansionTile(
                       leading: CircleAvatar(
                         backgroundColor: _getColor(m),
                         child: const Icon(Icons.medication, color: Colors.white, size: 18)
                       ),
                       title: Text(m['nome'] ?? "Desconhecido", style: const TextStyle(fontWeight: FontWeight.bold)),
                       subtitle: Text("${m['concentracao'] ?? ''} - ${m['forma'] ?? ''}"),
                       children: [
                         Padding(
                           padding: const EdgeInsets.all(16),
                           child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                             Row(children: [
                               const Icon(Icons.description, size: 16, color: Colors.grey),
                               const SizedBox(width: 8),
                               Expanded(child: Text("Origem: ${m['lista_origem'] ?? 'Manual'}", style: const TextStyle(fontSize: 12)))
                             ]),
                             const SizedBox(height: 10),
                             Wrap(spacing: 8, children: _buildBadges(m))
                           ]),
                         )
                       ],
                     ),
                   );
                 }
               ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadMeds,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  List<Widget> _buildBadges(Map m) {
    List<Widget> badges = [];
    String origem = (m['lista_origem'] ?? "").toString().toLowerCase();
    
    // Check flags or infer from origin
    bool isRemume = (m['disp_remume'] == 1) || origem.contains('remume');
    bool isRename = (m['disp_rename'] == 1) || origem.contains('rename');
    bool isEstadual = (m['disp_estadual'] == 1) || origem.contains('estadual');
    bool isAltoCusto = (m['alto_custo'] == 1) || origem.contains('alto') || origem.contains('custo');

    if (isRemume) badges.add(const _Badge("REMUME", Colors.green));
    if (isRename) badges.add(const _Badge("RENAME", Colors.blue));
    if (isEstadual) badges.add(const _Badge("ESTADUAL", Colors.orange));
    if (isAltoCusto) badges.add(const _Badge("ALTO CUSTO", Colors.red));
    
    return badges;
  }

  Color _getColor(Map m) {
    String origem = (m['lista_origem'] ?? "").toString().toLowerCase();
    if((m['disp_remume'] == 1) || origem.contains('remume')) return Colors.green;
    if((m['disp_rename'] == 1) || origem.contains('rename')) return Colors.blue;
    if(origem.contains('estadual')) return Colors.orange;
    if(origem.contains('alto') || origem.contains('custo')) return Colors.red;
    return Colors.grey;
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
  @override 
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
