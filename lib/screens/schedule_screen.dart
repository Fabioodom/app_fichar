// lib/screens/schedule_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

class ScheduleScreen extends StatefulWidget {
  final String userId;
  final String? userName;
  final bool readOnly;

  const ScheduleScreen({
    super.key,
    required this.userId,
    this.userName,
    this.readOnly = true,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _loading = false;

  /// Vacaciones del usuario
  final List<DateTime> _vacations = [];

  @override
  void initState() {
    super.initState();
    _loadVacations();
    _loadForDate(_selectedDay);
  }

  /// Carga las fechas de vacaciones de /users/{userId}/vacations
  Future<void> _loadVacations() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('vacations')
        .get();
    setState(() {
      _vacations
        ..clear()
        ..addAll(snap.docs.map((d) => DateTime.parse(d.id)));
    });
  }

  bool _isVacation(DateTime day) {
    return _vacations.any((d) =>
        d.year == day.year && d.month == day.month && d.day == day.day);
  }

  /// Marca o desmarca la vacación SOLO para este usuario
  Future<void> _toggleVacation(DateTime day) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(day);
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('vacations')
        .doc(dateKey);

    if (_isVacation(day)) {
      await ref.delete();
    } else {
      await ref.set({'date': dateKey});
    }
    await _loadVacations();
  }

  Future<void> _loadForDate(DateTime date) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('schedule')
        .doc(dateKey)
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        _startTime = _parseTime(data['start'] as String?);
        _endTime = _parseTime(data['end'] as String?);
      });
    } else {
      setState(() {
        _startTime = null;
        _endTime = null;
      });
    }
  }

  TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDay = picked;
        _focusedDay = picked;
      });
      await _loadForDate(picked);
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart
        ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 17, minute: 0));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      setState(() {
        if (isStart) _startTime = picked;
        else _endTime = picked;
      });
    }
  }

  String _format24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_startTime == null || _endTime == null) return;
    setState(() => _loading = true);

    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDay);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('schedule')
        .doc(dateKey)
        .set({
      'date': dateKey,
      'start': _format24(_startTime!),
      'end': _format24(_endTime!),
    });

    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horario guardado ✅')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        DateFormat('EEEE, dd MMM yyyy', 'es_ES').format(_selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName != null
            ? 'Horario de ${widget.userName}'
            : 'Mi horario'),
      ),
      body: Column(
        children: [
          // Calendario interactivo con marcadores y vacaciones
          TableCalendar(
            firstDay: DateTime.utc(2000, 1, 1),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (d) =>
                d.year == _selectedDay.year &&
                d.month == _selectedDay.month &&
                d.day == _selectedDay.day,
            onDaySelected: (d, f) async {
  setState(() {
    _selectedDay = d;
    _focusedDay = f;
  });
  await _loadForDate(d);
},

            calendarBuilders: CalendarBuilders(
              defaultBuilder: (ctx, day, focused) {
                if (_isVacation(day)) {
                  return Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text('${day.day}')),
                  );
                }
                return null;
              },
              todayBuilder: (ctx, day, focused) => Container(
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text('${day.day}')),
              ),
              markerBuilder: (ctx, date, events) {
                final key = DateFormat('yyyy-MM-dd').format(date);
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(widget.userId)
                      .collection('schedule')
                      .doc(key)
                      .get(),
                  builder: (_, snap) {
                    if (snap.hasData && snap.data!.exists) {
                      return const Positioned(
                        bottom: 4,
                        child: CircleAvatar(
                          radius: 3,
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                    return const SizedBox();
                  },
                );
              },
            ),
            headerStyle: const HeaderStyle(
              titleCentered: true,
              formatButtonVisible: false,
            ),
            calendarFormat: CalendarFormat.month,
          ),

          const Divider(),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Fecha seleccionada
                  if (!widget.readOnly)
                    TextButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(dateLabel),
                    )
                  else
                    Text(
                      dateLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),

                  const SizedBox(height: 12),

                  // Hora inicio
                  ListTile(
                    title: const Text('Hora de inicio'),
                    trailing: Text(
                        _startTime != null ? _format24(_startTime!) : '--:--'),
                    onTap: widget.readOnly
                        ? null
                        : () => _pickTime(isStart: true),
                  ),

                  // Hora fin
                  ListTile(
                    title: const Text('Hora de fin'),
                    trailing:
                        Text(_endTime != null ? _format24(_endTime!) : '--:--'),
                    onTap: widget.readOnly
                        ? null
                        : () => _pickTime(isStart: false),
                  ),

                  const Spacer(),

                  // Toggle vacaciones (solo admin y por usuario)
                  if (!widget.readOnly)
                    ElevatedButton.icon(
                      onPressed: () => _toggleVacation(_selectedDay),
                      icon: Icon(_isVacation(_selectedDay)
                          ? Icons.beach_access_outlined
                          : Icons.beach_access),
                      label: Text(_isVacation(_selectedDay)
                          ? 'Quitar vacaciones'
                          : 'Marcar vacaciones'),
                    ),

                  // Guardar horario (solo admin)
                  if (!widget.readOnly)
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: (_startTime != null && _endTime != null)
                                ? _save
                                : null,
                            child: const Text('Guardar horario'),
                          ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
