import 'dart:io' as io; // Import dart:io with a prefix
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(
    MaterialApp(
      home: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late FlutterVision vision;
  io.File? imageFile; // Use the io.File prefix here
  List<Map<String, dynamic>> yoloResults = [];
  int imageHeight = 1;
  int imageWidth = 1;
  bool isLoaded = false;

  @override
  void initState() {
    super.initState();
    vision = FlutterVision();
    loadYoloModels();
  }

  @override
  void dispose() async {
    super.dispose();
    await vision.closeTesseractModel();
    await vision.closeYoloModel();
  }

  Future<void> loadYoloModels() async {
    // Load first YOLO model
    await vision.loadYoloModel(
      labels: 'assets/labels.txt',
      modelPath: 'assets/new_shelf_18_May_float32.tflite',
      modelVersion: "yolov8",
      quantization: false,
      numThreads: 2,
      useGpu: true,
    );

    // Load second YOLO model
    await vision.loadYoloModel(
      labels: 'assets/labels.txt',
      modelPath: 'assets/pop_3_5_24_yolov8n_float32.tflite',
      modelVersion: "yolov8",
      quantization: false,
      numThreads: 2,
      useGpu: true,
    );

    setState(() {
      isLoaded = true;
    });
  }

  Future<void> pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.gallery);
    if (photo != null) {
      setState(() {
        imageFile = io.File(photo.path); // Use io.File here
        yoloResults.clear();
        isLoaded = false; // Reset the loaded state for a new image
      });
      await loadYoloModels(); // Load YOLO models for the new image
      await yoloOnImage(); // Automatically detect bounding boxes
    }
  }

  Future<void> yoloOnImage() async {
    if (imageFile == null) return;
    Uint8List byte = await imageFile!.readAsBytes();
    final image = await decodeImageFromList(byte);
    imageHeight = image.height;
    imageWidth = image.width;

    // Run YOLO model 1
    final result1 = await vision.yoloOnImage(
      bytesList: byte,
      imageHeight: image.height,
      imageWidth: image.width,
      iouThreshold: 0.5,
      confThreshold: 0.4,
      classThreshold: 0.5,
    );

    // Run YOLO model 2
    final result2 = await vision.yoloOnImage(
      bytesList: byte,
      imageHeight: image.height,
      imageWidth: image.width,
      iouThreshold: 0.5,
      confThreshold: 0.4,
      classThreshold: 0.5,
    );

    // Combine results
    final combinedResults = [...result1, ...result2];

    setState(() {
      yoloResults = combinedResults;
      isLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: task(),
      floatingActionButton: SpeedDial(
        icon: Icons.add_photo_alternate, // Icon to choose image
        backgroundColor: Colors.black12,
        foregroundColor: Colors.white,
        activeBackgroundColor: Colors.deepPurpleAccent,
        activeForegroundColor: Colors.white,
        visible: true,
        closeManually: false,
        curve: Curves.bounceIn,
        overlayColor: Colors.black,
        overlayOpacity: 0.5,
        buttonSize: const Size(56.0, 56.0),
        children: [
          SpeedDialChild(
            child: const Icon(Icons.add_photo_alternate),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            label: 'Pick an Image',
            labelStyle: const TextStyle(fontSize: 18.0),
            onTap: pickImage,
          ),
        ],
      ),
    );
  }

  Widget task() {
    if (imageFile == null) {
      return const Center(child: Text("Choose an Image"));
    }

    if (!isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(imageFile!), // Display chosen image
        ...displayBoxesAroundRecognizedObjects(MediaQuery.of(context).size),
      ],
    );
  }

  List<Widget> displayBoxesAroundRecognizedObjects(Size screen) {
    if (yoloResults.isEmpty) return [];

    double factorX = screen.width / imageWidth;
    double imgRatio = imageWidth / imageHeight;
    double newWidth = imageWidth * factorX;
    double newHeight = newWidth / imgRatio;
    double factorY = newHeight / imageHeight;
    double pady = (screen.height - newHeight) / 2;

    return yoloResults.map((result) {
      return Positioned(
        left: result["box"][0] * factorX,
        top: result["box"][1] * factorY + pady,
        width: (result["box"][2] - result["box"][0]) * factorX,
        height: (result["box"][3] - result["box"][1]) * factorY,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(10.0)),
            border: Border.all(color: const Color.fromARGB(255, 7, 157, 7), width: 2.0),
          ),
        ),
      );
    }).toList();
  }
}

class YoloVideo extends StatefulWidget {
  final FlutterVision vision;
  const YoloVideo({Key? key, required this.vision}) : super(key: key);

