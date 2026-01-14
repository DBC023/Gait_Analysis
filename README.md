# Gait Analysis App

Una aplicación móvil desarrollada en Flutter para el análisis de marcha en tiempo real mediante detección de pose y cálculo de ángulos articulares.

## 📋 Descripción

Esta aplicación utiliza ML Kit Pose Detection de Google para capturar y analizar el movimiento humano durante la marcha. Calcula automáticamente los ángulos de rodillas, tobillos y la inclinación de cadera, almacenando los datos en Firebase Firestore para su posterior análisis.

## ✨ Características Principales

- **Detección de Pose en Tiempo Real**: Utiliza Google ML Kit para identificar puntos clave del cuerpo humano
- **Cálculo de Ángulos Articulares**: 
  - Ángulo de rodilla izquierda y derecha
  - Ángulo de tobillo izquierdo y derecho
  - Ángulo de inclinación de cadera (hip drop)
- **Visualización en Vivo**: Overlay gráfico que muestra el esqueleto detectado sobre la imagen de la cámara
- **Almacenamiento en la Nube**: Guarda los datos de sesión en Firebase Firestore
- **Optimización de Rendimiento**: 
  - Frame skipping para reducir la carga de procesamiento
  - Guardado selectivo cada 10 frames procesados
  - Procesamiento asíncrono de imágenes

## 🏗️ Arquitectura

El proyecto sigue principios de **Clean Architecture** con la siguiente estructura:

```
lib/
├── domain/
│   ├── entities/          # Entidades del dominio (PoseData, PatientSession, AngleData)
│   ├── repositories/      # Interfaces de repositorios
│   └── usecases/          # Casos de uso (CalculateAngles, SavePatientSession)
├── data/
│   ├── models/            # Modelos de datos
│   └── repositories/      # Implementaciones de repositorios
└── presentation/
    ├── pages/             # Páginas de la aplicación
    └── widgets/           # Widgets personalizados (OptimizedPosePainter)
```

### Capas de la Arquitectura

1. **Domain Layer**: Contiene la lógica de negocio pura
   - `PoseData`: Entidad que encapsula los datos de una pose detectada
   - `PatientSession`: Entidad para datos de sesión del paciente
   - `AngleData`: Entidad para almacenar ángulos calculados
   - `CalculateAnglesUseCase`: Lógica para calcular ángulos entre articulaciones
   - `SavePatientSessionUseCase`: Lógica para guardar sesiones de pacientes

2. **Data Layer**: Implementaciones concretas y acceso a datos
   - `MLKitPoseDetectionRepositoryImpl`: Implementación usando ML Kit
   - `FirestorePatientDataRepositoryImpl`: Implementación usando Firestore

3. **Presentation Layer**: UI y lógica de presentación
   - `MyHomePage`: Página principal con cámara y análisis en tiempo real
   - `VideoPlaybackPage`: Reproducción de videos con overlay de poses
   - `OptimizedPosePainter`: Widget personalizado para dibujar el esqueleto

## 🛠️ Tecnologías Utilizadas

- **Flutter**: Framework de desarrollo móvil multiplataforma
- **Dart**: Lenguaje de programación
- **Firebase Core**: Integración con servicios de Firebase
- **Cloud Firestore**: Base de datos NoSQL para almacenamiento
- **Google ML Kit Pose Detection**: Detección de pose en tiempo real
- **Camera Plugin**: Acceso a la cámara del dispositivo
- **Video Player**: Reproducción de videos grabados
- **Provider**: Gestión de estado (disponible pero no implementada aún)
- **Path Provider**: Acceso al sistema de archivos
- **Permission Handler**: Gestión de permisos

## 📦 Dependencias

```yaml
dependencies:
  flutter:
    sdk: flutter
  camera: ^0.11.1
  google_mlkit_pose_detection: ^0.14.0
  firebase_core: ^3.15.2
  cloud_firestore: ^5.6.12
  provider: ^6.1.5
  path_provider: ^2.1.5
  video_player: ^2.10.0
  permission_handler: ^12.0.1
```

## 🚀 Instalación

1. **Clonar el repositorio**
   ```bash
   git clone <repository-url>
   cd bmapp
   ```

2. **Instalar dependencias**
   ```bash
   flutter pub get
   ```

