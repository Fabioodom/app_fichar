import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class UserReportsScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const UserReportsScreen({super.key, required this.userId, required this.userName});

  Future<List<Map<String, dynamic>>> _loadUserReports() async {
    final workSessionsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('workSessions')
        .orderBy('startTime', descending: true)
        .get();

    return workSessionsSnapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'startTime': data['startTime'] != null
            ? DateFormat('yyyy-MM-dd HH:mm').format((data['startTime'] as Timestamp).toDate())
            : 'Sin fecha',
        'endTime': data['endTime'] != null
            ? DateFormat('yyyy-MM-dd HH:mm').format((data['endTime'] as Timestamp).toDate())
            : 'Sin finalizar',
        'duration': data['duration'] != null ? '${data['duration']} min' : 'No registrado',
        'workSummary': data['workSummary'] ?? 'Sin resumen',
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Informes de $userName'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back), // Flecha para volver atrás
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadUserReports(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No hay informes disponibles.'));
          }

          final reports = snapshot.data!;

          return ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text('Fecha: ${report['startTime']} - ${report['endTime']}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Duración: ${report['duration']}'),
                      Text('Resumen: ${report['workSummary']}'),
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
