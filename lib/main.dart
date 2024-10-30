import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

void main() {
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
  String searchQuery = '';
  final Dio dio = Dio();
  Map<String, double> downloadProgress = {};

  final String bucketUrl = "https://firebasestorage.googleapis.com/v0/b/safeviewbd.appspot.com/o";

  Future<void> fetchItems() async {
    print('Fetching items from: $bucketUrl');
    final response = await http.get(Uri.parse(bucketUrl));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<Map<String, dynamic>> fetchedItems = List<Map<String, dynamic>>.from(
        data['items'].map((item) => {
          'name': item['name'],
          'downloadUrl': '${bucketUrl}/${Uri.encodeComponent(item['name'])}?alt=media',
        }),
      );

      setState(() {
        items = fetchedItems;
        filteredItems = fetchedItems;
        isListVisible = true;
      });

      print('Items fetched successfully: ${fetchedItems.length} items');
    } else {
      print('Error fetching items: ${response.statusCode}');
    }
  }

  Future<void> downloadFile(String url, String fileName) async {
    print('Attempting to download file: $fileName from URL: $url');
    try {
      dio.options.responseType = ResponseType.bytes;
      dio.options.headers = {
        'Accept': 'application/pdf',
      };

      // Determina o diretório de downloads de acordo com o sistema operacional
      final downloadsPath = Platform.isWindows
          ? path.join(Platform.environment['USERPROFILE']!, 'Downloads')
          : path.join(Platform.environment['HOME']!, 'Downloads');

      String finalFileName = fileName;
      if (!finalFileName.toLowerCase().endsWith('.pdf')) {
        finalFileName += '.pdf';
      }

      final savePath = path.join(downloadsPath, finalFileName);
      print('Saving file to: $savePath');

      // Cria o diretório se ele não existir
      final fileDir = Directory(downloadsPath);
      if (!fileDir.existsSync()) {
        fileDir.createSync(recursive: true);
      }

      if (await File(savePath).exists()) {
        print('File already exists: $savePath');
        final shouldOverwrite = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Arquivo já existe'),
            content: Text('O arquivo "$finalFileName" já existe. Deseja sobrescrever?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Sobrescrever'),
              ),
            ],
          ),
        );

        if (shouldOverwrite != true) {
          print('User chose not to overwrite the file');
          return;
        }
      }

      setState(() {
        downloadProgress[fileName] = 0;
      });

      final response = await dio.get(
        url,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              downloadProgress[fileName] = (received / total * 100);
            });
          }
        },
      );

      if (response.data == null || response.data.isEmpty) {
        throw Exception('Arquivo vazio ou inválido');
      }

      final file = File(savePath);
      await file.writeAsBytes(response.data);

      setState(() {
        downloadProgress.remove(fileName);
      });

      print('Download completed: $finalFileName saved at $savePath');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Download concluído'),
                    Text(
                      'Salvo em: $savePath',
                      style: TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () async {
                  final directory = File(savePath).parent;
                  // Usa 'explorer' no Windows e 'xdg-open' no Linux
                  if (Platform.isWindows) {
                    await Process.run('explorer', [directory.path]);
                  } else if (Platform.isLinux) {
                    await Process.run('xdg-open', [directory.path]);
                  }
                },
                child: Text('ABRIR PASTA', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        downloadProgress.remove(fileName);
      });

      print('Error downloading file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao fazer download: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
    print('Filtered items with query: $query, found: ${filteredItems.length}');
  }

  void toggleListVisibility() {
    if (isListVisible) {
      setState(() {
        isListVisible = false;
        filteredItems = [];
      });
      print('List is now hidden');
    } else {
      fetchItems();
      print('List is now visible');
    }
  }

  Widget buildDownloadButton(Map<String, dynamic> item) {
    final fileName = item['name'];
    final progress = downloadProgress[fileName];

    if (progress != null) {
      return Container(
        width: 50,
        height: 50,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress / 100,
              backgroundColor: Colors.grey[800],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              strokeWidth: 3,
            ),
            Text(
              '${progress.toInt()}%',
              style: TextStyle(fontSize: 10),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.download, color: Colors.blue),
          onPressed: () => downloadFile(
            item['downloadUrl'],
            fileName,
          ),
          tooltip: 'Download arquivo',
        ),
      ],
    );
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
                            title: Text(
                              item['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.blue,
                              ),
                            ),
                            trailing: buildDownloadButton(item),
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
}
