import 'dart:io'; // Para WebSocket
import 'package:flutter/material.dart'; // Para TimeOfDay

// Modelo para o aluno conectado
// Agora inclui a matrícula
class AlunoConectado {
  final WebSocket socket;
  final String nome;
  final String matricula; // NOVO CAMPO

  AlunoConectado({
    required this.socket,
    required this.nome,
    required this.matricula, // NOVO CAMPO
  });
}

// Modelo para a rodada
// (Sem alteração, mas movido para este arquivo)
class Rodada {
  final String nome;
  final TimeOfDay horaInicio;
  String status; // "Aguardando", "Em Andamento", "Encerrada"
  String? pin;

  Rodada({
    required this.nome,
    required this.horaInicio,
    this.status = "Aguardando",
    this.pin,
  });
}
