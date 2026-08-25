import 'package:flutter/material.dart';

/// Placeholder for a screen not yet built (Phase 5/6 of the migration plan
/// fill these in) — keeps every route in the go_router table reachable and
/// navigable from Phase 4 onward, so navigation/guards can be verified
/// before any real feature UI exists.
class StubScreen extends StatelessWidget {
  const StubScreen({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction_outlined, size: 40),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
