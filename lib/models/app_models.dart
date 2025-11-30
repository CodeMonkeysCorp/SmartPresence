import 'package:flutter/material.dart';
import 'dart:io';

class Rodada {
  final String nome;
  TimeOfDay horaInicio;
  String status;
  String? pin;

  Rodada({
    required this.nome,
    required this.horaInicio,
    this.status = "Aguardando",
    this.pin,
  });
}

class AlunoConectado {
  final WebSocket socket;
  final String matricula;
  final String nome;
  final String ip;
  final DateTime connectedAt;

  AlunoConectado({
    required this.socket,
    required this.matricula,
    required this.nome,
    required this.ip,
    required this.connectedAt,
  });
}
