import 'package:flutter/material.dart';

import '../../../../core/env.dart';
import '../../../exercises/data/exercise_api.dart';
import '../../../exercises/domain/exercise.dart';
import 'widgets/status_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ExerciseApi();
  late Future<List<Exercise>> _futureExercises;

  @override
  void initState() {
    super.initState();
    _futureExercises = _api.fetchExercises();
  }

  Future<void> _reload() async {
    setState(() {
      _futureExercises = _api.fetchExercises();
    });
    await _futureExercises;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gym Trainer Prototype'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar ejercicios',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Pantalla inicial conectada al backend real',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Esta base ya sirve para la siguiente fase: catálogo real desde PostgreSQL y app Flutter lista para crecer.',
            ),
            const SizedBox(height: 16),
            const _FeatureChecklist(),
            const SizedBox(height: 16),
            const StatusBanner(apiBaseUrl: Env.apiBaseUrl),
            const SizedBox(height: 16),
            FutureBuilder<List<Exercise>>(
              future: _futureExercises,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return _ErrorState(error: snapshot.error.toString(), onRetry: _reload);
                }

                final exercises = snapshot.data ?? [];
                if (exercises.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No hay ejercicios todavía.')),
                    ),
                  );
                }

                return Column(
                  children: exercises
                      .map(
                        (exercise) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  exercise.name.isNotEmpty
                                      ? exercise.name.substring(0, 1).toUpperCase()
                                      : '?',
                                ),
                              ),
                              title: Text(exercise.name),
                              subtitle: Text('${exercise.muscleGroup} · ${exercise.difficulty}'),
                              trailing: Text(exercise.equipment),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChecklist extends StatelessWidget {
  const _FeatureChecklist();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Estado del vertical slice'),
            SizedBox(height: 12),
            _ChecklistItem(text: 'FastAPI conectado a PostgreSQL'),
            _ChecklistItem(text: 'Seed inicial disponible en la base de datos'),
            _ChecklistItem(text: 'Flutter carga y refresca catálogo'),
            _ChecklistItem(text: 'Base preparada para detalle/login en siguiente iteración'),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final String text;

  const _ChecklistItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 12),
            const Text('No se pudo conectar con el backend.'),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
