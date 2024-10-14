import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:async';

class WebcamStreamScreen extends StatefulWidget {
  @override
  _WebcamStreamScreenState createState() => _WebcamStreamScreenState();
}

class _WebcamStreamScreenState extends State<WebcamStreamScreen> {
  String streamUrl = 'http://192.168.0.14:8001/video_feed';
  late WebSocketChannel channel;
  String statusMessage = 'Nenhuma mensagem recebida';
  String SecurityMessage = "";
  String? base64Image;
  Color securityMessageColor = Colors.red;

  int? countdown; // Variável para a contagem regressiva

  @override
  void initState() {
    super.initState();
    channel = IOWebSocketChannel.connect('ws://192.168.0.14:8001/ws');

    // Escuta as mensagens recebidas do WebSocket
    channel.stream.listen((message) {
      if (message.trim().toLowerCase().startsWith("img:")) {
        setState(() {
          base64Image = message.substring(4).trim();
        });
      } else if (message.trim().toLowerCase().startsWith("msg:")) {
        String msg = message.substring(4).trim();
        setState(() {
          statusMessage = msg;
        });

        // Iniciar contagem regressiva dependendo do conteúdo da mensagem
        if (msg.contains("Analise volta em 10") || msg.contains("Pessoa Detectada. Tirando foto em 10 segundos") ) {
          setState(() {
            countdown = 10;
          });
        } 
      } else if (message.trim().toLowerCase().startsWith("sec:")) {
        String secMessage = message.substring(4).trim();
        setState(() {
          SecurityMessage = secMessage;
          securityMessageColor = secMessage.contains("Todos os itens de segurança presentes para ")
              ? Colors.green
              : Colors.red;
        });
      } else {
        setState(() {
          statusMessage = message.trim();
        });
      }
    });
  }

  @override
  void dispose() {
    channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Webcam Streaming'),
      ),
      body: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  padding: EdgeInsets.all(20),
                  margin: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Mjpeg(
                    stream: streamUrl,
                    isLive: true,
                    error: (context, error, stack) {
                      return Center(child: Text('Erro ao carregar o stream'));
                    },
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Container(
                  padding: EdgeInsets.all(20),
                  margin: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: base64Image != null
                      ? Image.memory(
                          Base64Decoder().convert(base64Image!),
                          fit: BoxFit.cover,
                        )
                      : Center(
                          child: Text(
                            'Nenhuma imagem recebida',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
          SizedBox(height: 5),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              statusMessage,
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Exibe o widget da contagem regressiva se `countdown` não for nulo
          if (countdown != null)
            CountdownWidget(
              initialCountdown: countdown!,
              onCountdownComplete: () {
                setState(() {
                  countdown = null;
                });
              },
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 80.0),
            child: Text(
              SecurityMessage,
              style: TextStyle(fontSize: 20, color: securityMessageColor),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class CountdownWidget extends StatefulWidget {
  final int initialCountdown;
  final VoidCallback onCountdownComplete;

  CountdownWidget({
    required this.initialCountdown,
    required this.onCountdownComplete,
  });

  @override
  _CountdownWidgetState createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  late int countdown;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    countdown = widget.initialCountdown;
    timer = Timer.periodic(Duration(seconds: 1), (Timer t) {
      setState(() {
        if (countdown > 0) {
          countdown -= 1;
        } else {
          t.cancel();
          widget.onCountdownComplete(); // Chama o callback quando a contagem termina
        }
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      'Contagem regressiva: $countdown segundos',
      style: TextStyle(
        fontSize: 18,
        color: Colors.orange,
      ),
    );
  }
}

void main() => runApp(MaterialApp(
      home: WebcamStreamScreen(),
      theme: ThemeData.dark(),
    ));
