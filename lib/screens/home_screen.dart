// Dart core
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

// Flutter core
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Fechas y zonas horarias
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// Pantallas propias
import 'package:app_fichar/screens/schedule_screen.dart';

// Selección de ficheros
import 'package:file_picker/file_picker.dart';

// Envío de correos
import 'package:flutter_email_sender/flutter_email_sender.dart';

// Abrir URL / mailto:
import 'package:url_launcher/url_launcher.dart';

// Crear fichero temporal en móvil
import 'package:path_provider/path_provider.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  DateTime? startTime;
  bool trabajando = false;
  Timer? _timer;
  Duration tiempoTrabajado = Duration.zero;

  int minutosHoy = 0;
  int minutosSemana = 0;
  final int objetivoDiarioMinutos = 480;
  final int objetivoSemanalMinutos = 2400;

  AnimationController? _successController;
  final userId = FirebaseAuth.instance.currentUser!.uid;
  String? nombreUsuario;

  bool _ausenciaNotificado = false;

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    cargarNombreUsuario();
    cargarResumenTrabajo().then((_) {
      _chequearAusencia();
    });
  }

  @override
  void dispose() {
    detenerContador();
    _successController?.dispose();
    super.dispose();
  }

  DateTime convertirHoraLocal(DateTime utc) {
    final madrid = tz.getLocation('Europe/Madrid');
    return tz.TZDateTime.from(utc, madrid);
  }
  
   /// 1) Detecta ausencia y muestra opciones
  Future<void> _chequearAusencia() async {
    final ahora = convertirHoraLocal(DateTime.now().toUtc());
    final hoyKey = DateFormat('yyyy-MM-dd').format(ahora);

    final schedDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('schedule')
        .doc(hoyKey)
        .get();
    if (!schedDoc.exists) return;

    final startStr = schedDoc.data()?['start'] as String?;
    if (startStr == null) return;

    final parts = startStr.split(':');
    final sh = int.tryParse(parts[0]) ?? 0;
    final sm = int.tryParse(parts[1]) ?? 0;
    final scheduledStart = DateTime(ahora.year, ahora.month, ahora.day, sh, sm);

    if (ahora.isAfter(scheduledStart.add(const Duration(minutes: 15))) && !_ausenciaNotificado) {
      final sesionesHoy = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('workSessions')
          .where('workDate', isEqualTo: hoyKey)
          .get();
      if (sesionesHoy.docs.isEmpty) {
        _ausenciaNotificado = true;
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                const Text(
                  '¡No has fichado a tiempo!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Si tienes una incidencia, sube un justificante o envíalo por correo.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  /// 2a) Subida en-app a Firestore
  Future<void> _subirJustificanteFirestore() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg','png','pdf'],
      withData: true,
    );
    if (res == null) return;
    final file = res.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.length > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archivo demasiado grande o no válido.')),
      );
      return;
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('justificantes')
        .add({
      'fileName': file.name,
      'fileData': bytes,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Justificante guardado ✅')),
    );
  }

  /// 2b) Envío por correo con adjunto
  Future<void> _enviarJustificanteEmail() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg','png','pdf'],
      withData: true,
    );
    if (res == null) return;

    final file = res.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.length > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archivo demasiado grande o no válido.')),
      );
      return;
    }

    if (kIsWeb) {
      // En web usamos mailto sin adjunto en memoria
      final uri = Uri(
        scheme: 'mailto',
        path: 'admin@tuservidor.com',
        query: 'subject=Justificante&body=Adjunto mi justificante.',
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } else {
      // En móvil guardo temporalmente
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${file.name}';
      final f = File(filePath);
      await f.writeAsBytes(bytes);

      final email = Email(
        body: 'Adjunto mi justificante.',
        subject: 'Justificante de ausencia',
        recipients: ['admin@tuservidor.com'],
        attachmentPaths: [filePath],
        isHTML: false,
      );
      await FlutterEmailSender.send(email);
    }
  }
  Future<String?> mostrarDialogoTrabajo() async {
    final mensajeController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Escribe lo que has hecho"),
        content: TextField(
          controller: mensajeController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: "Ejemplo: Finalicé el informe de ventas...",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () {
              final mensaje = mensajeController.text.trim();
              if (mensaje.isNotEmpty) Navigator.pop(context, mensaje);
            },
            child: const Text("Guardar y fichar salida"),
          ),
        ],
      ),
    );
  }

  Future<void> cargarNombreUsuario() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    setState(() {
      nombreUsuario = doc.data()?['name'] ?? 'Usuario';
    });
  }

  Future<void> cargarResumenTrabajo() async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final query = await userRef.collection('workSessions').get();

    int minutosDia = 0, minutosSem = 0;
    final ahora = convertirHoraLocal(DateTime.now().toUtc());
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final comienzoSemana = hoy.subtract(Duration(days: hoy.weekday - 1));

    for (var doc in query.docs) {
      final data = doc.data();
      if (data['duration'] is num && data['startTime'] is Timestamp) {
        final dur = (data['duration'] as num).toInt();
        final st = convertirHoraLocal((data['startTime'] as Timestamp).toDate());
        final solo = DateTime(st.year, st.month, st.day);
        if (solo == hoy) minutosDia += dur;
        if (!solo.isBefore(comienzoSemana)) minutosSem += dur;
      }
    }

    if (minutosDia >= objetivoDiarioMinutos) {
      _successController?.forward(from: 0);
    }

    setState(() {
      minutosHoy = minutosDia;
      minutosSemana = minutosSem;
    });
  }

  static const int _toleranceMinutes = 15;

