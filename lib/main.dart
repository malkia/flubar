import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';

Random _random = Random();
TimeSpan _totalSpan = null;
Map<int, List<TimeSpan>> _spans = null;

// Copied from flutter/examples/flutter_gallery/lib/main.dart
//
// Sets a platform override for desktop to avoid exceptions. See
// https://flutter.dev/desktop#target-platform-override for more info.
// TODO(gspencergoog): Remove once TargetPlatform includes all desktop platforms.
// This is only included in the Gallery because Flutter's testing infrastructure
// uses the Gallery for various tests, and this allows us to test on desktop
// platforms that aren't yet supported in TargetPlatform.
void _enablePlatformOverrideForDesktop() {
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
  }

  if(kIsWeb) {
    WidgetsFlutterBinding.ensureInitialized();
  }
}

void main() async {
  _enablePlatformOverrideForDesktop();

//  var tracingFile = File("sample.tracing");
//  var tracingContents = await tracingFile.readAsString();
  var tracingContents = await rootBundle.loadString('sample.tracing');
  var tracingJson = null;

  bool triedToFix = false;
  for (;;) {
    bool done = false;
    try {
      tracingJson = jsonDecode(tracingContents);
      done = true;
    } on FormatException catch (exception, stack) {
      if (triedToFix) {
        print(stack);
        throw exception;
      }
      triedToFix = true;
      tracingContents += "{}]";
    }
    if (done) break;
  }

  var spans = Map<int, List<TimeSpan>>();
  for (var index = 0; index < tracingJson.length; index++) {
    var jsonSpan = tracingJson[index];
    if (!jsonSpan.containsKey("tid")) continue;
    int threadId = jsonSpan["tid"];
    String op = jsonSpan["ph"];
    if (op != "X") continue;

    double startTime = jsonSpan["ts"];
    double duration = jsonSpan["dur"];
    String label = jsonSpan["name"];
    var span = TimeSpan(
        startTime: startTime,
        duration: duration,
        label: SpanLabel(label: label));
    if( !spans.containsKey(threadId) )
      spans[threadId] = List<TimeSpan>();
    spans[threadId].add(span);
  }

  print(spans.length);

  var totalMinTime = double.infinity;
  var totalMaxTime = double.negativeInfinity;
  spans.forEach((int threadId, List<TimeSpan> threadSpans) {
    threadSpans.sort((TimeSpan a, TimeSpan b) {
      return (a.startTime - b.startTime).sign.toInt();
    });
    var minTime = double.infinity; //threadSpans[0].startTime;
    var maxTime = double.negativeInfinity; //.endTime;
    threadSpans.forEach((TimeSpan t) {
      minTime = min(minTime, t.startTime);
      maxTime = max(maxTime, t.endTime);
    });
    print(minTime);
    print(maxTime);
    totalMinTime = min(totalMinTime, minTime);
    totalMaxTime = max(totalMaxTime, maxTime);
  });

  print(totalMinTime);
  print(totalMaxTime);
  var totalSpan = TimeSpan(startTime: totalMinTime, duration: totalMaxTime - totalMinTime);

  _spans = spans;
  _totalSpan = totalSpan;

// Enable integration testing with the Flutter Driver extension.
// See https://flutter.dev/testing/ for more info.
  //enableFlutterDriverExtension();
  //WidgetsFlutterBinding.ensureInitialized();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class SpanLabel {
  final String label;

  const SpanLabel({this.label});
}

class TimeSpan {
  final double startTime;
  final double duration;
  final double endTime;
  final SpanLabel label;

  const TimeSpan({this.startTime, this.duration, this.label})
      : assert(duration >= 0.0),
        endTime = startTime + duration;
}

class SomePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint();
    paint.strokeWidth = 1;
    paint.style = PaintingStyle.fill;
    print(_totalSpan.duration);
    //if( _totalSpan.duration > 10000)
    //  _totalSpan = TimeSpan(startTime: _totalSpan.startTime, duration: 10000);
    //paint.blendMode = BlendMode.difference;

    print("starttime ${_totalSpan.startTime}");
    var totalStartTime = max(226888674068.1, _totalSpan.startTime);
    var totalDuration = min(1250000, _totalSpan.duration);
    var height = size.height / _spans.length;
    double y = 0;
    int cnt = 0;
    _spans.forEach((int threadId, List<TimeSpan> spans) {
      for (var i = 0; i < spans.length; i ++ ) {
        var span = spans[i];
        var start = (span.startTime - totalStartTime) * size.width /
            totalDuration;
        var width = span.duration * size.width / totalDuration;
        //print(start);
        var rect = Rect.fromLTWH(start, y, width, height - 1 );
        paint.color = Color.fromARGB(255, cnt % 256, cnt * 5 % 256, cnt * 7 % 256);
        canvas.drawRect(rect, paint);
        cnt ++;
      }
      y += height;
    });
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    print("shouldRepaint");
    return false;
  }

  @override
  bool shouldRebuildSemantics(CustomPainter oldDelegate) {
    print("shouldRebuildSemantics");
    return false;
  }

  @override
  bool hitTest(Offset position) {
    return null;
  }
}

class LotsOfThings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height - 200 ),
      painter: SomePainter(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      backgroundColor: Colors.blueGrey,
      drawerScrimColor: Colors.deepPurple,
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.display1,
            ),
            LotsOfThings(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
