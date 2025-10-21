import 'attendance.dart';

class Student {
  final String id;
  final String name;
  final List<Attendance> history;

  Student({required this.id, required this.name, List<Attendance>? history})
    : history = history ?? [];

  void addOrUpdateAttendance(Attendance attendance) {
    final idx = history.indexWhere((h) => h.round == attendance.round);
    if (idx >= 0) {
      history[idx] = attendance;
    } else {
      history.add(attendance);
    }
  }

  String statusForRound(int round) => history
      .firstWhere(
        (h) => h.round == round,
        orElse: () =>
            Attendance(round: round, status: '-', validationMethod: ''),
      )
      .status;

  int get totalPresences => history.where((h) => h.status == 'P').length;

  double get presenceRate =>
      history.isEmpty ? 0 : totalPresences / history.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'history': history.map((h) => h.toJson()).toList(),
  };

  factory Student.fromJson(Map<String, dynamic> json) => Student(
    id: json['id'] as String,
    name: json['name'] as String,
    history:
        (json['history'] as List?)
            ?.map((e) => Attendance.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [],
  );

  @override
  String toString() =>
      '$name ($id) – ${history.length} registros (${(presenceRate * 100).toStringAsFixed(0)}%)';
}
