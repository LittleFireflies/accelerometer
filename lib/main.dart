import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Accelerometer values
  double x = 0.0, y = 0.0, z = 0.0;

  List<double> recentMagnitudes = [];
  List<double> _recentAccelerometerReadings = [];
  final int windowSize = 100; // Number of samples to consider
  double lastShakeTime = 0.0; // Time of the last shake detection

  // Smoothed acceleration value (to reduce noise)
  double magnitude = 0.0;
  double previousMagnitude = 0.0;

  // Thresholds for classifying activities
  final double stillThreshold = 0.5;
  final double walkingThreshold = 2.0; // Example range for walking
  final double runningThreshold = 3.0; // Example range for running
  final double vehicleThreshold = 7.0; // Example for vehicle (steady)
  final double shakeThreshold = 4.0; // Magnitude threshold for shaking
  final double shakeDurationThreshold =
      0.5; // Minimum duration for shake detection in seconds

  // Timer for checking activity
  Timer? activityCheckTimer;

  String activity = "Unknown"; // Store current activity

  StreamSubscription<UserAccelerometerEvent>? _streamSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerStream;
  List<double> _accelerometerValues = [0.0, 0.0, 0.0];
  double _threshold = 0.5; // Define a threshold for distinguishing movements
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    /// Detect movement by accelerometer & orientation angle
    startUserAccelerometerDegreeListener();
    /// Detect movement by accelerometer only
    // startUserAccelerometerListener();
    // startActivityCheck();
    // analyzeMovement();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    activityCheckTimer?.cancel();
    super.dispose();
  }

  final double alpha = 0.8;
  final double gravity = 9.81;

  /// Degree-related
  // Previous filtered values for low-pass filter
  double previousX = 0;
  double previousY = 0;
  double previousZ = 0;
  // Number of samples for stable decision
  int requiredSamples = 5;
  int sampleCount = 0;
  List<String> orientations = [];
  String orientation = '';
  double finalAngle = 0;
  double previousAngle = 0;
  double angleDiff = 0;
  String movement = 'Still';
  String finalStatus = 'Still';
  List<String> recentMovement = [];

  void startUserAccelerometerDegreeListener() {
    _accelerometerStream = accelerometerEventStream().listen((AccelerometerEvent event) {

      // Apply low-pass filter
      double xFiltered = alpha * event.x + (1 - alpha) * previousX;
      double yFiltered = alpha * event.y + (1 - alpha) * previousY;
      double zFiltered = alpha * event.z + (1 - alpha) * previousZ;

      // Update previous values for the next iteration
      previousX = xFiltered;
      previousY = yFiltered;
      previousZ = zFiltered;

      setState(() {
        x = previousX;
        y = previousY;
        z = previousZ;
        magnitude = calculateMagnitude(xFiltered, yFiltered, zFiltered);
      });

      // Determine orientation
      String currentOrientation;
      double angle;

      if (zFiltered.abs() > 8) {
        // Device is likely flat
        angle = atan2(yFiltered, xFiltered) * (180 / pi);
        if (angle < 0) {
          angle += 360;
        }
        // currentOrientation = 'Flat orientation angle: ${angle.toStringAsFixed(2)}°';
        currentOrientation = 'Flat';
      } else if (yFiltered.abs() > xFiltered.abs()) {
        // Device is in portrait mode
        angle = atan2(xFiltered, zFiltered) * (180 / pi);
        if (angle < 0) {
          angle += 360;
        }
        // currentOrientation = 'Portrait orientation tilt: ${angle.toStringAsFixed(2)}°';
        currentOrientation = 'Portrait';
      } else {
        // Device is in landscape mode
        angle = atan2(yFiltered, zFiltered) * (180 / pi);
        if (angle < 0) {
          angle += 360;
        }
        // currentOrientation = 'Landscape orientation tilt: ${angle.toStringAsFixed(2)}°';
        currentOrientation = 'Landscape';
      }

      // Store orientation and count samples
      orientations.add(currentOrientation);
      sampleCount++;

      // After enough samples, determine the final orientation
      if (sampleCount >= requiredSamples) {
        setState(() {
          // if (orientations.contains('Flat')) {
          //   orientation = 'Flat';
          // } else {
          //   orientation = orientations
          //       .reduce((a, b) => a == b ? a : 'Unstable');
          // }

          if (previousAngle != 0) {
            final now = DateTime.now().toUtc();

            angleDiff = (angle - previousAngle).abs();
            if (angleDiff > 180) {
              angleDiff = (angleDiff - 360).abs();
            }

            if (angleDiff > 60) {
              movement = 'Movement detected';
            } else if (angleDiff > 45) {
              movement = 'Bumpy detected';
            } else {
              movement = 'Still';
            }

            recentMovement.add(movement);
            if (recentMovement.length > 10) {
              recentMovement.removeAt(0);
            }
            print(recentMovement);
            finalStatus = _determineFinalStatus(recentMovement);

            dataList
                .add([now, x, y, z, magnitude, angle, angleDiff, movement]);
          }
        });

        finalAngle = angle;
        previousAngle = angle;
        // save to csv
        // Reset for next decision cycle
        sampleCount = 0;
        orientations.clear();
      }
    });
  }

  // Listen to accelerometer events
  void startUserAccelerometerListener() {
    _streamSubscription =
        userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      setState(() {
        x = event.x;
        y = event.y;
        z = event.z;
        _accelerometerValues = [event.x, event.y, event.z];

        _recentAccelerometerReadings.add(event.x); // Store X readings for analysis
        _recentAccelerometerReadings.add(event.y); // Store Y readings for analysis
        _recentAccelerometerReadings.add(event.z); // Store Z readings for analysis

        if (_recentAccelerometerReadings.length > 30) {
          _recentAccelerometerReadings.removeRange(0, 3); // Keep only the last 10 readings
        }

        /// The code below no longer needed because `userAccelerometerEventStream`
        /// already removed the gravity
        // x = event.x;
        // y = event.y;
        // z = event.z;

        // lowPassFilter(alpha, x, y, z);
        //
        // // Subtract gravity from raw accelerometer readings
        // double filteredX = x - gravityX;
        // double filteredY = y - gravityY;
        // double filteredZ = z - gravityZ;

        // Calculate the magnitude of acceleration vector
        // print('filtered:: [$filteredX, $filteredY, $filteredZ]');
        // magnitude = calculateMagnitude(x, y, z);
        // //
        // // // double filteredMagnitude = highPassFilter(magnitude, previousMagnitude);
        // //
        // previousMagnitude = magnitude;
        //
        // if (magnitude >= 5) {
        //   print('Possible bumpy road. Ignoring...');
        //   activity = 'Possible bumpy road. Ignoring...';
        // } else if (x >= 5 || y >= 5 || z >= 5) {
        //   activity = 'Move in hand';
        // } else {
        //   activity = 'Still';
        // }
        //
        // // Maintain a sliding window of recent magnitudes
        // if (recentMagnitudes.length >= windowSize) {
        //   recentMagnitudes.removeAt(0); // Remove oldest value
        // }
        // recentMagnitudes.add(magnitude);
        //
        // // Detect if shaking
        // bool isShaking = recentMagnitudes.every((m) => m > shakeThreshold);
        // double currentTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
        // if (isShaking &&
        //     (currentTime - lastShakeTime) > shakeDurationThreshold) {
        //   activity = "Shaking in Hand";
        //   lastShakeTime = currentTime;
        // } /*else {
        //   activity = detectActivity(magnitude);
        // }*/
      });
    });
  }

  // Periodically check the activity
  void startActivityCheck() {
    activityCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      // if (activity != "Shaking in Hand") {
      // If not shaking, classify the current activity
      setState(() {
        activity = detectActivity(previousMagnitude);
      });
      // }
    });
  }

  // Detect the activity based on acceleration value
  String detectActivity(double acceleration) {
    if (acceleration <= stillThreshold) {
      return 'Still';
    } else if (acceleration <= walkingThreshold) {
      return "Walking";
    } else if (acceleration <= runningThreshold) {
      return "Running";
    } else if (acceleration > vehicleThreshold) {
      return "Driving";
    } else {
      return "Unknown";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Accelerometer Values:'),
            Text('X: ${x.toStringAsFixed(2)}'),
            Text('Y: ${y.toStringAsFixed(2)}'),
            Text('Z: ${z.toStringAsFixed(2)}'),
            Text('Angle: ${finalAngle.toStringAsFixed(2)}'),
            Text('AngleDiff: ${angleDiff.toStringAsFixed(2)}'),
            Text('statues: $recentMovement'),
            const SizedBox(height: 20),
            Text('Magnitude: ${previousMagnitude.toStringAsFixed(2)}'),
            const SizedBox(height: 20),
            Text('Activity: $activity', style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            Text('Orientation: $orientation', style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            Text('Status: $finalStatus', style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                var status = await Permission.storage.status;
                if (!status.isGranted) {
                  await Permission.storage.request();
                }

                final directory = Directory('/storage/emulated/0/Download');
                final filePath = '${directory?.path}/accelerometer_result.csv';
                final file = File(filePath);

                final csv = const ListToCsvConverter().convert(dataList);

                if (!file.existsSync()) {
                  await file.create();
                }

                file.writeAsString(csv, mode: FileMode.append);
                print('CSV saved at $filePath');
                dataList.clear();
              },
              child: const Text('Save CSV'),
            ),
          ],
        ),
      ),
    );
  }

  double calculateMagnitude(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  double highPassFilter(double current, double previous) {
    return (1 - alpha) * current + alpha * previous; // Simplified version
  }

  double gravityX = 0.0, gravityY = 0.0, gravityZ = 0.0;

  void lowPassFilter(double alpha, double x, double y, double z) {
    gravityX = alpha * gravityX + (1 - alpha) * x;
    gravityY = alpha * gravityY + (1 - alpha) * y;
    gravityZ = alpha * gravityZ + (1 - alpha) * z;
  }

  final dataList = <List<dynamic>>[
    [
      'timestamp',
      'x',
      'y',
      'z',
      'magnitude',
      'angle',
      'angleDiff',
      // 'variance',
      // 'peakInterval',
      'remark',
    ]
  ];

  void analyzeMovement() {
    _timer = Timer.periodic(Duration(milliseconds: 200), (Timer t) async {
      setState(() {
        final now = DateTime.now().toUtc();
        double variance = _calculateVariance(_accelerometerValues);
        double totalAcceleration =
            _accelerometerValues.map((v) => v.abs()).reduce((a, b) => a + b);
        magnitude = calculateMagnitude(_accelerometerValues[0],
            _accelerometerValues[1], _accelerometerValues[2]);
        previousMagnitude = magnitude;
        double peakInterval = calculatePeakInterval(_recentAccelerometerReadings);

        // Define thresholds
        double stillnessThreshold = 1.0; // Adjust as needed
        double bumpyThreshold = 2.0; // Adjust as needed
        double intentionalThreshold = 4.0; // Adjust as needed
        const double peakIntervalThreshold = 3.0;

        recentMagnitudes.add(magnitude);
        if (recentMagnitudes.length > windowSize) {
          recentMagnitudes.removeAt(0); // Keep only the last 10 values
        }

        // Check conditions
        if (magnitude < stillnessThreshold) {
          activity = 'Still';
        } else if (magnitude > bumpyThreshold &&
            variance > _threshold &&
            peakInterval < peakIntervalThreshold) {
          activity = 'Bumpy Road';
        } else {
          activity = 'Intentional Movement';
        }

        // save to csv
        dataList
            .add([now, x, y, z, magnitude, variance, peakInterval, activity]);
      });
    });
  }

  double _calculateVariance(List<double> values) {
    // double mean = values.reduce((a, b) => a + b) / values.length;
    // double sumSquaredDifferences = values
    //     .map((value) => (value - mean) * (value - mean))
    //     .reduce((a, b) => a + b);
    // return sumSquaredDifferences / values.length;

    if (values.isEmpty) return 0.0;

    double mean = values.reduce((a, b) => a + b) / values.length;
    double variance =
        values.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) /
            values.length;

    return variance;
  }

  double calculatePeakInterval(List<double> readings) {
    print('length:: ${readings.length}');
    List<double> peakIndices = [];

    // Identify peaks
    for (int i = 1; i < readings.length - 1; i++) {
      if (readings[i] > readings[i - 1] && readings[i] > readings[i + 1]) {
        peakIndices.add(readings[i]);
        print('newPeak:: ${readings[i]}');
      }
    }

    // Calculate intervals between peaks
    if (peakIndices.length < 2) {
      return double.infinity; // Not enough peaks to calculate intervals
    }

    List<double> intervals = [];
    for (int i = 1; i < peakIndices.length; i++) {
      // Calculate the interval in terms of indices
      double interval = peakIndices[i] - peakIndices[i - 1];
      intervals.add(interval);
    }

    // Return the average interval
    return intervals.reduce((a, b) => a + b) / intervals.length;
  }

  String _determineFinalStatus(List<String> data) {
    int moveCount = 0;

    for (String movement in data) {
      if (movement != 'Still') {
        moveCount++;
      }
    }

    if (moveCount >= 2) {
      return 'Movement detected';
    } else if (moveCount >= 6) {
      return 'Bumpy detected';
    } else  {
      return 'Still';
    }

    // // Step 1: Count occurrences
    // Map<String, int> counts = {};
    // for (var item in data) {
    //   counts[item] = (counts[item] ?? 0) + 1;
    // }
    //
    // // Step 2: Find the majority string
    // String majorityString = 'Still';
    // int maxCount = 0;
    //
    // counts.forEach((key, value) {
    //   if (value > maxCount) {
    //     maxCount = value;
    //     majorityString = key;
    //   }
    // });
    //
    // return majorityString;
  }
}
