import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zoom_widget/zoom_widget.dart';
import 'package:photo_view/photo_view.dart';

var outScale = 1.0;
var outPosition = Offset(0.0, 0.0);

Offset globalPan = Offset(0.0, 0.0);
Offset globalScale = Offset(0.01, 1.0);
Offset headPan = Offset(0.0, 0.0);
Offset restPan = Offset(0.0, 0.0);
Offset headScale = Offset(0.0, 0.0);
Offset restScale = Offset(0.0, 0.0);
double localAdjustment = 0;

Offset get currentPan {
  Offset ofs = globalPan + headPan - restPan;
//  var dx = min(max(ofs.dx, -1000.0), 1500.0);
  //var dy = min(max(ofs.dy, -1000.0), 1500.0);
  return Offset(ofs.dx + localAdjustment,ofs.dy);
}

Offset get currentScale {
  double dx = globalScale.dx * restScale.dx;
  double dy = globalScale.dy * restScale.dy;
  dx = min(max(dx, 0.01), 100.0);
  dy = min(max(dy, 0.01), 100.0);
  return Offset( dx, dy );
}

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

Offset _scale = Offset(1.0, 1.0);
Offset _offset = Offset(0.0, 0.0);

Offset _tempScale = Offset(1.0, 1.0);
Offset _tempOffset = Offset(0.0, 0.0);

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

    double startTime = jsonSpan["ts"] / 1e3;
    double duration = jsonSpan["dur"] / 1e3;
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

class RenderStrip {
  double startTime;
  double endTime;
  int depthLevel;
  Vertices vertices;
}

class SomePainter extends CustomPainter {
  void _drawSomeVertices(Canvas canvas, Size size) {
    //return;
    //_scale = 1.0;
    //if( _random.nextInt(10) == 0 ) {
    //_verts = null;
    //}
    if (_verts == null) {
      var numRects = 1500;
      // 2 triangles, of 3 vertices, of 2 coordinates
      var numPoints = 2 * 3 * 2 * numRects;
      var xy = Float32List(numPoints * 2 /* for each coord */);
      var rgb = Int32List(numPoints);
      for (var r = 0; r < numRects; r++) {
        var left = ((_random.nextDouble() * size.width * 9 / 10) ~/ 50) * 50.0;
        var top = ((_random.nextDouble() * size.height * 9 / 10) ~/ 50) * 30.0;
        var width = _random.nextDouble() * size.width / 50;
        var height = _random.nextDouble() * size.height / 50;
        var xyo = 12 * r;
        var co = 6 * r;
        var color = Color.fromARGB(_random.nextInt(255 - 196) + 196,
            _random.nextInt(255), _random.nextInt(255), _random.nextInt(255));
        rgb[co + 0] = color.value;
        xy[xyo + 0] = left;
        xy[xyo + 1] = top;
        rgb[co + 1] = color.value;
        xy[xyo + 2] = left;
        xy[xyo + 3] = top + height;
        rgb[co + 2] = color.value;
        xy[xyo + 4] = left + width;
        xy[xyo + 5] = top + height;
        rgb[co + 3] = color.value;
        xy[xyo + 6] = left + width;
        xy[xyo + 7] = top + height;
        rgb[co + 4] = color.value;
        xy[xyo + 8] = left + width;
        xy[xyo + 9] = top;
        rgb[co + 5] = color.value;
        xy[xyo + 10] = left;
        xy[xyo + 11] = top;
      }
      _verts = Vertices.raw(VertexMode.triangles, xy, colors: rgb);
    }
    var paint = Paint();

    //paint.color = Color.fromARGB(
    //    255, _random.nextInt(256), _random.nextInt(256), _random.nextInt(256));
    //paint.style = PaintingStyle.fill;
    //paint.blendMode = BlendMode.color;
    canvas.save();
    //canvas.translate(size.width*4/5, size.height/4);
    //canvas.translate(-size.width/2, -size.height/2);

    // if( _scrollEvent != null ) {
    //   print(_scrollEvent);
    //   print("before $_translation");
    //   //_translation = _scrollEvent.localPosition;
    //   print(" after $_translation");
    //   var scrollAmount = _scrollEvent.scrollDelta.dy.sign;
    //   _translation = _translation.translate( -scrollAmount*_scrollEvent.localPosition.dx / _scale, -scrollAmount*_scrollEvent.localPosition.dy / _scale );
    //   _scale += scrollAmount;
    //   _scrollEvent = null;
    // }
    //print("scale $_scale");
    //print(_translation);
    bool reset = false;
//    reset = true;
    // if( reset ) {
    //   _translation = Offset(0, 0);
    //   _scale = 1.5;
    // }

    //canvas.translate(_offset.dx + size.width / 2, _offset.dy + size.height / 2);
    //canvas.translate(-_tempOffset.dx, -_tempOffset.dy);
    //canvas.scale(_scale.dx * _tempScale.dx, _scale.dy * _tempScale.dy);
    //canvas.translate(_tempOffset.dx, _tempOffset.dy);
//    canvas.translate(_tempOffset.dx / (_scale.dx + _tempScale.dx), _tempOffset.dy / (_scale.dy + _tempScale.dy));
    canvas.drawVertices(_verts, BlendMode.color, paint);
    canvas.restore();

//    _translation = _translation.translate(
//        _random.nextDouble() * 4.0 - 2.0, _random.nextDouble() * 4.0 - 2.0);
    //_scale += (_random.nextDouble() * 2.0 - 1.0) / 10000.0;
    //_scale *= 0.99995;
  }

