import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuple/tuple.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (light, dark) {
        return MaterialApp(
          title: "Ripit's",
          theme: ThemeData(
      appBarTheme: const AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarIconBrightness: Brightness.dark,
                statusBarColor: Colors.transparent,
              ),
            ),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            useMaterial3: true, //A gérer dans le futur
            colorScheme: light ?? ColorScheme.fromSwatch(primarySwatch: Colors.red)
          ),
          darkTheme: ThemeData(
            appBarTheme: const AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarIconBrightness: Brightness.light,
                statusBarColor: Colors.transparent,
              ),
            ),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            useMaterial3: true,
            colorScheme: dark ?? ColorScheme.fromSwatch(primarySwatch: Colors.red, brightness: Brightness.dark)
          ),
          themeMode: ThemeMode.system,
          home: const MyHomePage(title: "Ripit's"),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  var pageIndex = 0;
  var autoRecord = false;
  Record record = Record();
  var currentlyRecording = false;
  var fileList = [];
  var lastFileName = "";
  var previousFileName = "";
  var currentlyPlaying = const Tuple2<bool, String>(false, "");
  final player = AudioPlayer();
  var trimLength = 30;
  var duration = 1.0;
  var songProgress = const Tuple2<double, String>(0.0, "");
  var brightness = Brightness.light;

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  void beginRecording(filename) async {
    if (await record.hasPermission()) {
      // Start recording
      var f = await _localPath;
      var path = '$f/autorec/$filename.opus';
      await record.start(
        path: path,
        encoder: AudioEncoder.opus, // by default
        bitRate: 128000, // by default
        samplingRate: 44100, // by default
      );
      setState(() {
        currentlyRecording = true;
      });
    }
  }

  Future<void> endRecording() async {
    await record.stop();
    setState(() {
      currentlyRecording = false;
    });
    return;
  }

  // String getStringLength(int totalLen, int len) {
  //   var delta = totalLen - len;
  //   var m =
  //   return "";
  // }

  Future<void> trimFile(filename) async {
    var file = '${await _localPath}/$filename.m4a';
    FFmpegKit.execute('-sseof -$trimLength -i "$previousFileName" $file').then((session) async {
      // The list of logs generated for this execution
      final logs = await session.getLogs();
      if (kDebugMode) {
        print(logs.map((x) => x.getMessage()));
      }
    });
    return;
  }

  Future<void> dialogName() async {
    var textController = TextEditingController();
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
              title: const Text("Save file as"),
              actions: [
                TextField(
                  controller: textController,
                ),
                TextButton(
                    onPressed: (){Navigator.pop(context);},
                    child: const Text("Cancel")
                ),
                TextButton(
                    onPressed: () {
                      trimFile(textController.text);
                      Navigator.pop(context);
                      return;
                    },
                    child: const Text("Confirm")
                ),
              ]
          );
        }
    );
  }

  Future<void> listFiles() async {
    var dir = await getApplicationDocumentsDirectory();
    var autoDir = Directory('${dir.path}/autorec/');
    autoDir.create();
    var f = await dir.list(recursive: true).toList();
    for (var file in await autoDir.list(recursive: true).toList()) {
      File(file.path).delete();
    }
    setState(() {
      fileList = f;
    });
    var stream = dir.watch(recursive: true);
    stream.listen((data){
      switch (data.type) {
        case FileSystemEvent.create:
          setState(() {
            fileList.add(File(data.path));
          });
          break;
        case FileSystemEvent.delete:
          setState(() {
            fileList.removeWhere((x) => x.path == data.path);
          });
          break;
        default:
          break;
      }
    });
  }

  Future<SharedPreferences> getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  @override
  void didChangePlatformBrightness() {
      setState(() {
        brightness = WidgetsBinding.instance.window.platformBrightness;
      });
    super.didChangePlatformBrightness();
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    brightness = WidgetsBinding.instance.window.platformBrightness;
    listFiles();
    getPrefs().then((prefs) {
      if (!prefs.containsKey('trimlen')) {
        prefs.setInt('trimlen', 30);
        setState(() {
          trimLength = 30;
        });
      } else {
        setState(() {
          trimLength = prefs.getInt('trimlen')!;
        });
      }
      if (!prefs.containsKey('autorec')) {
        prefs.setBool('autorec', false);
      }
      if (prefs.getBool('autorec')! == true) {
        setState(() {
          autoRecord = true;
        });
        var date = DateTime.now();
        beginRecording(date.toString());
      }
    });
    player.positionStream.listen((event) {
      setState(() {
        songProgress = songProgress.withItem1(event.inMilliseconds.toDouble() / duration);
      });
    });
    player.durationStream.listen((event) {
      setState(() {
        var e = event?.inMilliseconds.toDouble() ?? 1.0;
        duration = (event?.inMilliseconds != null) ? ((e > 0.0) ? e : 10.0) : 10.0;
      });
    });
    player.playerStateStream.listen((ev) {
      if (ev.processingState == ProcessingState.completed) {
        setState(() {
          songProgress = songProgress.withItem1(0.0);
          currentlyPlaying = currentlyPlaying.withItem1(false);
        });
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    endRecording();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var listPage = fileList.map((x) => x.path).where((x) => x.endsWith('.m4a')).where((x) => !x.contains('/autorec/')).isEmpty ? const Center(
      child: Text("Start recording"),
    ) : ListView(
      children: fileList.map((x) => x.path).where((x) => x.endsWith('.m4a')).where((x) => !x.contains('/autorec/')).map((x) =>
      Stack(
        children: [
          Container(
            height: 50,
            width: (songProgress.item2 == x) ? MediaQuery.of(context).size.width * songProgress.item1 : 0,
            color: Colors.red,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () async {
                  if (!currentlyPlaying.item1) {
                    setState(() {
                      currentlyPlaying = currentlyPlaying.withItem1(true);
                      currentlyPlaying = currentlyPlaying.withItem2(x);
                      songProgress = songProgress.withItem2(x);
                    });
                    await player.setFilePath(x);
                    await player.play();
                  } else {
                    setState(() {
                      currentlyPlaying = currentlyPlaying.withItem1(false);
                    });
                    await player.pause();
                  }
                },
                icon: (currentlyPlaying.item1 && currentlyPlaying.item2 == x) ? const Icon(Icons.pause) : const Icon(Icons.play_arrow),
              ),
              Column(
                children: [
                  Text(x.split('/').last.split('.').first),
                ],
              ),
              IconButton(
                onPressed: (){
                  File(x).delete();
                },
                icon: const Icon(Icons.delete),
              ),
            ],

          ),
        ],
      )
      ).toList(),
    );
    var settingsPage = ListView(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Auto Record"),
            Switch(
              value: autoRecord,
              onChanged: (val) {
                setState(() {
                  autoRecord = val;
                });
                getPrefs().then((prefs) {
                  prefs.setBool('autorec', val);
                });
              },
            )
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Audio Length"),
            DropdownButton(
              items: const [
                DropdownMenuItem(value: 15,child: Text("15s"),),
                DropdownMenuItem(value: 30,child: Text("30s"),),
                DropdownMenuItem(value: 60,child: Text("1m"),),
                DropdownMenuItem(value: 300,child: Text("5min"),),
                DropdownMenuItem(value: 900,child: Text("15min"),),
              ],
              onChanged: (val) {
                setState(() {
                  trimLength = val as int;
                  getPrefs().then((prefs) {
                    prefs.setInt('trimLength', trimLength);
                  });
                });
              },
              value: trimLength,
            )
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: (){
              launchUrl(Uri.parse('https://github.com/srgoti/Ripits.git'), mode: LaunchMode.externalApplication);
            },
            child: Image.asset(brightness == Brightness.light ? 'assets/github-mark.png' : 'assets/github-mark-white.png', width: 50, height: 50,),
            )
          ],
        )
      ],
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        // foregroundColor: Theme.of(context)!.primaryColor,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 36),),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.red,
          onPressed: () async {
            previousFileName = lastFileName;
            var date = DateTime.now();
            var d =  date.toString();
            var f = await _localPath;
            if (currentlyRecording) {
              await endRecording();
              dialogName();
            } else {
              previousFileName = '$f/autorec/$d.opus';
            }
            lastFileName = '$f/autorec/$d.opus';
            beginRecording(d);
          },
          tooltip: 'Record',
          elevation: 2.0,
          child: GestureDetector(
              child: Icon(currentlyRecording ? Icons.stop : Icons.mic),
              onLongPress: () async {
                if (await record.isRecording()) {
                  await endRecording();
                  dialogName();
                }
              }
          ),
        ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: pageIndex,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (index) {
          setState(() {
            pageIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: "Recordings"),
          NavigationDestination(icon: Icon(Icons.settings), label: "Settings"),
        ],
          elevation: 0,
      ),
      body: pageIndex == 0 ? listPage : settingsPage
    );
  }
}