/// Muestra el diálogo de justificante y devuelve true si subiste uno
/// Muestra un bottom sheet y devuelve true si subió o envió justificante
Future<bool> _askJustificante() async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            const Text(
              '¡No has fichado a tiempo!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Si tienes una incidencia, sube un justificante para el administrador.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Subir justificante'),
              onPressed: () {
                Navigator.pop(context, true);
                _subirJustificanteFirestore();
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.email),
              label: const Text('Enviar por correo'),
              onPressed: () {
                Navigator.pop(context, true);
                _enviarJustificanteEmail();
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}


/// Modifica tu ficharEntrada() así:
Future<void> ficharEntrada() async {
  final ahora = convertirHoraLocal(DateTime.now().toUtc());
  final workDate = DateFormat('yyyy-MM-dd').format(ahora);

  // 1) Obtener horario previsto
  final schedDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('schedule')
      .doc(workDate)
      .get();

  if (schedDoc.exists) {
    final startStr = schedDoc.data()?['start'] as String?;
    if (startStr != null) {
      final parts = startStr.split(':');
      final sh = int.tryParse(parts[0]) ?? 0;
      final sm = int.tryParse(parts[1]) ?? 0;
      final scheduledStart = DateTime(ahora.year, ahora.month, ahora.day, sh, sm);

      // 2) Si pasaron 15 minutos y no has fichado, pide justificante
      if (ahora.isAfter(scheduledStart.add(const Duration(minutes: 15)))) {
        final ok = await _askJustificante();
        if (!ok) return; // sin justificante, no dejamos fichar
      }
    }
  }

  // 3) Sigue con el fichado normal
  startTime = ahora;
  final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
  final docSnap = await userRef.get();
  if (!docSnap.exists) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'desconocido';
    final provisionalName = email.split('@').first;
    await userRef.set({
      'email': email,
      'name': provisionalName,
      'role': 'worker',
    });
    setState(() => nombreUsuario = provisionalName);
  }

  await userRef.collection('workSessions').add({
    'startTime': startTime,
    'workDate': workDate,
    'endTime': null,
    'duration': null,
  });

  iniciarContador();
  setState(() => trabajando = true);
}

  Future<void> ficharSalida() async {
    final mensajeSalida = await mostrarDialogoTrabajo();
    if (mensajeSalida == null) return;

    final endTime = convertirHoraLocal(DateTime.now().toUtc());
    final duration = endTime.difference(startTime!).inMinutes;

    final query = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('workSessions')
        .where('endTime', isEqualTo: null)
        .orderBy('startTime', descending: true)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.update({
        'endTime': endTime,
        'duration': duration,
        'workSummary': mensajeSalida,
      });
    }

    detenerContador();
    setState(() {
      trabajando = false;
      startTime = null;
      tiempoTrabajado = Duration.zero;
    });
    await cargarResumenTrabajo();
  }

  Future<void> cerrarSesion() async {
    detenerContador();
    await FirebaseAuth.instance.signOut();
  }

  void iniciarContador() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        tiempoTrabajado = convertirHoraLocal(DateTime.now().toUtc())
            .difference(startTime!);
      });
    });
  }

  void detenerContador() {
    _timer?.cancel();
    _timer = null;
  }

  String formatearDuracion(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final texto = trabajando
        ? 'Trabajando desde las ${DateFormat.Hm().format(startTime!)}'
        : 'No estás trabajando';

    final progresoDiario =
        (minutosHoy / objetivoDiarioMinutos).clamp(0.0, 1.0);
    final progresoSemanal =
        (minutosSemana / objetivoSemanalMinutos).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text('Control de Horario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Ver mi horario',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScheduleScreen(
                    userId: userId,
                    userName: nombreUsuario,
                    readOnly: true,
                 ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: cerrarSesion,
          ),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (nombreUsuario != null)
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green[300],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    nombreUsuario!.capitalize(),
                    style: const TextStyle(
                        fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Progreso diario (${(minutosHoy / 60).toStringAsFixed(1)}h / 8h)',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progresoDiario,
                  minHeight: 12,
                  backgroundColor: Colors.grey[300],
                  color: progresoDiario >= 1.0
                      ? Colors.amber
                      : Colors.green,
                  borderRadius: BorderRadius.circular(10),
                ),
                if (progresoDiario >= 1.0)
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _successController!,
                      curve: Curves.easeOutBack,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Center(
                        child: Text(
                          '🎉 ¡Objetivo cumplido!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  'Progreso semanal (${(minutosSemana / 60).toStringAsFixed(1)}h / 40h)',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progresoSemanal,
                  minHeight: 12,
                  backgroundColor: Colors.grey[300],
                  color: progresoSemanal >= 1.0
                      ? Colors.blueAccent
                      : Colors.indigo,
                  borderRadius: BorderRadius.circular(10),
                ),
                if (progresoSemanal >= 1.0)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Center(
                      child: Text(
                        '💪 ¡Semana completada!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text(
            texto,
            style: const TextStyle(
                fontSize: 18, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 40),
          Center(
            child: GestureDetector(
              onTap: trabajando ? ficharSalida : ficharEntrada,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                      color: Colors.black.withOpacity(0.7), width: 4),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    trabajando ? Icons.stop : Icons.play_arrow,
                    size: 70,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text(
            trabajando
                ? formatearDuracion(tiempoTrabajado)
                : '00:00:00',
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

extension StringCasingExtension on String {
  String capitalize() =>
      '${this[0].toUpperCase()}${substring(1)}';
}
