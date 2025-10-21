import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import 'professor_page.dart';
import 'student_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String role = 'aluno';
  String? selectedStudentId;

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('SmartPresence — Login')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DropdownButton<String>(
              value: role,
              items: const [
                DropdownMenuItem(value: 'aluno', child: Text('Aluno')),
                DropdownMenuItem(value: 'professor', child: Text('Professor')),
              ],
              onChanged: (v) => setState(() => role = v ?? 'aluno'),
            ),
            const SizedBox(height: 20),
            if (role == 'aluno')
              DropdownButton<String>(
                value: selectedStudentId,
                hint: const Text('Selecione seu nome'),
                items: session.students
                    .map(
                      (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => selectedStudentId = v),
              )
            else
              ElevatedButton(
                onPressed: () {
                  session.generateSessionCode();
                  session.setProfessorMode(true);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfessorPage()),
                  );
                },
                child: const Text('Entrar como professor'),
              ),
            const SizedBox(height: 20),
            if (role == 'aluno')
              ElevatedButton(
                onPressed: selectedStudentId == null
                    ? null
                    : () {
                        final info = session.students.firstWhere(
                          (s) => s.id == selectedStudentId,
                        );
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StudentPage(
                              studentId: info.id,
                              studentName: info.name,
                            ),
                          ),
                        );
                      },
                child: const Text('Entrar como aluno'),
              ),
          ],
        ),
      ),
    );
  }
}
