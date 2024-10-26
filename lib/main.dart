import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pdfx/pdfx.dart';

void main() async {
  await dotenv.load(fileName: "/home/ideal_pad/Documentos/Projetos/teste_flutter/flutter_application_1/.env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: StorageListPage(),
    );
  }
}

class StorageListPage extends StatefulWidget {
  @override
  _StorageListPageState createState() => _StorageListPageState();
}

class _StorageListPageState extends State<StorageListPage> {
  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> filteredItems = [];
  bool isListVisible = false;
  bool isDownloading = false;
  String searchQuery = '';

  final String bucketUrl = dotenv.env['BUCKET_URL'] ?? '';

  Future<void> fetchItems() async {
    final response = await http.get(Uri.parse(bucketUrl));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<Map<String, dynamic>> fetchedItems = List<Map<String, dynamic>>.from(
        data['items'].map((item) => {
          'name': item['name'],
          'downloadUrl': '$bucketUrl/${Uri.encodeComponent(item['name'])}?alt=media',
        }),
      );

      setState(() {
        items = fetchedItems;
        filteredItems = fetchedItems;
        isListVisible = true;
      });
    } else {
      print('Erro ao buscar itens: ${response.statusCode}');
    }
  }

  Future<void> downloadFile(String url, String fileName) async {
    setState(() => isDownloading = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arquivo $fileName baixado com sucesso!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao baixar o arquivo')),
        );
      }
    } catch (e) {
      print('Erro ao baixar arquivo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao baixar o arquivo')),
      );
    } finally {
      setState(() => isDownloading = false);
    }
  }

  void filterItems(String query) {
    setState(() {
      searchQuery = query;
      filteredItems = items
          .where((item) =>
              item['name'].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  void toggleListVisibility() {
    if (isListVisible) {
      setState(() {
        isListVisible = false;
        filteredItems = [];
      });
    } else {
      fetchItems();
    }
  }

  void openFileContent(String downloadUrl, String fileName) async {
    final response = await http.get(Uri.parse(downloadUrl));
    if (response.statusCode == 200) {
      final fileData = response.bodyBytes;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FileContentScreen(fileName: fileName, fileData: fileData),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar conteúdo do arquivo')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.storage, color: Colors.white),
            SizedBox(width: 8),
            Text('Itens do Bucket Firebase'),
          ],
        ),
      ),
      body: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(
              onChanged: filterItems,
              decoration: InputDecoration(
                labelText: 'Pesquisar',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              style: TextStyle(color: Colors.black),
            ),
            SizedBox(height: 12),
            ElevatedButton(
              onPressed: toggleListVisibility,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                elevation: 2,
              ),
              child: Text(isListVisible ? 'Ocultar Itens do Bucket' : 'Mostrar Itens do Bucket'),
            ),
            SizedBox(height: 12),
            Expanded(
              child: isListVisible
                  ? ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return Card(
                          elevation: 4,
                          margin: EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            leading: getFileIcon(item['name']),
                            title: GestureDetector(
                              onTap: () => openFileContent(item['downloadUrl'], item['name']),
                              child: Text(
                                item['name'],
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            trailing: isDownloading
                                ? CircularProgressIndicator()
                                : TextButton(
                                    onPressed: () => downloadFile(item['downloadUrl'], item['name']),
                                    child: Text('Download'),
                                  ),
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Text(
                        'Pressione "Mostrar" para exibir os itens',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Icon getFileIcon(String fileName) {
    if (fileName.toLowerCase().endsWith('.pdf')) {
      return Icon(Icons.picture_as_pdf, color: Colors.red);
    } else if (fileName.toLowerCase().endsWith('.jpg') ||
               fileName.toLowerCase().endsWith('.jpeg') ||
               fileName.toLowerCase().endsWith('.png') ||
               fileName.toLowerCase().endsWith('.gif')) {
      return Icon(Icons.image, color: Colors.blue);
    } else {
      return Icon(Icons.insert_drive_file, color: Colors.grey);
    }
  }
}

class FileContentScreen extends StatelessWidget {
  final String fileName;
  final List<int> fileData;

  FileContentScreen({required this.fileName, required this.fileData});

  bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    bool isImage = fileName.toLowerCase().endsWith('.jpg') ||
                   fileName.toLowerCase().endsWith('.jpeg') ||
                   fileName.toLowerCase().endsWith('.png') ||
                   fileName.toLowerCase().endsWith('.gif');

    bool isText = fileName.toLowerCase().endsWith('.txt');
    bool isPdf = fileName.toLowerCase().endsWith('.pdf');

    return Scaffold(
      appBar: AppBar(title: Text(fileName)),
      body: Center(
        child: isImage
            ? Image.memory(Uint8List.fromList(fileData))
            : isText
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: Text(
                        utf8.decode(fileData),
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  )
                : isPdf && isSupportedPlatform
                    ? PdfViewPinch(
                        controller: PdfControllerPinch(
                          document: PdfDocument.openData(fileData as FutureOr<Uint8List>),
                        ),
                      )
                    : Text(
                        isPdf ? 'Visualização de PDF não suportada neste dispositivo' : 'Formato de arquivo não suportado',
                        style: TextStyle(color: Colors.white),
                      ),
      ),
    );
  }
}
