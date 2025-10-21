import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/student.dart';
import '../models/attendance.dart';

class StudentInfo {
  final String name;
  final String id;
  bool isPresent;

  StudentInfo({required this.name, required this.id, this.isPresent = false});
}

class SessionProvider extends ChangeNotifier {
  String? _sessionCode;
  bool _isProfessor = false;
  final List<StudentInfo> _students = [];
  final Map<String, Student> _studentsById = {};
  bool _isConnected = false;

  // rodada
  bool _roundActive = false;
  int _currentRound = 1;

  String? get sessionCode => _sessionCode;
  bool get isProfessor => _isProfessor;
  bool get isConnected => _isConnected;
  List<StudentInfo> get students => List.unmodifiable(_students);
  bool get roundActive => _roundActive;
  int get currentRound => _currentRound;

  Student? studentModelById(String id) => _studentsById[id];

  String generateSessionCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    _sessionCode = List.generate(
      5,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
    notifyListeners();
    return _sessionCode!;
  }

  void setProfessorMode(bool value) {
    _isProfessor = value;
    notifyListeners();
  }

  void setConnected(bool value) {
    _isConnected = value;
    notifyListeners();
  }

  void addStudent(String name, String id) {
    if (_students.any((s) => s.id == id)) return;
    _students.add(StudentInfo(name: name, id: id));
    _studentsById.putIfAbsent(id, () => Student(id: id, name: name));
    notifyListeners();
  }

  void syncStudents(List<Map<String, dynamic>> studentsData) {
    _students
      ..clear()
      ..addAll(
        studentsData.map(
          (s) => StudentInfo(
            name: s['name'] as String,
            id: s['id'] as String,
            isPresent: s['present'] as bool? ?? false,
          ),
        ),
      );
    // manter modelos:
    for (final s in studentsData) {
      final id = s['id'] as String;
      final name = s['name'] as String;
      _studentsById.putIfAbsent(id, () => Student(id: id, name: name));
    }
    notifyListeners();
  }

  void markPresent(String id) {
    final st = _students.firstWhere(
      (s) => s.id == id,
      orElse: () => StudentInfo(name: '', id: ''),
    );
    if (st.name.isNotEmpty) {
      st.isPresent = true;
      notifyListeners();
    }
  }

  void resetSession() {
    _students.clear();
    _studentsById.clear();
    _sessionCode = null;
    _isConnected = false;
    _roundActive = false;
    _currentRound = 1;
    notifyListeners();
  }

  // Rodadas
  void startNewRound() {
    _currentRound++;
    _roundActive = true;
    for (final s in _students) {
      s.isPresent = false;
    }
    notifyListeners();
  }

  void endRound() {
    _roundActive = false;
    notifyListeners();
  }

  void setRoundActive(bool value) {
    _roundActive = value;
    notifyListeners();
  }

  void setCurrentRound(int r) {
    _currentRound = r;
    notifyListeners();
  }

  // Histórico: registra presença no modelo Student (history)
  void addAttendanceToStudent(
    String id,
    int round,
    String status, {
    String validationMethod = 'UNKNOWN',
  }) {
    final student = _studentsById.putIfAbsent(
      id,
      () => Student(id: id, name: id),
    );
    student.addOrUpdateAttendance(
      Attendance(
        round: round,
        status: status,
        validationMethod: validationMethod,
      ),
    );
    notifyListeners();
  }
}
