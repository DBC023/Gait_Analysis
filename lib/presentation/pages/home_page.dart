import 'package:bmapp/presentation/pages/acceleration_measure_page.dart';
import 'package:bmapp/presentation/pages/analysis_page.dart';
import 'package:bmapp/presentation/pages/routine_page.dart';
import 'package:bmapp/presentation/pages/vertical_jump_analysis_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para Numeric Input
//import 'analysis_page.dart'; // Asegúrate de que este import sea correcto
// import 'vertical_jump_page.dart'; // Descomentar cuando crees esta página

class HomePageController {
  final TextEditingController identificationController =
      TextEditingController();
  final TextEditingController sessionController = TextEditingController();
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final HomePageController _controller = HomePageController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.identificationController.dispose();
    _controller.sessionController.dispose();
    super.dispose();
  }

  // Lógica para Navegación al Análisis de Marcha
  void _startGaitAnalysis() {
    if (_formKey.currentState!.validate()) {
      final String id = _controller.identificationController.text;
      final int session = int.tryParse(_controller.sessionController.text) ?? 1;

      // Navegar a la pantalla de análisis pasando los parámetros
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => AnalysisPage(identification: id, session: session),
        ),
      );
    }
  }

  void _startVerticalJumpAnalysis() {
    // Agregar lógica si el Salto Vertical también necesita una ID

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => VerticalJumpAnalysisPage()),
    );
  }

  void _startAccelerationMeasure() {
    // Agregar lógica si el Salto Vertical también necesita una ID

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AccelerationMeasurePage()),
    );
  }

  void _startRoutinePage() {
    // Agregar lógica si el Salto Vertical también necesita una ID

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RoutinePage(identification: "55", week: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GAIT ANALYSIS DB'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Sección de Análisis de Marcha (Requiere Parámetros)
            _buildGaitAnalysisSection(),

            const SizedBox(height: 40),

            // Sección de Medición de Salto Vertical
            _buildVerticalJumpSection(),
            //Seccion de Medicion de Aceleracion
            const SizedBox(height: 40),
            _buildAccelerationMeasure(),
            const SizedBox(height: 40),
            _buildRoutineSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildGaitAnalysisSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '1. Gait Analysis',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),

              // Campo de Identificación
              TextFormField(
                controller: _controller.identificationController,
                decoration: const InputDecoration(
                  labelText: 'Patient ID',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a valid ID.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              // Campo de Sesión
              TextFormField(
                controller: _controller.sessionController,
                decoration: const InputDecoration(
                  labelText: 'Session Number',
                  border: OutlineInputBorder(),
                  hintText: 'Ej: 1, 2, 3...',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ], // Solo números
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a session number.';
                  }
                  if (int.tryParse(value) == null || int.parse(value) <= 0) {
                    return 'Muast be a positive integer.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Botón para iniciar Análisis de Marcha
              ElevatedButton.icon(
                onPressed: _startGaitAnalysis,
                icon: const Icon(Icons.directions_walk),
                label: const Text(
                  'Start Gait Analysis',
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalJumpSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '2. Vertical Jump Measurement',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            // Botón para iniciar Medición de Salto Vertical
            ElevatedButton.icon(
              onPressed: _startVerticalJumpAnalysis,
              icon: const Icon(Icons.height),
              label: const Text(
                'Measure Vertical Jump',
                style: TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, // Color diferente para distinguir
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccelerationMeasure() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '3. Acceleration Measurement',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            // Botón para iniciar Medición de Salto Vertical
            ElevatedButton.icon(
              onPressed: _startAccelerationMeasure,
              icon: const Icon(Icons.height),
              label: const Text(
                'Measure Acceleration',
                style: TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, // Color diferente para distinguir
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutineSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '4. Routine',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            // Botón para iniciar Medición de Salto Vertical
            ElevatedButton.icon(
              onPressed: _startRoutinePage,
              icon: const Icon(Icons.height),
              label: const Text('Routine Page', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, // Color diferente para distinguir
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
