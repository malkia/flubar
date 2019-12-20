import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';

class TimeSpan {
  final double startTime;
  final double duration;
  final double endTime; // Calculated from startTime + duration

  // int stackLevel
  // int parentIndex
  // int labelIndex

  const TimeSpan({this.startTime, this.duration})
      : assert(duration >= 0.0),
        endTime = startTime + duration;

  bool overlaps(TimeSpan other) {
    return startTime <= other.startTime && other.startTime <= endTime ||
        startTime <= other.endTime && other.endTime <= endTime;
  }

  bool contains(TimeSpan other) {
    return startTime <= other.startTime &&
        other.startTime <= endTime &&
        startTime <= other.endTime &&
        other.endTime <= endTime;
  }
}

Random _random = Random();
TimeSpan _totalSpan = null;
Map<int, List<TimeSpan>> _spans = null;

/*
  List<TimeSpan> allSpans;

  Map<int16, List<int8, List<int32>>>

  For each thread (16 bit index)
    for each stack level (8 bit index)
       index to the timespan (32-bit)

  We can use binary search to find [first .. last] index each thread
  Although heuristic can be used here, since the timeline range is the same for all threads/stack levels.

  timeLine.startTime
  timeLine.endTime
  timeLine.List<int16> index to threads to show

  We need two indexes:

  Sorted by startTime
  Sorted by endTime

  This would tell us, for any given timeline view where is the start visible index, and end visible index.

  Float64x2List startAndEndTimeValues;
  Int32List     labelIndexAndStackDepth;
  Int32List     endTimeIndex;

  Each thread, at each stack level:
  Int32List   spanIndex;

  // All time spans information:
  // startTime and endTime, and string label.  
  class TimeSpans {
    // pair of start and end times, sorted by startTime
    Float64x2List startAndEndTimes;
    List<string> labels;
    Int32List labelIndex;
  }

  // A single strip of timespan bars, at specific stack level
  class TimeLineStrip {
    Int32List startTimeIndex;
    Int32List endTimeIndex;

    int lowerBound(double starTime, TimeSpans timeSpans) {
      int index = lowerBound(startTimeIndex, startTime, (Int32 a, Int32 b) {
        var startTimeA = timeSpans[startTimeIndex[a]][0];
        var startTimeA = timeSpans[startTimeIndex[a]][0];
      });
    }

    int upperBound(double endTime) {
    }
  }

  // The timeline for a single thread
  class ThreadTimeLine {
    int threadId;
    bool collapsed;
    // TimeLine strips for each stackLevel
    // The max stack level is the timeLineStrips.length
    List<TimeLineStrip> timeLineStrips;
  }

  class ProcessTimeLine {
    int processId;
    List<ThreadTimeLine> threadTimeLines; 
  }
*/

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

//  if(kIsWeb) {
  WidgetsFlutterBinding.ensureInitialized();
//  }
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
    //  String label = jsonSpan["name"];
    var span = TimeSpan(
      startTime: startTime,
      duration: duration,
    );
    if (!spans.containsKey(threadId)) spans[threadId] = List<TimeSpan>();
    spans[threadId].add(span);
  }

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
    totalMinTime = min(totalMinTime, minTime);
    totalMaxTime = max(totalMaxTime, maxTime);
  });

  var totalSpan =
      TimeSpan(startTime: totalMinTime, duration: totalMaxTime - totalMinTime);

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

Vertices _verts;
double _scale = 1.0;
Offset _translation = Offset(0, 0);

