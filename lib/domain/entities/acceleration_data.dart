// lib/domain/entities/acceleration_data.dart
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class AccelerationData {
  final double x, y, z;
  final double magnitude;
  final DateTime timestamp;
  final PoseLandmarkType landmarkType;

  AccelerationData({
    required this.x,
    required this.y,
    required this.z,
    required this.magnitude,
    required this.timestamp,
    required this.landmarkType,
  });
}
