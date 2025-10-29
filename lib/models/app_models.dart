// lib/models/app_models.dart

import 'package:flutter/material.dart'; // Para TimeOfDay
import 'dart:io'; // Para WebSocket

// Modelos do Aplicativo

// Classe para representar uma rodada de chamada
class Rodada {
  final String nome;
  TimeOfDay horaInicio;
  String status; // Ex: "Aguardando", "Em Andamento", "Encerrada"
  String? pin; // PIN gerado para a rodada, pode ser nulo

  Rodada({
    required this.nome,
    required this.horaInicio,
    this.status = "Aguardando",
    this.pin,
  });
}

// Classe para representar um aluno conectado ao servidor do professor
class AlunoConectado {
  final WebSocket socket; // O socket WebSocket do aluno
  final String matricula; // Matrícula do aluno
  final String nome; // Nome de exibição do aluno
  final String ip; // Endereço IP do aluno >>>
  final DateTime connectedAt; // Timestamp da conexão >>>

  AlunoConectado({
    required this.socket,
    required this.matricula,
    required this.nome,
    required this.ip,
    required this.connectedAt,
  });
}
