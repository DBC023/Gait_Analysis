// lib/domain/usecases/calculate_acceleration_usecase.dart

import 'dart:math';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../entities/acceleration_data.dart';

class CalculateAccelerationUseCase {
  // Buffer para almacenar posiciones anteriores
  final List<_LandmarkPosition> _positionHistory = [];
  static const int HISTORY_SIZE = 3; // Necesitamos al menos 3 puntos

  Future<AccelerationData?> execute(
    Pose pose,
    DateTime timestamp,
    PoseLandmarkType landmarkType,
  ) async {
    final landmark = pose.landmarks[landmarkType];
    if (landmark == null) return null;

    // Guardar posición actual
    _positionHistory.add(
      _LandmarkPosition(
        x: landmark.x,
        y: landmark.y,
        z: landmark.z,
        timestamp: timestamp,
      ),
    );

    // Mantener solo las últimas N posiciones
    if (_positionHistory.length > HISTORY_SIZE) {
      _positionHistory.removeAt(0);
    }

    // Necesitamos al menos 3 puntos para calcular aceleración
    if (_positionHistory.length < HISTORY_SIZE) return null;

    // Calcular velocidades entre puntos consecutivos
    final v1 = _calculateVelocity(_positionHistory[0], _positionHistory[1]);
    final v2 = _calculateVelocity(_positionHistory[1], _positionHistory[2]);

    // Calcular aceleración (cambio de velocidad / tiempo)
    final dt =
        _positionHistory[2].timestamp
            .difference(_positionHistory[1].timestamp)
            .inMilliseconds /
        1000.0;

    if (dt == 0) return null;

    final ax = (v2.x - v1.x) / dt;
    final ay = (v2.y - v1.y) / dt;
    final az = (v2.z - v1.z) / dt;

    // Magnitud de la aceleración
    final magnitude = _calculateMagnitude(ax, ay, az);

    return AccelerationData(
      x: ax,
      y: ay,
      z: az,
      magnitude: magnitude,
      timestamp: timestamp,
      landmarkType: landmarkType,
    );
  }

  _Velocity _calculateVelocity(_LandmarkPosition p1, _LandmarkPosition p2) {
    final dt = p2.timestamp.difference(p1.timestamp).inMilliseconds / 1000.0;
    if (dt == 0) return _Velocity(x: 0, y: 0, z: 0);

    return _Velocity(
      x: (p2.x - p1.x) / dt,
      y: (p2.y - p1.y) / dt,
      z: (p2.z - p1.z) / dt,
    );
  }

  double _calculateMagnitude(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  void reset() {
    _positionHistory.clear();
  }
}

class _LandmarkPosition {
  final double x, y, z;
  final DateTime timestamp;
  _LandmarkPosition({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  });
}

class _Velocity {
  final double x, y, z;
  _Velocity({required this.x, required this.y, required this.z});
}