3. **Configurar Firebase**
   - Crear un proyecto en [Firebase Console](https://console.firebase.google.com/)
   - Descargar `google-services.json` (Android) y `GoogleService-Info.plist` (iOS)
   - Ejecutar FlutterFire CLI:
     ```bash
     flutterfire configure
     ```

4. **Configurar permisos**

   **Android** (`android/app/src/main/AndroidManifest.xml`):
   ```xml
   <uses-permission android:name="android.permission.CAMERA"/>
   <uses-permission android:name="android.permission.INTERNET"/>
   ```

   **iOS** (`ios/Runner/Info.plist`):
   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Esta app necesita acceso a la cámara para detectar poses</string>
   ```

5. **Ejecutar la aplicación**
   ```bash
   flutter run
   ```

## 💻 Uso

### Análisis en Tiempo Real

1. Abre la aplicación
2. Concede permisos de cámara
3. Posiciona al sujeto en el campo de visión
4. La aplicación automáticamente:
   - Detecta la pose
   - Calcula los ángulos articulares
   - Muestra el overlay del esqueleto
   - Guarda datos en Firestore cada 10 frames

### Datos Guardados

Los datos se almacenan en Firestore bajo la colección `data_patients` con el siguiente formato:

```json
{
  "identification": "1002987699",
  "session": 2,
  "frame": 1,
  "leftankle": 85.3,
  "rightankle": 87.1,
  "leftknee": 145.2,
  "rightknee": 143.8
}
```

## 📊 Cálculo de Ángulos

### Ángulo de Rodilla
Calculado entre los puntos: **Cadera → Rodilla → Tobillo**

### Ángulo de Tobillo
Calculado entre los puntos: **Rodilla → Tobillo → Talón**

### Hip Drop (Inclinación de Cadera)
Calculado como el ángulo de desviación de la línea de cadera respecto a la horizontal.

## ⚙️ Configuración de Rendimiento

### Frame Skipping
```dart
static const int FRAME_SKIP_COUNT = 3;  // Procesa 1 de cada 3 frames
```

### Intervalo Mínimo de Procesamiento
```dart
static const int MIN_PROCESS_INTERVAL_MS = 100;  // 100ms entre procesamiento
```

### Frecuencia de Guardado en Firestore
```dart
static const int FRAME_SAVE_COUNT = 10;  // Guarda cada 10 frames procesados
```

## 🎨 Personalización

### Colores del Overlay
En `OptimizedPosePainter`:
- **Verde**: Extremidades izquierdas
- **Amarillo**: Extremidades derechas
- **Azul**: Línea de cadera

### Resolución de Cámara
En `home_page.dart`:
```dart
ResolutionPreset.medium  // Opciones: low, medium, high, veryHigh
```

## 🔧 Solución de Problemas

### La cámara no se inicializa
- Verifica que los permisos estén concedidos
- Asegúrate de que `cameras` está disponible en `main.dart`
- Revisa los logs para errores específicos

### Detección de pose lenta
- Reduce la resolución de la cámara
- Aumenta `FRAME_SKIP_COUNT`
- Usa `PoseDetectionMode.stream` en lugar de `single`

### Error al guardar en Firestore
- Verifica la configuración de Firebase
- Comprueba las reglas de seguridad en Firestore
- Revisa la conexión a internet

## 📝 Estructura de Datos

### PoseData
```dart
class PoseData {
  final DateTime timestamp;
  final Map<PoseLandmarkType, PoseLandmark> landmarks;
  final double leftKneeAngle;
  final double rightKneeAngle;
  final double leftAnkleAngle;
  final double rightAnkleAngle;
}
```

### PatientSession
```dart
class PatientSession {
  final String identification;
  final int session;
  final int frame;
  final double leftAnkle;
  final double rightAnkle;
  final double leftKnee;
  final double rightKnee;
}
```

## 📄 Licencia

Este proyecto es parte de un proyecto de base de datos para análisis de marcha.

## 👥 Damian

- Proyecto desarrollado como prototipo de análisis de marcha

## 🔮 Mejoras Futuras

- [ ] Implementar grabación de video con overlay
- [ ] Análisis comparativo entre sesiones
- [ ] Exportación de datos a CSV/Excel
- [ ] Gráficos de evolución temporal
- [ ] Detección automática de ciclos de marcha
- [ ] Machine Learning para clasificación de patrones
- [ ] Modo offline con sincronización posterior
- [ ] Interfaz de administración web
- [ ] Reportes PDF automatizados
- [ ] Integración con dispositivos wearables


Para reportar problemas o solicitar características, por favor abre un issue en el repositorio del proyecto.

---

**Versión**: 1.0.0+1  
**Última actualización**: 2025  
**Estado**: Prototipo en desarrollo
