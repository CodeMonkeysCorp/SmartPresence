import 'package:flutter/material.dart';

class AttendanceStatus extends StatelessWidget {
  final String status;
  final int round;

  const AttendanceStatus({
    super.key,
    required this.status,
    required this.round,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    if (status == 'P') {
      color = Colors.green;
    } else if (status == 'F')
      color = Colors.red;
    else
      color = Colors.grey;

    return CircleAvatar(
      backgroundColor: color,
      radius: 18,
      child: Text('$round', style: const TextStyle(color: Colors.white)),
    );
  }
}
