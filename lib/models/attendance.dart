class Attendance {
  final int round;
  final String status; // 'P' = Presente, 'F' = Falta, '-' = Não marcado
  final DateTime recordedAt;
  final String validationMethod; // 'UI_TOKEN', 'WS', 'AUTO', etc.
  final Duration? reactionTime;

  Attendance({
    required this.round,
    required this.status,
    DateTime? recordedAt,
    this.validationMethod = 'UNKNOWN',
    this.reactionTime,
  }) : recordedAt = recordedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'round': round,
    'status': status,
    'recordedAt': recordedAt.toIso8601String(),
    'validationMethod': validationMethod,
    'reactionTimeMs': reactionTime?.inMilliseconds,
  };

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
    round: json['round'] as int,
    status: json['status'] as String,
    recordedAt: json['recordedAt'] != null
        ? DateTime.parse(json['recordedAt'])
        : DateTime.now(),
    validationMethod: json['validationMethod'] as String? ?? 'UNKNOWN',
    reactionTime: json['reactionTimeMs'] != null
        ? Duration(milliseconds: json['reactionTimeMs'] as int)
        : null,
  );

  @override
  String toString() =>
      'Round $round → $status ($validationMethod, ${recordedAt.toIso8601String()})';
}
