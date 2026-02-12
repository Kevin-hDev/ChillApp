import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../i18n/locale_provider.dart';

class ConnectionInfoScreen extends ConsumerWidget {
  const ConnectionInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.go('/'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t(locale, 'info.title'),
                      style: theme.textTheme.headlineLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  t(locale, 'info.intro'),
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                // TODO: Affichage des infos de connexion
                const Expanded(
                  child: Center(
                    child: Text('Connection Info — À implémenter'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
