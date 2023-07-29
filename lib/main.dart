import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:network_discovery/network_discovery.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(FileShareApp());

class FileShareApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Share App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: FileSharePage(),
    );
  }
}

class FileSharePage extends StatefulWidget {
  @override
  State<FileSharePage> createState() => _FileSharePageState();
}

class _FileSharePageState extends State<FileSharePage> {
  String receiverIp = '';
  String hostip = '';
  List<String> _activeHosts = [];
  String? _selectedHost;
  Socket? _socket;

  final TextEditingController _messageController = TextEditingController();
  List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    _scanNetwork();
  }

  Future<void> _scanNetwork() async {
    final String? deviceIP = await _getSubnet();
    print(deviceIP);

    if (deviceIP != null && deviceIP.isNotEmpty) {
      final String subnet = deviceIP.substring(0, deviceIP.lastIndexOf('.'));
      List<String> activeHostnames =
          await _findActiveHostsWithHostnames(subnet);

      setState(() {
        _activeHosts = activeHostnames;
      });
    } else {
      print("Couldn't get IP Address");
    }
  }

  Future<String?> _getSubnet() async {
    final subnet = await NetworkInfo().getWifiIP();
    setState(() {
      hostip = subnet!;
    });
    return subnet;
  }

  Future<List<String>> _findActiveHostsWithHostnames(String subnet) async {
    final List<String> activeHosts = [];
    final stream = NetworkDiscovery.discoverAllPingableDevices(subnet);
    await for (HostActive host in stream) {
      // print('${host.ip} - ${host.isActive}');
      if (host.isActive) {
        activeHosts.add(host.ip);
      }
    }
    activeHosts.remove(await _getSubnet());
    return activeHosts;
  }

  void _onHostSelected(String host) {
    setState(() {
      _selectedHost = host;
      receiverIp = host;
    });

    // Connect to the selected host
    _connectToHost();
  }

  Future<void> _connectToHost() async {
    try {
      _socket = await Socket.connect(_selectedHost!, 12345);
      print('Connected to $_selectedHost:12345');

      // Start listening for incoming messages from the host
      _socket!.listen(
        (data) {
          final message = utf8.decode(data);
          print('Received message: $message');

          if (message.startsWith('FILE:')) {
            // Extract the file name from the message
            final fileInfoJson = message.substring('FILE:'.length);
            final fileInfo = jsonDecode(fileInfoJson);
            final fileName = fileInfo['name'];

            setState(() {
              _messages.add('Received: $fileName');
            });
          } else {
            setState(() {
              _messages.add('Received: $message');
            });
          }
        },
        onError: (error) {
          print('Error listening to socket: $error');
          _socket?.destroy();
          _socket = null;
        },
        onDone: () {
          print('Connection closed by remote host.');
          _socket?.destroy();
          _socket = null;
        },
      );
    } catch (e) {
      print('Error connecting to $_selectedHost:12345');
      print(e);
      _socket?.destroy();
      _socket = null;
    }
  }

  // For sending messages
  void _sendMessage(String message) {
    if (message.trim().isNotEmpty && _socket != null) {
      final messageData = {'type': 'message', 'data': message};
      final messageJson = jsonEncode(messageData);
      final messageBytes = utf8.encode(messageJson);
      _socket!.add(messageBytes);
      setState(() {
        _messages.add('Sent: $message');
      });
    }
  }

  // For sending files
  void _sendFile(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      try {
        Socket socket = await Socket.connect(receiverIp, 12345);

        List<int> bytes = await file.readAsBytes();
        String fileName = file.path.split('/').last;
        String base64Data = base64Encode(bytes);

        final fileData = {'type': 'file', 'name': fileName, 'data': base64Data};
        final fileJson = jsonEncode(fileData);
        socket.writeln(fileJson);
        await socket.flush();

        await socket.close(); // Close the socket after sending the file.

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File sent successfully!')),
        );
      } catch (e) {
        print('Error sending file: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending file!')),
        );
      }
    }
  }

  void _startServer() async {
    try {
      ServerSocket serverSocket = await ServerSocket.bind('0.0.0.0', 12345);
      print('Server listening on port 12345');

      await for (Socket socket in serverSocket) {
        print('Client connected: ${socket.remoteAddress}:${socket.remotePort}');

        StringBuffer buffer = StringBuffer();

        socket.listen(
          (data) {
            try {
              print(
                  'Received data from ${socket.remoteAddress}:${socket.remotePort}');
              buffer.write(utf8.decode(data));
              print(utf8.decode(data));
              setState(() {
                Map<String, dynamic> info = jsonDecode(utf8.decode(data));
                if (info['type'] != 'file') {
                  _messages.add('Received: ${info['data']}');
                }
              });
            } catch (e) {
              print('Error handling data: $e');
            }
          },
          onDone: () async {
            try {
              Map<String, dynamic> fileInfo = jsonDecode(buffer.toString());
              String fileName = fileInfo['name'];
              String base64Data = fileInfo['data'];
              List<int> bytes = base64Decode(base64Data);
              final status = await Permission.storage.request();
              if (status.isGranted) {
                final pickedDirectory =
                    await FilePicker.platform.getDirectoryPath();
                if (pickedDirectory != null) {
                  final destinationDirectory = Directory(pickedDirectory);
                  final file = File('${destinationDirectory.path}/$fileName');
                  await file.writeAsBytes(bytes);
                  print('File received and saved: $fileName');
                  setState(() {
                    _messages.add('Received: $fileName');
                  });
                } else {
                  print('No destination folder selected.');
                }
              } else {
                print('Permission to access storage denied.');
              }
              socket.close();
            } catch (e) {
              print('Error handling data: $e');
            }
          },
        );
      }
    } catch (e) {
      print('Error starting server: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('File Share')),
      body: Column(
        children: [
          Text('Your ip: $hostip'),
          Expanded(
            child: ListView.builder(
              itemCount: _activeHosts.length,
              itemBuilder: (context, index) {
                final host = _activeHosts[index];
                return ListTile(
                  title: Text(host),
                  onTap: () => _onHostSelected(host),
                );
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ListTile(
                  title: Text(message),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(hintText: 'Type a message'),
                    onSubmitted: (message) {
                      _sendMessage(message);
                      _messageController.clear();
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () {
                    final message = _messageController.text.trim();
                    _sendMessage(message);
                    _messageController.clear();
                  },
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _sendFile(context),
            child: Text('Send File'),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: _startServer,
            child: Text('Start Receiver'),
          ),
        ],
      ),
    );
  }
}
