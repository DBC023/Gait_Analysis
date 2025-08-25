// lib/presentation/pages/home_page.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/entities/patient_session.dart';
import '../../domain/usecases/calculate_angles_usecase.dart';
import '../../domain/usecases/save_patient_session_usecase.dart';
import '../../data/repositories/mlkit_pose_detection_repository_impl.dart';
import '../../data/repositories/firestore_patient_data_repository_impl.dart';
import '../../main.dart';
import '../widgets/optimized_pose_painter.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  String _errorMessage = '';
  late Size size;
  int frameCount = 1;
  double rightKneeAngle = 0;
  double leftKneeAngle = 0;
  double rightAnkleAngle = 0;
  double leftAnkleAngle = 0;
  double hipDropAngle = 0;
  String identification = "1002987699";

  late PoseDetector poseDetector;
  List<Pose>? _scanResults;
  CameraImage? img;
  bool isBusy = false;

  int _frameSkipCounter = 0;
  static const int FRAME_SKIP_COUNT =
      3; // Salta 2 fotogramas para procesamiento
  DateTime? _lastProcessTime;
  static const int MIN_PROCESS_INTERVAL_MS = 100;

  // Nuevas variables para controlar la frecuencia de guardado en Firestore
  int _frameSaveCounter = 0;
  static const int FRAME_SAVE_COUNT =
      10; // Guarda en Firestore cada 10 fotogramas

  late CalculateAnglesUseCase _calculateAnglesUseCase;
  late SavePatientSessionUseCase _savePatientSessionUseCase;
  late MLKitPoseDetectionRepositoryImpl _poseDetectionRepository;

  @override
  void initState() {
    super.initState();
    poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.accurate,
      ),
    );
    _poseDetectionRepository = MLKitPoseDetectionRepositoryImpl(poseDetector);
    _calculateAnglesUseCase = CalculateAnglesUseCase();
    _savePatientSessionUseCase = SavePatientSessionUseCase(
      FirestorePatientDataRepositoryImpl(FirebaseFirestore.instance),
    );
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) {
      setState(() {
        _errorMessage = 'No se encontraron cámaras disponibles.';
      });
      return;
    }

    _controller = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      imageFormatGroup:
          Platform.isAndroid
              ? ImageFormatGroup.nv21
              : ImageFormatGroup.bgra8888,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });

      _controller!.startImageStream((image) {
        if (_shouldSkipFrame()) return;

        if (!isBusy) {
          isBusy = true;
          img = image;
          _processFrameAsync();
        }
      });
    } on CameraException catch (e) {
      String errorText = 'Error al inicializar la cámara: ${e.description}';
      if (e.code == 'CameraAccessDenied') {
        errorText =
            'Acceso a la cámara denegado. Por favor, otorga los permisos en la configuración.';
      }
      setState(() {
        _errorMessage = errorText;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Ocurrió un error inesperado: $e';
      });
    }
  }

  bool _shouldSkipFrame() {
    _frameSkipCounter++;
    if (_frameSkipCounter < FRAME_SKIP_COUNT) {
      return true;
    }
    _frameSkipCounter = 0;

    final now = DateTime.now();
    if (_lastProcessTime != null) {
      final timeDiff = now.difference(_lastProcessTime!).inMilliseconds;
      if (timeDiff < MIN_PROCESS_INTERVAL_MS) {
        return true;
      }
    }
    _lastProcessTime = now;
    return false;
  }

  void _processFrameAsync() async {
    try {
      final inputImage = _inputImageFromCameraImage();
      if (inputImage == null) {
        isBusy = false;
        return;
      }

      final poses = await _poseDetectionRepository.detectPose(inputImage);

      if (poses.isNotEmpty && mounted) {
        final pose = poses.first;
        final angles = await _calculateAnglesUseCase.execute(pose);

        if (mounted) {
          setState(() {
            _scanResults = [pose];
            leftKneeAngle = angles.leftKnee;
            rightKneeAngle = angles.rightKnee;
            leftAnkleAngle = angles.leftAnkle;
            rightAnkleAngle = angles.rightAnkle;
            hipDropAngle = angles.hipDrop;
          });

          // Lógica para guardar en Firestore
          _frameSaveCounter++;
          if (_frameSaveCounter >= FRAME_SAVE_COUNT) {
            final patientSession = PatientSession(
              identification: identification,
              session: 2,
              frame: frameCount,
              leftAnkle: leftAnkleAngle,
              rightAnkle: rightAnkleAngle,
              leftKnee: leftKneeAngle,
              rightKnee: rightKneeAngle,
            );
            print("FIREBASE: Guardando sesión del paciente: $patientSession");
            await _savePatientSessionUseCase.execute(patientSession);
            frameCount++;
            _frameSaveCounter = 0; // Reinicia el contador de guardado
          }
        }
      } else if (mounted) {
        setState(() {
          _scanResults = null;
          leftKneeAngle = 0;
          rightKneeAngle = 0;
          leftAnkleAngle = 0;
          rightAnkleAngle = 0;
        });
      }
    } catch (e) {
      print('ERROR: Error processing frame (full pipeline): $e');
      if (e is Error) {
        print('Stack trace: ${e.stackTrace}');
      }
    } finally {
      isBusy = false;
    }
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _inputImageFromCameraImage() {
    if (img == null ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return null;
    }

    final camera = cameras[0];
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[_controller!.value.deviceOrientation];
      if (rotationCompensation == null) {
        return null;
      }

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) {
      return null;
    }

    InputImageFormat? inputFormat;
    Uint8List? bytes;

    if (Platform.isAndroid) {
      if (img!.format.raw == 35 && img!.planes.length == 3) {
        inputFormat = InputImageFormat.nv21;
        bytes = _concatenatePlanes(img!.planes);
      } else if (img!.format.raw == InputImageFormat.nv21.rawValue &&
          img!.planes.length == 1) {
        inputFormat = InputImageFormat.nv21;
        bytes = img!.planes.first.bytes;
      } else {
        return null;
      }
    } else if (Platform.isIOS) {
      if (img!.format.raw == 875708020 && img!.planes.length == 1) {
        inputFormat = InputImageFormat.bgra8888;
        bytes = img!.planes.first.bytes;
      } else {
        return null;
      }
    } else {
      return null;
    }

    if (bytes == null) {
      return null;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(img!.width.toDouble(), img!.height.toDouble()),
        rotation: rotation,
        format: inputFormat,
        bytesPerRow: img!.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final int width = img!.width;
    final int height = img!.height;
    final int totalBytes = width * height + (width * height ~/ 2);
    final Uint8List nv21Image = Uint8List(totalBytes);
    final Uint8List yPlane = planes[0].bytes;
    final int yRowStride = planes[0].bytesPerRow;
    final int uvRowStride = planes[1].bytesPerRow;
    final Uint8List uPlane = planes[1].bytes;
    final Uint8List vPlane = planes[2].bytes;
    int uvIndex = width * height;

    for (int y = 0; y < height; y++) {
      int yStart = y * yRowStride;
      nv21Image.setRange(
        y * width,
        (y + 1) * width,
        yPlane.sublist(yStart, yStart + width),
      );
      if (y % 2 == 0) {
        int uvStart = (y ~/ 2) * uvRowStride;
        for (int x = 0; x < width; x += 2) {
          nv21Image[uvIndex++] = vPlane[uvStart + x];
          nv21Image[uvIndex++] = uPlane[uvStart + x];
        }
      }
    }
    return nv21Image;
  }

  Widget buildResult() {
    if (_scanResults == null ||
        _scanResults!.isEmpty ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final Size imageSize = Size(
      _controller!.value.previewSize!.height,
      _controller!.value.previewSize!.width,
    );

    return CustomPaint(painter: OptimizedPosePainter(imageSize, _scanResults!));
  }

  @override
  void dispose() {
    _controller?.dispose();
    poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> stackChildren = [];
    size = MediaQuery.of(context).size;

    if (!_isCameraInitialized ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cargando...')),
        body: Center(
          child:
              _errorMessage.isNotEmpty
                  ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  )
                  : const CircularProgressIndicator(),
        ),
      );
    }

    stackChildren.add(
      Positioned(
        top: 0.0,
        left: 0.0,
        width: size.width,
        height: size.height,
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
          child: CameraPreview(_controller!),
        ),
      ),
    );

    stackChildren.add(
      Positioned(
        top: 0.0,
        left: 0.0,
        width: size.width,
        height: size.height,
        child: buildResult(),
      ),
    );

    stackChildren.add(
      Positioned(
        bottom: 40,
        left: 20,
        right: 20,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "ANGLES",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Left Knee: ${leftKneeAngle.toStringAsFixed(1)}°",
                    style: const TextStyle(color: Colors.green, fontSize: 16),
                  ),
                  Text(
                    "Right Knee: ${rightKneeAngle.toStringAsFixed(1)}°",
                    style: const TextStyle(color: Colors.yellow, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Left Ankle: ${leftAnkleAngle.toStringAsFixed(1)}°",
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  Text(
                    "Right Ankle: ${rightAnkleAngle.toStringAsFixed(1)}°",
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Hip Drop: ${hipDropAngle.toStringAsFixed(1)}°",
                    style: const TextStyle(color: Colors.cyan, fontSize: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      body: Container(
        margin: const EdgeInsets.only(top: 0),
        color: Colors.black,
        child: Stack(children: stackChildren),
      ),
    );
  }
}
