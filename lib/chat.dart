import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'main.dart';

class ChatPage extends StatefulWidget {
  final String ip;
  ChatPage({required this.ip});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  Future<void> _sendMessage(String message) async {
    Socket socket = await Socket.connect(widget.ip, 12345);
    if (message.trim().isNotEmpty) {
      final messageData = {'type': 'message', 'data': message};
      final messageJson = jsonEncode(messageData);
      final messageBytes = utf8.encode(messageJson);
      socket.add(messageBytes);
      setState(() {
        messages.add('Sent: $message');
      });
    }
  }

  // For sending files
  void _sendFile(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      try {
        Socket socket = await Socket.connect(widget.ip, 12345);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.ip}")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
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
                    controller: messageController,
                    decoration: InputDecoration(hintText: 'Type a message'),
                    onSubmitted: (message) {
                      _sendMessage(message);
                      messageController.clear();
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () {
                    final message = messageController.text.trim();
                    _sendMessage(message);
                    messageController.clear();
                  },
                ),
                ElevatedButton(
                  onPressed: () => _sendFile(context),
                  child: Text('Send File'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
