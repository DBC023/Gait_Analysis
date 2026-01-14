import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../domain/usecases/calculate_acceleration_usecase.dart';
import '../../domain/entities/acceleration_data.dart';
import '../../main.dart';

// Clases auxiliares fuera del widget
class _WriteBuffer {
  final _BytesBuilder _buffer = _BytesBuilder();

  void putUint8List(List<int> list) {
    _buffer.add(list);
  }

  ByteData done() {
    final bytes = _buffer.toBytes();
    return ByteData.view(bytes.buffer);
  }
}

class _BytesBuilder {
  final List<int> _bytes = [];

  void add(List<int> bytes) {
    _bytes.addAll(bytes);
  }

  Uint8List toBytes() {
    return Uint8List.fromList(_bytes);
  }
}

class AccelerationMeasurePage extends StatefulWidget {
  const AccelerationMeasurePage({Key? key}) : super(key: key);

  @override
  State<AccelerationMeasurePage> createState() =>
      _AccelerationMeasurePageState();
}

class _AccelerationMeasurePageState extends State<AccelerationMeasurePage> {
  CameraController? _cameraController;
  late PoseDetector _poseDetector;
  late CalculateAccelerationUseCase _accelerationUseCase;

  bool _isDetecting = false;
  bool _isMeasuring = false;
  bool _isCameraInitialized = false;
  PoseLandmarkType _selectedLandmark = PoseLandmarkType.rightKnee;

  // Control de frecuencia de procesamiento
  int _frameCounter = 0;
  static const int PROCESS_EVERY_N_FRAMES = 3; // Procesar cada 3 frames (era 5)

  // Datos de aceleración
  final List<AccelerationData> _accelerationHistory = [];
  AccelerationData? _currentAcceleration;

  // Estadísticas
  double _maxAcceleration = 0;
  double _avgAcceleration = 0;
  double _minAcceleration = 0;

  // Conteo de repeticiones
  int _repetitionCount = 0;
  bool _isInMovement = false;
  double _currentRepMaxAcceleration = 0;
  final List<double> _repetitionPeaks = [];
  final List<int> _lowPerformanceReps = [];
  double _baselineAcceleration = 0;
  bool _showLowPerformanceAlert = false;
  int _alertRepNumber = 0;

  DateTime? _movementStartTime;
  static const int MIN_MOVEMENT_DURATION_MS = 300;
  static const double PIXELS_PER_METER = 1000.0;

  static const int MAX_HISTORY = 100;
  static const double MOVEMENT_THRESHOLD =
      20.0; // px/s² para detectar inicio de movimiento
  static const double REST_THRESHOLD =
      10.0; // px/s² para detectar fin de movimiento
  static const double PERFORMANCE_DROP_THRESHOLD = 0.20; // 20% de caída

  @override
  void initState() {
    super.initState();
    _initializePoseDetector();
    _accelerationUseCase = CalculateAccelerationUseCase();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) {
      debugPrint('No cameras available');
      return;
    }

