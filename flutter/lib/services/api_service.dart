import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 'http://10.0.2.2:8000' se estiver usando emulador Android
  // Use 'http://127.0.0.1:8000' para web ou windows
  static String baseUrl = 'https://medubs-backend.onrender.com'; // Produção Render

  static Future<List<dynamic>> uploadMedicamento(File pdfFile, String nomeLista, String apiKey, String model) async {
    var uri = Uri.parse('$baseUrl/upload-medicamento');
    var request = http.MultipartRequest('POST', uri);
    
    request.fields['nome_lista'] = nomeLista;
    request.fields['api_key'] = apiKey;
    request.fields['model'] = model; // <--- Envia o modelo
    request.files.add(await http.MultipartFile.fromPath('file', pdfFile.path));

    try {
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        var decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is List) return decoded;
        if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
        return [];
      } else {
        throw Exception('Falha no upload: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Erro de conexão: $e');
    }
  }

  static Future<bool> uploadDiretriz(File pdfFile, String apiKey) async {
    var uri = Uri.parse('$baseUrl/upload-diretriz');
    var request = http.MultipartRequest('POST', uri);
    
    request.fields['api_key'] = apiKey;
    request.files.add(await http.MultipartFile.fromPath('file', pdfFile.path));

    try {
      var streamedResponse = await request.send();
      if (streamedResponse.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      throw Exception('Erro de conexão: $e');
    }
  }

  static Future<Map<String, dynamic>> consultarIA(String transcricao, String apiKey, {String model = 'gemini-1.5-flash'}) async {
    var uri = Uri.parse('$baseUrl/consultar-ia');
    
    try {
      var response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'transcricao': transcricao,
          'api_key': apiKey,
          'model': model,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('Falha na IA: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Erro de conexão: $e');
    }
  }
}
