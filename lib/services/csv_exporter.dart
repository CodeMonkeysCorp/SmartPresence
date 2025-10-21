import '../providers/session_provider.dart';

class CsvExporter {
  /// Retorna CSV como string. rounds = lista de rodadas a exportar.
  static String generateCsv(SessionProvider provider, {List<int>? rounds}) {
    final used = rounds ?? [1, 2, 3, 4];
    final buffer = StringBuffer();
    buffer.writeln('Aluno,Data,${used.map((r) => 'Rodada $r').join(',')}');

    final date = DateTime.now().toIso8601String().split('T').first;
    for (final s in provider.students) {
      final model = provider.studentModelById(s.id);
      final row = [
        s.name,
        date,
        ...used.map((r) => model?.statusForRound(r) ?? '-'),
      ];
      buffer.writeln(row.join(','));
    }

    return buffer.toString();
  }
}
