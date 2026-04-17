import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/env.dart';
import '../domain/exercise.dart';

class ExerciseApi {
  Future<List<Exercise>> fetchExercises() async {
    final uri = Uri.parse('${Env.apiBaseUrl}/exercises');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Backend error: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = (body['data'] as List<dynamic>?) ?? [];

    return data
        .whereType<Map<String, dynamic>>()
        .map(Exercise.fromJson)
        .toList();
  }
}
