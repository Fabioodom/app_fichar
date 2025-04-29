// lib/screens/justificantes_screen.dart

import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;       // Para web
import 'package:path_provider/path_provider.dart';       // Para móvil
import 'package:open_file/open_file.dart';               // Para móvil

class JustificantesScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const JustificantesScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  Future<List<Map<String, dynamic>>> _loadJustificantes() async {
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('justificantes')
      .orderBy('uploadedAt', descending: true)
      .get();

  return snap.docs.map((d) {
    final data = d.data();
    final ts = data['uploadedAt'] as Timestamp?;
    final raw = data['fileData'];

    Uint8List bytes;
    if (raw is Uint8List) {
      bytes = raw;
    } else if (raw is Blob) {
      bytes = raw.bytes;
    } else if (raw is List<int>) {
      bytes = Uint8List.fromList(raw);
    } else if (raw is List<dynamic>) {
      // Aquí convertimos List<dynamic> a List<int>
      bytes = Uint8List.fromList(raw.cast<int>());
    } else {
      bytes = Uint8List(0);
      print('WARNING: unexpected fileData type: ${raw.runtimeType}');
    }

    return {
      'id': d.id,
      'fileName': data['fileName'] ?? '(sin nombre)',
      'uploadedAt': ts != null
          ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate())
          : '',
      'bytes': bytes,
    };
  }).toList();
}




  Future<void> _downloadFile(String name, Uint8List bytes) async {
    if (kIsWeb) {
      // Web: crea un Blob y un <a download>
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..download = name
        ..style.display = 'none';
      html.document.body?.append(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    } else {
      // Móvil: guarda en temp y abre con open_file
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Justificantes de $userName'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadJustificantes(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Text('No hay justificantes.'));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final j = list[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(j['fileName'] as String),
                  subtitle: Text(j['uploadedAt'] as String),
                  trailing: IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Descargar',
                    onPressed: () {
                      final bytes = j['bytes'] as Uint8List;
                      if (bytes.isNotEmpty) {
                        _downloadFile(j['fileName'] as String, bytes);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Error al abrir el fichero')),
                        );
                      }
                    },
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