  @override
  void paint(Canvas canvas, Size size) {
    //_drawSomeVertices(canvas, size);
    //return;
    var paint = Paint();
    paint.strokeWidth = 1;
    paint.style = PaintingStyle.fill;
    //print(_totalSpan.duration);
    //if( _totalSpan.duration > 10000)
    //  _totalSpan = TimeSpan(startTime: _totalSpan.startTime, duration: 10000);
    //paint.blendMode = BlendMode.difference;

    //var totalStartTime = max(226888674068.1, _totalSpan.startTime);
    //var totalDuration = min(1250000, _totalSpan.duration);
    var totalStartTime = _totalSpan.startTime;
    var totalDuration = _totalSpan.duration;
    //var height = size.height / _spans.length * size.height / totalDuration;
    //var height = (size.height / _spans.length);//r * size.height / (3*totalDuration);
    double height = 16.0; // outScale;// / outScale;//16.0 / (sqrt(outScale));
    double ooScale = 1.0; // outScale;
    //print(height);
    //print(totalDuration);
    print("scale $currentPan $currentScale");
    double x = -currentPan.dx;// * currentScale.dx;///outPosition.dy;//size.height/3;// / outScale;
    double y = -currentPan.dy;//outPosition.dx / outScale;
    int cnt = 0;
    var stack = Int32List(1024);
    var limit = 10;
    _spans.forEach((int threadId, List<TimeSpan> spans) {
      spans = _spans[94332];
      int stackUsed = 0;
      int maxStackUsed = 0;
      if (limit-- < 0) return;
      for (var i = 0; i < spans.length/4; i++) {
        var span = spans[i];
        while (stackUsed > 0) {
          var parentIndex = stack[stackUsed - 1];
          if (spans[parentIndex].contains(span)) break;
          stackUsed--;
        }
        stack[stackUsed] = i;
        stackUsed++;
        maxStackUsed = max(maxStackUsed, stackUsed);
        double start = x + 
            (span.startTime - totalStartTime) * currentScale.dx;
        double width = span.duration * currentScale.dx;
        Rect r = Rect.fromLTWH(start, y + stackUsed * height, width, height - ooScale);
        paint.color = Color.fromARGB(255, cnt * 3 % 256, cnt * 5 % 256, cnt * 7 % 256);
        canvas.drawRect(r, paint);
        if( width > 30 )
        {
          TextSpan textSpan = new TextSpan(style: new TextStyle(color: Colors.white), text: "blah");
          TextPainter tp = new TextPainter(text: textSpan, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
          tp.layout();
          tp.paint(canvas, r.topLeft );
        }
         cnt++;
      }
      y += height * (maxStackUsed + 1);
    });
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    //print("shouldRepaint");
    return true;
  }
}

class LotsOfThings extends StatefulWidget {
  LotsOfThings({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  LotsOfThingsState createState() => LotsOfThingsState();
}

class LotsOfThingsState extends State<LotsOfThings> {
  PhotoViewControllerBase _photoViewController;
  PhotoViewScaleStateController _photoViewScaleStateController;

 @override
  void initState() {
    _photoViewController = PhotoViewController()
      ..scale = 1.0
      ..outputStateStream.listen((PhotoViewControllerValue event) {
        outScale = event.scale;
        outPosition = event.position;
        //print("photoViewController $event, ${_photoViewScaleStateController.scaleState}")
      });

    _photoViewScaleStateController = PhotoViewScaleStateController()
//    ..
      ..addIgnorableListener(() => {

      });
    super.initState();
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    _photoViewScaleStateController.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    _verts = null;
    _tempScale = Offset(1.0, 1.0);
    _tempOffset = Offset(0.0, 0.0);
    _offset = Offset(0.0, 0.0);
    _scale = Offset(1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // var size = Size(
    //   MediaQuery.of(context).size.width,
    //   MediaQuery.of(context).size.height - 200,
    // );
//    print("duration ${_totalSpan.duration}");
    var size = Size(_totalSpan.duration, _totalSpan.duration);
    // return Zoom(
    //     width: size.width,
    //     height: size.height,
    //     backgroundColor: Colors.amber[50],
    //     canvasColor: Colors.green,
    //     //colorScrollBars: Colors.red,
    //     //zoomSensibility: 5.0,
    //     doubleTapZoom: true,
    //     centerOnScale: true,
    //     //initZoom: 0.0,
    //     //scrollWeight: 100.0,
    //     onPositionUpdate: (Offset position) {
    //       print(position);
    //     },
    //     onScaleUpdate: (double scale, double zoom) {
    //       print("$scale  $zoom");
    //     },
    //     child: CustomPaint(size: Size(10240.0, 10240.0), painter: SomePainter()),
    //     );
    return Listener(
//      behavior: HitTestBehavior.translucent,
//      onPointerCancel: ((var p) => print("cancel $p")),
//      onPointerDown: ((var p) => print("cancel $p")),
      onPointerSignal: (var signalEvent) {
        var scrollEvent = signalEvent as PointerScrollEvent;
        if (scrollEvent == null) return;
          var dx = scrollEvent.scrollDelta.dx.sign / 100.0;
          var dy = scrollEvent.scrollDelta.dy.sign / 100.0;
          dx = dx + 1.0;
          dy = dy + 1.0;
          restScale = restScale.scale( dy, 1.0 ); //(dx, dy);
          print( "$dx $dy");
        setState(() {
        });
      },
    child: GestureDetector(
//        controller: _photoViewController,
        //scaleStateController: _photoViewScaleStateController,
  //      scaleStateChangedCallback: (PhotoViewScaleState state) => {
   //       print("state $state")
    //    },
     //   minScale: 0.0001,
      //  maxScale: 10000.0,
       // initialScale: 1.0,
        //enableRotation: true,
        behavior: HitTestBehavior.deferToChild,
        onScaleStart: (ScaleStartDetails d) {
          headPan = d.localFocalPoint;
          restPan = headPan;
          headScale = currentScale;
          localAdjustment = 0;
          setState(() {
          });
        },
        onScaleUpdate: (ScaleUpdateDetails d) {
          restPan = d.localFocalPoint;
          //print("update head=$headPan rest=$restPan");
          restScale = Offset( d.horizontalScale, d.verticalScale );
          localAdjustment = currentPan.dx * (headScale.dx - currentScale.dx);
          print("adjustment $localAdjustment");
          setState(() {
          });
        },
        onScaleEnd: (ScaleEndDetails d) {
          // globalPan is not scaled
          // restPan is not scaled too.
          // now user at position restPan
          // 
          // globalPan hasn't changed.
          // localPan shows where we have to scale at
          // prevScale is the previous scale
          // currentScale is the current scale

          // globalPan = 100
          // scale = 10
          // localPan = 50
          // 
          // focusPoint = globalPanA + localPan * scaleA
          //
          // scale = 20
          //
          // focusPoint = globalPanB + localPan * scaleB
          //
          // globalPanA + localPan * scaleA = globalPanB + localPan * scaleB
          // globalPanA = globalPanB + localPan * (scaleB - scaleA)
          // globalPanB = globalPanA + localPan * (scaleA - scaleB)

          var prevScale = headScale;
          //print("adjustment $adjustment prev=${prevScale.dx} cur=${headScale.dx}");
          globalPan = currentPan;
          globalScale = currentScale;
          headPan = Offset(0.0, 0.0);
          restPan = Offset(0.0, 0.0);
          headScale = Offset(0.0, 0.0);
          restScale = Offset(1.0, 1.0);
          localAdjustment = 0;
          setState(() {
          });
        },
        child: CustomPaint( size: Size(MediaQuery.of(context).size.width,
                MediaQuery.of(context).size.height), painter: SomePainter()),
        ));
  }

  Widget build_old(BuildContext context) {
    return new Listener(
//      behavior: HitTestBehavior.translucent,
//      onPointerCancel: ((var p) => print("cancel $p")),
//      onPointerDown: ((var p) => print("cancel $p")),
      onPointerSignal: (var signalEvent) {
        var scrollEvent = signalEvent as PointerScrollEvent;
        if (scrollEvent == null) return;
        setState(() {
          _offset = _offset.translate(
            scrollEvent.scrollDelta.dx / _scale.dx,
            -scrollEvent.scrollDelta.dy / _scale.dy,
          );
        });
      },
//      onPointerUp: ((var p) => print("cancel $p")),
//      onPointerMove: ((var p) {
//        _scale += p.delta.dy;
//        print("cancel $p");
//      }),
      child: GestureDetector(
          onPanUpdate: (var d) {
            setState(() {
              _offset = _offset.translate(
                d.delta.dx / _scale.dx,
                d.delta.dy / _scale.dy,
              );
            });
          },
          onLongPressStart: (var d) {
            setState(() {
              _tempScale = Offset(1.0, 1.0);
              _tempOffset = d.localPosition;
            });
          },
          onLongPressEnd: (var d) {
            setState(() {
              _tempScale = Offset(1.0, 1.0);
              _tempOffset = Offset(0.0, 0.0);
              print("END OF LONG PRESS");
            });
          },
          onLongPressMoveUpdate: (var d) {
            setState(() {
              _tempScale = d.localOffsetFromOrigin;
              var dx = d.localOffsetFromOrigin.dx / 16.0;
              var dy = d.localOffsetFromOrigin.dy / 16.0;
              if (dx >= -1 && dx <= 1.0) dx = dx.sign;
              if (dy >= -1 && dy <= 1.0) dy = dy.sign;
              _tempScale = Offset(dx, dy);
              print(
                  "longPress ${d.globalPosition} ${d.localPosition} ${d.offsetFromOrigin} ${d.localOffsetFromOrigin}");
            });
          },
          onForcePressUpdate: (var d) {
            setState(() {
              print("forcePress $d");
            });
          },
//        onVerticalDragCancel: () => print("cancel"),
//        onVerticalDragDown: (var d) => print(d),
//        onVerticalDragEnd: (var d) => print(d),
//        onVerticalDragStart: (var d) => print(d),
          behavior: HitTestBehavior.translucent,
          child: CustomPaint(
            size: Size(MediaQuery.of(context).size.width,
                MediaQuery.of(context).size.height - 200),
            painter: SomePainter(),
          )),
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
      body: LotsOfThings(),/*Center(
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
      ),*/
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
      // This trailing comma makes auto-formatting nicer for build methods.
//      bottomNavigationBar: BottomNavigationBar(
//          onTap: ((int which) {
//            print("$which");
//            switch (which) {
//              case 0:
//                break;
//              case 1:
//                break;
//            }
//          }),
//          items: const <BottomNavigationBarItem>[
//            const BottomNavigationBarItem(
//              title: Text("Test"),
//              icon: Icon(Icons.access_alarm),
//              activeIcon: Icon(Icons.access_time),
//              backgroundColor: Colors.blueGrey,
//            ),
//            const BottomNavigationBarItem(
//              title: Text("Test2"),
//              icon: Icon(Icons.access_alarm),
//              activeIcon: Icon(Icons.access_time),
//              backgroundColor: Colors.blueGrey,
//            )
//          ]),
    );
  }
}
