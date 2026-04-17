import 'package:flutter/material.dart';

class StatusBanner extends StatelessWidget {
  final String apiBaseUrl;

  const StatusBanner({super.key, required this.apiBaseUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Backend objetivo',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(apiBaseUrl),
        ],
      ),
    );
  }
}
