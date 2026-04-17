class Exercise {
  final String id;
  final String name;
  final String muscleGroup;
  final String difficulty;
  final String equipment;

  const Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.difficulty,
    required this.equipment,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Sin nombre',
      muscleGroup: json['muscle_group'] as String? ?? '-',
      difficulty: json['difficulty'] as String? ?? '-',
      equipment: json['equipment'] as String? ?? '-',
    );
  }
}
