import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:network_discovery/network_discovery.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'chat.dart';

String receiverIp = '';
String hostip = '';
List<String> activeHosts = [];
String? selectedHost;
Socket? socket;
final TextEditingController messageController = TextEditingController();
List<String> messages = [];

void main() => runApp(FileShareApp());

class FileShareApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'File Share App',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: FileSharePage(),
    );
  }
}

class FileSharePage extends StatefulWidget {
  @override
  State<FileSharePage> createState() => _FileSharePageState();
}

enum state {
  SEND,
  RECIEVE,
  INITIAL,
}

class _FileSharePageState extends State<FileSharePage> {
  String receiverIp = '';
  String hostip = '';
  List<String> activeHosts = [];
  String? selectedHost;
  Socket? socket;
  final TextEditingController messageController = TextEditingController();
  var currState = state.INITIAL;

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
        activeHosts = activeHostnames;
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
      selectedHost = host;
      receiverIp = host;
    });
    // Connect to the selected host
    _connectToHost();
  }

  Future<void> _connectToHost() async {
    try {
      socket = await Socket.connect(selectedHost!, 12345);
      print('Connected to $selectedHost:12345');

      // Start listening for incoming messages from the host
      socket!.listen(
        (data) {
          final message = utf8.decode(data);
          print('Received message: $message');

          if (message.startsWith('FILE:')) {
            // Extract the file name from the message
            final fileInfoJson = message.substring('FILE:'.length);
            final fileInfo = jsonDecode(fileInfoJson);
            final fileName = fileInfo['name'];

            setState(() {
              messages.add('Received: $fileName');
            });
          } else {
            setState(() {
              messages.add('Received: $message');
            });
          }
        },
        onError: (error) {
          print('Error listening to socket: $error');
          socket?.destroy();
          socket = null;
        },
        onDone: () {
          print('Connection closed by remote host.');
          socket?.destroy();
          socket = null;
        },
      );
    } catch (e) {
      print('Error connecting to $selectedHost:12345');
      print(e);
      socket?.destroy();
      socket = null;
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
                  messages.add('Received: ${info['data']}');
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
                    messages.add('Received: $fileName');
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
    var media = MediaQuery.of(context);
    double pwidth = media.size.width;
    double pheight = media.size.height;
    activeHosts.add("192.168.43.1");
    return Scaffold(
      floatingActionButton: currState == state.SEND
          ? Container(
              alignment: Alignment.center,
              margin: EdgeInsets.symmetric(vertical: pheight * 0.02),
              width: pwidth * 0.85,
              height: pheight * 0.04,
              decoration: BoxDecoration(
                color: Color(0x90FFF400),
                borderRadius: BorderRadius.all(Radius.circular(50)),
              ),
              child: Text(
                "Select an IP address to start sharing!",
                style: TextStyle(
                  color: Colors.deepPurpleAccent,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            )
          : Container(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      appBar: AppBar(
          title: Row(
        children: [
          Text('Share Fa'),
          SvgPicture.asset("assets/images/x.svg", height: 25),
          Text('t'),
        ],
      )),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Image.asset("assets/images/yellow_stroke.png"),
                Text(
                  'Your IP: $hostip',
                  style: TextStyle(
                    color: Colors.deepPurpleAccent,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Ubuntu',
                  ),
                ),
              ],
            ),
            currState == state.SEND
                ? Padding(
                    padding: EdgeInsets.only(
                        bottom: pheight * 0.01, top: pheight * 0.03),
                    child: Text(
                      "Avaible Hosts:",
                      style: TextStyle(
                        color: Colors.deepPurpleAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Ubuntu',
                      ),
                      textAlign: TextAlign.left,
                    ),
                  )
                : Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Container(
                          height: pheight * 0.4,
                          child: Image.asset(
                            "assets/images/choose.gif",
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  currState = state.SEND;
                                });
                              },
                              child: Text('Send'),
                            ),
                            ElevatedButton(
                              onPressed: _startServer,
                              child: Text('Receive'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
            currState == state.SEND
                ? Expanded(
                    child: ListView.separated(
                      itemCount: activeHosts.length,
                      // itemCount: 2,
                      itemBuilder: (context, index) {
                        final host = activeHosts[index];
                        return ListTile(
// <<<<<<< HEAD
//                     trailing: InkWell(
//                       onTap: (){},
//                         child: Icon(Icons.send, color: Colors.deepPurple,),),
//                     leading: Icon(Icons.person, color: Colors.amberAccent,),
//                     title: Text(host),
//                     onTap: () => _onHostSelected(host),
//                   );
//                 }, separatorBuilder: (BuildContext context, int index) {
// =======
                            onTap: () {
                              _onHostSelected(host);
                            },
                            trailing: IconButton(
                              icon: Icon(Icons.send),
                              color: Colors.deepPurple,
                              onPressed: () {
                                _onHostSelected(host);
                                _sendFile(context);
                              },
                            ),
                            leading: IconButton(
                              icon: Icon(Icons.chat),
                              color: Colors.amberAccent,
                              onPressed: () {
                                _onHostSelected(host);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatPage(ip: host),
                                  ),
                                );
                              },
                            ),
                            title: Text(host));
                        // title: Text("hi"));
                      },
                      separatorBuilder: (BuildContext context, int index) {
                        return Container(
                          color: Colors.deepPurple,
                          height: 1,
                          margin: EdgeInsets.symmetric(horizontal: 15),
                        );
                      },
                    ),
                  )
                : Container(),
          ],
        ),
      ),
    );
  }
}
