import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    cargarNombreUsuario();
    cargarResumenTrabajo();
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
  Future<String?> mostrarDialogoTrabajo() async {
  TextEditingController mensajeController = TextEditingController();
  return await showDialog<String>(
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
          onPressed: () => Navigator.pop(context, null), // Cierra sin guardar
          child: const Text("Cancelar"),
        ),
        TextButton(
          onPressed: () {
            String mensaje = mensajeController.text.trim();
            if (mensaje.isNotEmpty) {
              Navigator.pop(context, mensaje);
            }
          },
          child: const Text("Guardar y fichar salida"),
        ),
      ],
    ),
  );
}

  Future<void> cargarNombreUsuario() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    setState(() {
      nombreUsuario = doc.data()?['name'] ?? 'Usuario';
    });
  }

  Future<void> cargarResumenTrabajo() async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final query = await userRef.collection('workSessions').get();

    int minutosDia = 0;
    int minutosSem = 0;

    final ahora = convertirHoraLocal(DateTime.now().toUtc());
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final comienzoSemana = hoy.subtract(Duration(days: hoy.weekday - 1));

    for (var doc in query.docs) {
      final data = doc.data();
      if (data['duration'] != null && data['duration'] is num && data['startTime'] is Timestamp) {
        final dur = (data['duration'] as num).toInt();
        final startTime = convertirHoraLocal((data['startTime'] as Timestamp).toDate());
        final fechaSolo = DateTime(startTime.year, startTime.month, startTime.day);

        if (fechaSolo == hoy) minutosDia += dur;
        if (!fechaSolo.isBefore(comienzoSemana)) minutosSem += dur;
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

  Future<void> ficharEntrada() async {
    startTime = convertirHoraLocal(DateTime.now().toUtc());
    final workDate = DateFormat('yyyy-MM-dd').format(startTime!);

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
  String? mensajeSalida = await mostrarDialogoTrabajo(); // Mostrar diálogo antes de salir

  if (mensajeSalida != null && mensajeSalida.isNotEmpty) {
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
        'workSummary': mensajeSalida, // Guardar el mensaje en Firestore
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
}


  Future<void> cerrarSesion() async {
    detenerContador();
    await FirebaseAuth.instance.signOut();
  }

  void iniciarContador() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        tiempoTrabajado = convertirHoraLocal(DateTime.now().toUtc()).difference(startTime!);
      });
    });
  }

  void detenerContador() {
    _timer?.cancel();
    _timer = null;
  }

  String formatearDuracion(Duration d) {
    final horas = d.inHours.toString().padLeft(2, '0');
    final minutos = (d.inMinutes % 60).toString().padLeft(2, '0');
    final segundos = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$horas:$minutos:$segundos';
  }

  @override
  Widget build(BuildContext context) {
    final texto = trabajando
        ? 'Trabajando desde las ${DateFormat.Hm().format(startTime!)}'
        : 'No estás trabajando';

    final progresoDiario = (minutosHoy / objetivoDiarioMinutos).clamp(0.0, 1.0);
    final progresoSemanal = (minutosSemana / objetivoSemanalMinutos).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text('Control de Horario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: cerrarSesion,
            tooltip: 'Cerrar sesión',
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green[300],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    nombreUsuario!.capitalize(),
                    style: const TextStyle(fontSize: 16, color: Colors.white),
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
                Text('Progreso diario (${(minutosHoy / 60).toStringAsFixed(1)}h / 8h)', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progresoDiario,
                  minHeight: 12,
                  backgroundColor: Colors.grey[300],
                  color: progresoDiario >= 1.0 ? Colors.amber : Colors.green,
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
                        child: Text('🎉 ¡Objetivo cumplido!',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Text('Progreso semanal (${(minutosSemana / 60).toStringAsFixed(1)}h / 40h)', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progresoSemanal,
                  minHeight: 12,
                  backgroundColor: Colors.grey[300],
                  color: progresoSemanal >= 1.0 ? Colors.blueAccent : Colors.indigo,
                  borderRadius: BorderRadius.circular(10),
                ),
                if (progresoSemanal >= 1.0)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Center(
                      child: Text('💪 ¡Semana completada!',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text(texto, style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic)),
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
                  border: Border.all(color: Colors.black.withOpacity(0.7), width: 4),
                  boxShadow: [
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
            trabajando ? formatearDuracion(tiempoTrabajado) : '00:00:00',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

extension StringCasingExtension on String {
  String capitalize() => '${this[0].toUpperCase()}${substring(1)}';
}