  @override
  State<YoloVideo> createState() => _YoloVideoState();
}

class _YoloVideoState extends State<YoloVideo> {
  late CameraController controller;
  late List<Map<String, dynamic>> yoloResults;
  CameraImage? cameraImage;
  bool isLoaded = false;
  bool isDetecting = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  init() async {
    var cameras = await availableCameras();
    controller = CameraController(cameras[0], ResolutionPreset.medium);
    controller.initialize().then((value) {
      loadYoloModels().then((value) {
        setState(() {
          isLoaded = true;
          isDetecting = false;
          yoloResults = [];
        });
      });
    });
  }

  @override
  void dispose() async {
    super.dispose();
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    if (!isLoaded) {
      return const Scaffold(
        body: Center(
          child: Text("Model not loaded, waiting for it"),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: CameraPreview(
            controller,
          ),
        ),
        ...displayBoxesAroundRecognizedObjects(size),
        Positioned(
          bottom: 75,
          width: MediaQuery.of(context).size.width,
          child: Container(
            height: 80,
            width: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  width: 5, color: Colors.white, style: BorderStyle.solid),
            ),
            child: isDetecting
                ? IconButton(
                    onPressed: () async {
                      stopDetection();
                    },
                    icon: const Icon(
                      Icons.stop,
                      color: Colors.red,
                    ),
                    iconSize: 50,
                  )
                : IconButton(
                    onPressed: () async {
                      await startDetection();
                    },
                    icon: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                    ),
                    iconSize: 50,
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> loadYoloModels() async {
    // Load first YOLO model
    await widget.vision.loadYoloModel(
      labels: 'assets/labels.txt',
      modelPath: 'assets/new_shelf_18_May_float32.tflite',
      modelVersion: "yolov8",
      numThreads: 2,
      useGpu: true,
    );

    // Load second YOLO model
    await widget.vision.loadYoloModel(
      labels: 'assets/labels.txt',
      modelPath: 'assets/pop_3_5_24_yolov8n_float32.tflite',
      modelVersion: "yolov8",
      numThreads: 2,
      useGpu: true,
    );

    setState(() {
      isLoaded = true;
    });
  }

  Future<void> yoloOnFrame(CameraImage cameraImage) async {
    // Run YOLO model 1
    final result1 = await widget.vision.yoloOnFrame(
      bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
      imageHeight: cameraImage.height,
      imageWidth: cameraImage.width,
      iouThreshold: 0.4,
      confThreshold: 0.4,
      classThreshold: 0.5,
    );

    // Run YOLO model 2
    final result2 = await widget.vision.yoloOnFrame(
      bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
      imageHeight: cameraImage.height,
      imageWidth: cameraImage.width,
      iouThreshold: 0.4,
      confThreshold: 0.4,
      classThreshold: 0.5,
    );

    // Combine results
    final combinedResults = [...result1, ...result2];

    if (combinedResults.isNotEmpty) {
      setState(() {
        yoloResults = combinedResults;
      });
    }
  }

  Future<void> startDetection() async {
    setState(() {
      isDetecting = true;
    });
    if (controller.value.isStreamingImages) {
      return;
    }
    await controller.startImageStream((image) async {
      if (isDetecting) {
        cameraImage = image;
        yoloOnFrame(image);
      }
    });
  }

  Future<void> stopDetection() async {
    setState(() {
      isDetecting = false;
      yoloResults.clear();
    });
  }

  List<Widget> displayBoxesAroundRecognizedObjects(Size screen) {
    if (yoloResults.isEmpty) return [];
    double factorX = screen.width / (cameraImage?.height ?? 1);
    double factorY = screen.height / (cameraImage?.width ?? 1);

    Color colorPick = const Color.fromARGB(255, 50, 233, 30);

    return yoloResults.map((result) {
      return Positioned(
        left: result["box"][0] * factorX,
        top: result["box"][1] * factorY,
        width: (result["box"][2] - result["box"][0]) * factorX,
        height: (result["box"][3] - result["box"][1]) * factorY,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(10.0)),
            border: Border.all(color: Colors.pink, width: 2.0),
          ),
          child: Text(
            "${result['tag']} ${(result['box'][4] * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              background: Paint()..color = colorPick,
              color: Colors.white,
              fontSize: 18.0,
            ),
          ),
        ),
      );
    }).toList();
  }
}

class PolygonPainter extends CustomPainter {
  final List<Map<String, double>> points;

  PolygonPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromARGB(129, 255, 2, 124)
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    final path = Path();
    if (points.isNotEmpty) {
      path.moveTo(points[0]['x']!, points[0]['y']!);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i]['x']!, points[i]['y']!);
      }
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
