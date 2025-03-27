import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

import 'login_screen.dart';
import 'user_reports_screen.dart'; // Importar la nueva pantalla

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  Future<List<Map<String, dynamic>>> _loadUserStats() async {
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
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
        if (data['duration'] != null && data['duration'] is num) {
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
            ? DateFormat('yyyy-MM-dd – kk:mm').format(lastDate)
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

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No hay datos de trabajadores.'));
          }

          final users = snapshot.data!;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(user['name'].toString().substring(0, 1).toUpperCase()),
                  ),
                  title: Text(user['name']),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Correo: ${user['email']}'),
                      Text('Total de horas: ${user['totalHours']}'),
                      Text('Último fichaje: ${user['lastWorkDate']}'),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserReportsScreen(
                          userId: user['userId'],
                          userName: user['name'],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
