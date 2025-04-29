// lib/screens/admin_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../theme.dart';
import 'login_screen.dart';
import 'user_reports_screen.dart';
import 'schedule_screen.dart';
import 'justificantes_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  Future<List<Map<String, dynamic>>> _loadUserStats() async {
    final usersSnapshot =
        await FirebaseFirestore.instance.collection('users').get();
    List<Map<String, dynamic>> userStats = [];

    for (var userDoc in usersSnapshot.docs) {
      final workSessionsSnapshot = await userDoc.reference
          .collection('workSessions')
          .orderBy('startTime', descending: true)
          .get();

      int totalMinutes = 0;
      DateTime? lastDate;
      for (var session in workSessionsSnapshot.docs) {
        final data = session.data();
        if (data['duration'] is num) {
          totalMinutes += (data['duration'] as num).toInt();
        }
        if (lastDate == null && data['startTime'] != null) {
          lastDate = (data['startTime'] as Timestamp).toDate();
        }
      }

      userStats.add({
        'userId': userDoc.id,
        'email': userDoc.data()['email'] ?? '(sin email)',
        'name': userDoc.data()['name'] ?? '(sin nombre)',
        'totalHours': (totalMinutes / 60).toStringAsFixed(2),
        'lastWorkDate': lastDate != null
            ? DateFormat('yyyy-MM-dd – HH:mm').format(lastDate)
            : 'Sin registros',
      });
    }

    return userStats;
  }

  Future<void> _cerrarSesion(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administración'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _cerrarSesion(context),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadUserStats(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data ?? [];
          if (users.isEmpty) {
            return const Center(child: Text('No hay datos de trabajadores.'));
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, idx) {
              final u = users[idx];
              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(u['name'][0].toUpperCase()),
                  ),
                  title: Text(u['name']),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Correo: ${u['email']}'),
                      Text('Total horas: ${u['totalHours']}'),
                      Text('Último fichaje: ${u['lastWorkDate']}'),
                    ],
                  ),
                  // 1️⃣ Al pulsar la tarjeta: ir a UserReportsScreen
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserReportsScreen(
                          userId: u['userId'],
                          userName: u['name'],
                        ),
                      ),
                    );
                  },
                  // 2️⃣ Botones para configurar horario y ver justificantes
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.schedule),
                        tooltip: 'Configurar horario',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ScheduleScreen(
                                userId: u['userId'],
                                userName: u['name'],
                                readOnly: false,
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.attach_file),
                        tooltip: 'Ver justificantes',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => JustificantesScreen(
                                userId: u['userId'],
                                userName: u['name'],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
