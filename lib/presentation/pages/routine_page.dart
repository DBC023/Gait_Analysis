// lib/presentation/pages/vertical_jump_analysis_page.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/usecases/calculate_jump_height_usecase.dart';
import '../../data/repositories/mlkit_pose_detection_repository_impl.dart';
import '../../data/repositories/firestore_patient_data_repository_impl.dart';

import '../../domain/entities/vertical_jump_session.dart';
import '../../main.dart';
import '../widgets/optimized_pose_painter.dart';

class RoutinePage extends StatefulWidget {
  final String identification;
  final int week;
  const RoutinePage({
    Key? key,
    required this.identification,
    required this.week,
  }) : super(key: key);

  @override
  _RoutinePageState createState() => _RoutinePageState();
}

class _RoutinePageState extends State<RoutinePage> {
  // --- MÉTODOS DE CÁMARA E INICIALIZACIÓN (IDÉNTICOS AL ORIGINAL) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Center(child: const Text('Routine Page'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            "ROUTINE PAGE\n\nAthlete ID: ${widget.identification}\nWeek: ${widget.week}",
            style: const TextStyle(color: Colors.red, fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
