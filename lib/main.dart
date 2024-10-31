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
  bool isListVisible = false;
  final Dio dio = Dio();

  final String bucketUrl = "https://firebasestorage.googleapis.com/v0/b/safeviewbd.appspot.com/o";

  Future<void> fetchItems() async {
    print('Fetching folders from: $bucketUrl');
    final response = await http.get(Uri.parse('$bucketUrl?prefix='));

    if (response.statusCode == 200) {
      final List<Map<String, dynamic>> fetchedItems = [
        {'name': 'Faces'},
        {'name': 'Reports'},
      ];

      setState(() {
        items = fetchedItems;
        isListVisible = true;
      });

      print('Folders fetched successfully: ${fetchedItems.length} folders');
    } else {
      print('Error fetching folders: ${response.statusCode}');
    }
  }

  void toggleListVisibility() {
    if (isListVisible) {
      setState(() {
        isListVisible = false;
      });
      print('List is now hidden');
    } else {
      fetchItems();
      print('List is now visible');
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
            Text('Pastas no Bucket Firebase'),
          ],
        ),
      ),
      body: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: toggleListVisibility,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                elevation: 2,
              ),
              child: Text(isListVisible ? 'Ocultar Pastas do Bucket' : 'Mostrar Pastas do Bucket'),
            ),
            SizedBox(height: 12),
            Expanded(
              child: isListVisible
                  ? ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final folder = items[index]['name'];
                        return Card(
                          elevation: 4,
                          margin: EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            title: Text(
                              folder,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.blue,
                              ),
                            ),
                            trailing: Icon(Icons.folder, color: Colors.blue),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FolderContentsPage(folder: folder),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Text(
                        'Pressione "Mostrar" para exibir as pastas',
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

class FolderContentsPage extends StatefulWidget {
  final String folder;

  FolderContentsPage({required this.folder});

  @override
  _FolderContentsPageState createState() => _FolderContentsPageState();
}

class _FolderContentsPageState extends State<FolderContentsPage> {
  List<Map<String, dynamic>> folderItems = [];
  List<Map<String, dynamic>> filteredFolderItems = [];
  String searchQuery = '';
  final Dio dio = Dio();
  Map<String, double> downloadProgress = {};

  final String bucketUrl = "https://firebasestorage.googleapis.com/v0/b/safeviewbd.appspot.com/o";

  @override
  void initState() {
    super.initState();
    fetchFolderContents();
  }

  Future<void> fetchFolderContents() async {
    final folderUrl = "$bucketUrl?prefix=${widget.folder}/";
    final response = await http.get(Uri.parse(folderUrl));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<Map<String, dynamic>> fetchedItems = List<Map<String, dynamic>>.from(
        data['items'].map((item) => {
          'name': item['name'].replaceFirst('${widget.folder}/', ''),
          'downloadUrl': '${bucketUrl}/${Uri.encodeComponent(item['name'])}?alt=media',
        }),
      );

      setState(() {
        folderItems = fetchedItems;
        filteredFolderItems = fetchedItems;
      });
    } else {
      print('Error fetching folder contents: ${response.statusCode}');
    }
  }

  void filterItems(String query) {
    setState(() {
      searchQuery = query;
      filteredFolderItems = folderItems
          .where((item) =>
              item['name'].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
    print('Filtered items with query: $query, found: ${filteredFolderItems.length}');
  }

  Future<void> deleteFile(String fileName) async {
    print('Attempting to delete file: $fileName');
    try {
      final fileUrl = "$bucketUrl/${Uri.encodeComponent('${widget.folder}/$fileName')}";
      final response = await dio.delete(fileUrl);

      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() {
          folderItems.removeWhere((item) => item['name'] == fileName);
          filteredFolderItems.removeWhere((item) => item['name'] == fileName);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File "$fileName" deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Failed to delete file');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> downloadFile(String url, String fileName) async {
    print('Attempting to download file: $fileName from URL: $url');
    try {
      dio.options.responseType = ResponseType.bytes;
      dio.options.headers = {
        'Accept': 'application/pdf',
      };

      final downloadsPath = Platform.isWindows
          ? path.join(Platform.environment['USERPROFILE']!, 'Downloads')
          : path.join(Platform.environment['HOME']!, 'Downloads');

      String finalFileName = fileName;
      
      final savePath = path.join(downloadsPath, finalFileName);
      print('Saving file to: $savePath');

      final fileDir = Directory(downloadsPath);
      if (!fileDir.existsSync()) {
        fileDir.createSync(recursive: true);
      }

      if (await File(savePath).exists()) {
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao fazer download: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
          onPressed: () => downloadFile(item['downloadUrl'], fileName),
          tooltip: 'Download arquivo',
        ),
        IconButton(
          icon: Icon(Icons.delete, color: Colors.red),
          onPressed: () => deleteFile(fileName),
          tooltip: 'Delete arquivo',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Conteúdo de ${widget.folder}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
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
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredFolderItems.length,
              itemBuilder: (context, index) {
                final item = filteredFolderItems[index];
                return ListTile(
                  title: Text(item['name']),
                  trailing: buildDownloadButton(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