    _cameraController = CameraController(
      cameras[1],
      ResolutionPreset.low, // Cambiar a low para mejor rendimiento
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid
              ? ImageFormatGroup.nv21
              : ImageFormatGroup.bgra8888,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;

      debugPrint('Camera initialized successfully');
      debugPrint('Preview size: ${_cameraController!.value.previewSize}');

      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  void _initializePoseDetector() {
    final options = PoseDetectorOptions(
      model: PoseDetectionModel.accurate,
      mode: PoseDetectionMode.stream,
    );
    _poseDetector = PoseDetector(options: options);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    // Saltar frames para mejorar rendimiento
    _frameCounter++;
    if (_frameCounter % PROCESS_EVERY_N_FRAMES != 0) {
      return;
    }

    if (_isDetecting) return;

    if (!_isMeasuring) {
      debugPrint('No está midiendo, saltando frame');
      return;
    }

    _isDetecting = true;

    try {
      final inputImage = _convertToInputImage(image);
      if (inputImage == null) {
        debugPrint('Failed to convert image to InputImage');
        _isDetecting = false;
        return;
      }

      final poses = await _poseDetector.processImage(inputImage);

      if (poses.isNotEmpty && mounted) {
        final pose = poses.first;
        final timestamp = DateTime.now();

        // Verificar si el landmark existe
        final landmark = pose.landmarks[_selectedLandmark];
        if (landmark != null) {
          // Calcular aceleración
          final acceleration = await _accelerationUseCase.execute(
            pose,
            timestamp,
            _selectedLandmark,
          );

          if (acceleration != null && mounted) {
            setState(() {
              _currentAcceleration = acceleration;
              _accelerationHistory.add(acceleration);

              // Mantener historial limitado
              if (_accelerationHistory.length > MAX_HISTORY) {
                _accelerationHistory.removeAt(0);
              }

              // Actualizar estadísticas
              _updateStatistics();
              _detectRepetition(acceleration.magnitude);
            });

            if (_accelerationHistory.length % 10 == 0) {
              debugPrint(
                'Datos recopilados: ${_accelerationHistory.length}, última magnitud: ${acceleration.magnitude.toStringAsFixed(2)}',
              );
            }
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error processing image: $e');
      if (_frameCounter % 50 == 0) {
        // Solo mostrar cada 50 frames para no saturar
        debugPrint('Stack trace: $stackTrace');
      }
    } finally {
      _isDetecting = false;
    }
  }

  InputImage? _convertToInputImage(CameraImage image) {
    try {
      final camera = cameras[0];
      final sensorOrientation = camera.sensorOrientation;
      InputImageRotation? rotation;

      if (Platform.isIOS) {
        rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
      } else if (Platform.isAndroid) {
        var rotationCompensation =
            _orientations[_cameraController!.value.deviceOrientation];
        if (rotationCompensation == null) return null;

        if (camera.lensDirection == CameraLensDirection.front) {
          rotationCompensation =
              (sensorOrientation + rotationCompensation) % 360;
        } else {
          rotationCompensation =
              (sensorOrientation - rotationCompensation + 360) % 360;
        }
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      }

      if (rotation == null) return null;

      InputImageFormat? inputFormat;
      Uint8List? bytes;

      if (Platform.isAndroid) {
        if (image.format.raw == 35 && image.planes.length == 3) {
          inputFormat = InputImageFormat.nv21;
          bytes = _concatenatePlanes(image.planes);
        } else if (image.format.raw == InputImageFormat.nv21.rawValue &&
            image.planes.length == 1) {
          inputFormat = InputImageFormat.nv21;
          bytes = image.planes.first.bytes;
        }
      } else if (Platform.isIOS) {
        if (image.format.raw == 875708020 && image.planes.length == 1) {
          inputFormat = InputImageFormat.bgra8888;
          bytes = image.planes.first.bytes;
        }
      }

      if (bytes == null || inputFormat == null) return null;

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: inputFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('Error converting image: $e');
      return null;
    }
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final _WriteBuffer allBytes = _WriteBuffer();
    for (final Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  void _updateStatistics() {
    if (_accelerationHistory.isEmpty) return;

    final magnitudes = _accelerationHistory.map((a) => a.magnitude).toList();

    _maxAcceleration = magnitudes.reduce((a, b) => a > b ? a : b);
    _minAcceleration = magnitudes.reduce((a, b) => a < b ? a : b);
    _avgAcceleration = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
  }

  void _detectRepetition(double magnitude) {
    // Detectar inicio de movimiento (aceleración supera el umbral)
    if (!_isInMovement && magnitude > MOVEMENT_THRESHOLD) {
      _isInMovement = true;
      _movementStartTime = DateTime.now();
      _currentRepMaxAcceleration = magnitude;
      debugPrint('🏋️ Inicio de repetición detectado');
    }

    // Durante el movimiento, rastrear el pico de aceleración
    if (_isInMovement) {
      if (magnitude > _currentRepMaxAcceleration) {
        _currentRepMaxAcceleration = magnitude;
      }

      // Detectar fin de movimiento (aceleración cae bajo el umbral de reposo)
      if (magnitude < REST_THRESHOLD) {
        if (_movementStartTime != null &&
            DateTime.now().difference(_movementStartTime!).inMilliseconds <
                MIN_MOVEMENT_DURATION_MS) {
          _isInMovement = false;
          return; // Movimiento muy corto, ignorar
        }
        _isInMovement = false;
        _repetitionCount++;

        // Guardar el pico de esta repetición
        _repetitionPeaks.add(_currentRepMaxAcceleration);

        debugPrint(
          '✅ Repetición #$_repetitionCount completada. Pico: ${_currentRepMaxAcceleration.toStringAsFixed(2)} px/s²',
        );

        // Establecer baseline con las primeras 3 repeticiones
        if (_repetitionCount == 3 && _baselineAcceleration == 0) {
          _baselineAcceleration =
              _repetitionPeaks.reduce((a, b) => a + b) /
              _repetitionPeaks.length;
          debugPrint(
            '📊 Baseline establecido: ${_baselineAcceleration.toStringAsFixed(2)} px/s²',
          );
        }

        // Verificar caída de rendimiento (después de establecer baseline)
        if (_repetitionCount > 3 && _baselineAcceleration > 0) {
          final dropPercentage =
              (_baselineAcceleration - _currentRepMaxAcceleration) /
              _baselineAcceleration;

          if (dropPercentage >= PERFORMANCE_DROP_THRESHOLD) {
            _lowPerformanceReps.add(_repetitionCount);
            _alertRepNumber = _repetitionCount;
            _showLowPerformanceAlert = true;

            debugPrint(
              '⚠️ ALERTA: Caída de rendimiento del ${(dropPercentage * 100).toStringAsFixed(1)}% en repetición #$_repetitionCount',
            );

            // Ocultar alerta después de 3 segundos
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _showLowPerformanceAlert = false;
                });
              }
            });
          }
        }

        // Resetear para la próxima repetición
        _currentRepMaxAcceleration = 0;
      }
    }
  }

  void _toggleMeasurement() async {
    if (_isMeasuring) {
      // Detener medición
      await _cameraController?.stopImageStream();
      setState(() {
        _isMeasuring = false;
      });
      debugPrint('Medición detenida');
    } else {
      // Iniciar medición
      setState(() {
        _isMeasuring = true;
      });
      debugPrint('Iniciando medición...');

      try {
        await _cameraController?.startImageStream((CameraImage image) {
          _processCameraImage(image);
        });
        debugPrint('Stream de imágenes iniciado correctamente');
      } catch (e) {
        debugPrint('Error al iniciar stream: $e');
        setState(() {
          _isMeasuring = false;
        });
      }
    }
  }

  void _resetMeasurement() {
    setState(() {
      _accelerationHistory.clear();
      _currentAcceleration = null;
      _maxAcceleration = 0;
      _avgAcceleration = 0;
      _minAcceleration = 0;
      _repetitionCount = 0;
      _isInMovement = false;
      _currentRepMaxAcceleration = 0;
      _repetitionPeaks.clear();
      _lowPerformanceReps.clear();
      _baselineAcceleration = 0;
      _showLowPerformanceAlert = false;
      _alertRepNumber = 0;
      _movementStartTime = null;
      _accelerationUseCase.reset();
    });
  }

  void _changeLandmark(PoseLandmarkType? newLandmark) {
    if (newLandmark != null) {
      setState(() {
        _selectedLandmark = newLandmark;
        _resetMeasurement();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medición de Aceleración'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetMeasurement,
            tooltip: 'Reiniciar',
          ),
        ],
      ),
      body:
          !_isCameraInitialized ||
                  _cameraController == null ||
                  !_cameraController!.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  // Vista de cámara
                  Expanded(
                    flex: 2,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AspectRatio(
                          aspectRatio: _cameraController!.value.aspectRatio,
                          child: CameraPreview(_cameraController!),
                        ),
                        if (_isMeasuring)
                          Positioned(
                            top: 16,
                            left: 16,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.fiber_manual_record,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'MIDIENDO',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Frames: $_frameCounter',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Contador de repeticiones
                        if (_isMeasuring)
                          Positioned(
                            top: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.fitness_center,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$_repetitionCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text(
                                    'REPS',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Alerta de bajo rendimiento
                        if (_showLowPerformanceAlert)
                          Positioned(
                            top: 100,
                            left: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black,
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '⚠️ CAÍDA DE RENDIMIENTO',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Repetición #$_alertRepNumber - Reducción >20%',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Considera descansar o reducir carga',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Selector de articulación
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.grey[200],
                    child: Row(
                      children: [
                        const Text(
                          'Articulación:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButton<PoseLandmarkType>(
                            value: _selectedLandmark,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(
                                value: PoseLandmarkType.rightKnee,
                                child: Text('Rodilla Derecha'),
                              ),
                              DropdownMenuItem(
                                value: PoseLandmarkType.leftKnee,
                                child: Text('Rodilla Izquierda'),
                              ),
                              DropdownMenuItem(
                                value: PoseLandmarkType.rightAnkle,
                                child: Text('Tobillo Derecho'),
                              ),
                              DropdownMenuItem(
                                value: PoseLandmarkType.leftAnkle,
                                child: Text('Tobillo Izquierdo'),
                              ),
                              DropdownMenuItem(
                                value: PoseLandmarkType.rightWrist,
                                child: Text('Muñeca Derecha'),
                              ),
                              DropdownMenuItem(
                                value: PoseLandmarkType.leftWrist,
                                child: Text('Muñeca Izquierda'),
                              ),
                            ],
                            onChanged: _isMeasuring ? null : _changeLandmark,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Datos actuales
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aceleración Actual',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_currentAcceleration != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildAccelerationValue(
                                'X',
                                _currentAcceleration!.x,
                                Colors.red,
                              ),
                              _buildAccelerationValue(
                                'Y',
                                _currentAcceleration!.y,
                                Colors.green,
                              ),
                              _buildAccelerationValue(
                                'Z',
                                _currentAcceleration!.z,
                                Colors.blue,
                              ),
                              _buildAccelerationValue(
                                'Mag',
                                _currentAcceleration!.magnitude,
                                Colors.purple,
                              ),
                            ],
                          )
                        else
                          const Center(
                            child: Text(
                              'Sin datos',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Estadísticas
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.grey[100],
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatistic(
                              'Máx',
                              _maxAcceleration,
                              Colors.red,
                            ),
                            _buildStatistic(
                              'Prom',
                              _avgAcceleration,
                              Colors.orange,
                            ),
                            _buildStatistic(
                              'Mín',
                              _minAcceleration,
                              Colors.green,
                            ),
                          ],
                        ),
                        if (_repetitionCount > 0) ...[
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildRepStatistic(
                                'Repeticiones',
                                _repetitionCount.toString(),
                                Icons.fitness_center,
                                Colors.teal,
                              ),
                              if (_baselineAcceleration > 0)
                                _buildRepStatistic(
                                  'Baseline',
                                  (_baselineAcceleration / PIXELS_PER_METER)
                                      .toStringAsFixed(2),
                                  Icons.timeline,
                                  Colors.blue,
                                ),
                              if (_lowPerformanceReps.isNotEmpty)
                                _buildRepStatistic(
                                  'Alertas',
                                  _lowPerformanceReps.length.toString(),
                                  Icons.warning,
                                  Colors.orange,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Gráfica
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          _accelerationHistory.length < 2
                              ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.show_chart,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _isMeasuring
                                          ? 'Recopilando datos...\n${_accelerationHistory.length} puntos'
                                          : 'Inicia la medición para ver la gráfica',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              : CustomPaint(
                                painter: AccelerationChartPainter(
                                  _accelerationHistory,
                                  pixelsPerMeter: PIXELS_PER_METER,
                                ),
                                child: Container(),
                              ),
                    ),
                  ),

                  // Botón de control
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _toggleMeasurement,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isMeasuring ? Colors.red : Colors.teal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isMeasuring ? 'DETENER' : 'INICIAR MEDICIÓN',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildAccelerationValue(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          (value / PIXELS_PER_METER).toStringAsFixed(2),
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'm/s²',
          style: TextStyle(color: color.withOpacity(0.7), fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildStatistic(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          (value / PIXELS_PER_METER).toStringAsFixed(2),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildRepStatistic(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  @override
  void dispose() {
    _cameraController
        ?.stopImageStream()
        .then((_) {
          _cameraController?.dispose();
        })
        .catchError((e) {
          debugPrint('Error stopping stream: $e');
          _cameraController?.dispose();
        });
    _poseDetector.close();
    super.dispose();
  }
}

// Custom Painter para la gráfica de aceleración
class AccelerationChartPainter extends CustomPainter {
  final List<AccelerationData> data;
  final double pixelsPerMeter;

  AccelerationChartPainter(this.data, {this.pixelsPerMeter = 1000.0});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    // Configuración de pinturas
    final linePaint =
        Paint()
          ..color = Colors.purple
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final fillPaint =
        Paint()
          ..color = Colors.purple.withOpacity(0.1)
          ..style = PaintingStyle.fill;

    final gridPaint =
        Paint()
          ..color = Colors.grey.withOpacity(0.3)
          ..strokeWidth = 1.0;

    final axisPaint =
        Paint()
          ..color = Colors.black87
          ..strokeWidth = 2.0;

    final pointPaint =
        Paint()
          ..color = Colors.purple
          ..style = PaintingStyle.fill;

    // Márgenes
    const margin = 50.0;
    final chartWidth = size.width - 2 * margin;
    final chartHeight = size.height - 2 * margin;

    // Fondo blanco
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // Dibujar ejes
    canvas.drawLine(
      Offset(margin, size.height - margin),
      Offset(size.width - margin, size.height - margin),
      axisPaint,
    );
    canvas.drawLine(
      Offset(margin, margin),
      Offset(margin, size.height - margin),
      axisPaint,
    );

    // Encontrar valores máximo y mínimo
    double maxValue = data
        .map((d) => d.magnitude)
        .reduce((a, b) => a > b ? a : b);
    double minValue = data
        .map((d) => d.magnitude)
        .reduce((a, b) => a < b ? a : b);

    // Añadir padding vertical
    final range = maxValue - minValue;
    if (range < 0.1) {
      maxValue += 0.5;
      minValue -= 0.5;
    } else {
      maxValue += range * 0.1;
      minValue -= range * 0.1;
    }

    // Dibujar líneas de grid horizontales
    for (int i = 0; i <= 5; i++) {
      final y = margin + (chartHeight / 5) * i;
      canvas.drawLine(
        Offset(margin, y),
        Offset(size.width - margin, y),
        gridPaint,
      );
    }

    // Dibujar líneas de grid verticales
    for (int i = 0; i <= 4; i++) {
      final x = margin + (chartWidth / 4) * i;
      canvas.drawLine(
        Offset(x, margin),
        Offset(x, size.height - margin),
        gridPaint,
      );
    }

    // Crear path para la línea y el área
    final linePath = Path();
    final fillPath = Path();
    bool isFirstPoint = true;

    final points = <Offset>[];

    for (int i = 0; i < data.length; i++) {
      final x = margin + (chartWidth / (data.length - 1)) * i;
      final normalizedValue =
          (data[i].magnitude - minValue) / (maxValue - minValue);
      final y = size.height - margin - (normalizedValue * chartHeight);

      points.add(Offset(x, y));

      if (isFirstPoint) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height - margin);
        fillPath.lineTo(x, y);
        isFirstPoint = false;
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Cerrar el área de relleno
    if (points.isNotEmpty) {
      fillPath.lineTo(points.last.dx, size.height - margin);
      fillPath.close();
      canvas.drawPath(fillPath, fillPaint);
    }

    // Dibujar la línea
    canvas.drawPath(linePath, linePaint);

    // Dibujar puntos
    for (final point in points) {
      canvas.drawCircle(point, 3, pointPaint);
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
    }

    // Dibujar valores en el eje Y
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i <= 5; i++) {
      final value = minValue + (maxValue - minValue) * (1 - i / 5);
      final y = margin + (chartHeight / 5) * i;

      textPainter.text = TextSpan(
        text: (value / pixelsPerMeter).toStringAsFixed(2),
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(5, y - 7));
    }

    // Etiqueta del eje Y
    textPainter.text = const TextSpan(
      text: 'Aceleración (m/s²)',
      style: TextStyle(
        color: Colors.black87,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
    textPainter.layout();
    canvas.save();
    canvas.translate(15, size.height / 2 + textPainter.width / 2);
    canvas.rotate(-1.5708); // -90 grados en radianes
    textPainter.paint(canvas, Offset.zero);
    canvas.restore();

    // Etiqueta del eje X
    textPainter.text = const TextSpan(
      text: 'Tiempo',
      style: TextStyle(
        color: Colors.black87,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(size.width / 2 - textPainter.width / 2, size.height - 20),
    );
  }

  @override
  bool shouldRepaint(AccelerationChartPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