class SomePainter extends CustomPainter {
  void _drawSomeVertices(Canvas canvas, Size size) {
    if (_verts == null) {
      var numRects = 50000;
      // 2 triangles, of 3 vertices, of 2 coordinates
      var numCoords = 2 * 3 * 2 * numRects;
      var xy = Float32List(numCoords);
      var rgb = Int32List(numCoords);
      for (var r = 0; r < numRects; r++) {
        var left = _random.nextDouble() * size.width * 9 / 10;
        var top = _random.nextDouble() * size.height * 9 / 10;
        var width = _random.nextDouble() * size.width / 100;
        var height = _random.nextDouble() * size.height / 100;
        var xyo = 12 * r;
        var co = 6 * r;
        rgb[co + 0] = _random.nextInt(256) | (0xFF << 24);
        xy[xyo + 0] = left;
        xy[xyo + 1] = top;
        rgb[co + 1] = (_random.nextInt(256) << 8) | (0xFF << 24);
        xy[xyo + 2] = left;
        xy[xyo + 3] = top + height;
        rgb[co + 2] = (_random.nextInt(256) << 16) | (0xFF << 24);
        xy[xyo + 4] = left + width;
        xy[xyo + 5] = top + height;
        rgb[co + 3] = _random.nextInt(256) | (0xFF << 24);
        xy[xyo + 6] = left + width;
        xy[xyo + 7] = top + height;
        rgb[co + 4] = (_random.nextInt(256) << 8) | (0xFF << 24);
        xy[xyo + 8] = left + width;
        xy[xyo + 9] = top;
        rgb[co + 5] = (_random.nextInt(256) << 16) | (0xFF << 24);
        xy[xyo + 10] = left;
        xy[xyo + 11] = top;
      }
      _verts = Vertices.raw(VertexMode.triangles, xy, colors: rgb);
    }
    var paint = Paint();
    paint.color = Color.fromARGB(
        255, _random.nextInt(256), _random.nextInt(256), _random.nextInt(256));
    paint.style = PaintingStyle.stroke;
    paint.blendMode = BlendMode.values[_random.nextInt(BlendMode.values.length)];
    canvas.save();
    canvas.scale(_scale);
    canvas.translate(_translation.dx, _translation.dy);
    canvas.drawVertices(_verts,
        BlendMode.values[_random.nextInt(BlendMode.values.length)], paint);
    canvas.restore();

    _translation = _translation.translate( _random.nextDouble() * 4.0 -2.0, _random.nextDouble() * 4.0 -2.0);
    _scale += (_random.nextDouble() * 2.0 - 1.0) / 10000.0;
    _scale *= 0.99995;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawSomeVertices(canvas, size);
    return;
    var paint = Paint();
    paint.strokeWidth = 1;
    paint.style = PaintingStyle.fill;
    //print(_totalSpan.duration);
    //if( _totalSpan.duration > 10000)
    //  _totalSpan = TimeSpan(startTime: _totalSpan.startTime, duration: 10000);
    //paint.blendMode = BlendMode.difference;

    var totalStartTime = max(226888674068.1, _totalSpan.startTime);
    var totalDuration = min(1250000, _totalSpan.duration);
    var height = size.height / _spans.length;
    double y = 0;
    int cnt = 0;
    var stack = Int32List(1024);
    var limit = 5;
    _spans.forEach((int threadId, List<TimeSpan> spans) {
      var stackUsed = 0;
      var maxStackUsed = 0;
      if (limit-- < 0) return;
      for (var i = 0; i < spans.length; i++) {
        var span = spans[i];
        while (stackUsed > 0) {
          var parentIndex = stack[stackUsed - 1];
          if (spans[parentIndex].contains(span)) break;
          stackUsed--;
        }
        stack[stackUsed] = i;
        stackUsed++;
        maxStackUsed = max(maxStackUsed, stackUsed);
        var start =
            (span.startTime - totalStartTime) * size.width / totalDuration;
        var width = span.duration * size.width / totalDuration;
        var rect =
            Rect.fromLTWH(start, y + stackUsed * height, width, height - 1);
        paint.color =
            Color.fromARGB(255, cnt % 256, cnt * 5 % 256, cnt * 7 % 256);
        canvas.drawRect(rect, paint);
        cnt++;
      }
      y += height * (maxStackUsed + 1);
    });
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    //print("shouldRepaint");
    return false;
  }

  @override
  bool shouldRebuildSemantics(CustomPainter oldDelegate) {
    //print("shouldRebuildSemantics");
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
      size: Size(MediaQuery.of(context).size.width,
          MediaQuery.of(context).size.height - 200),
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
