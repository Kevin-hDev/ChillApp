import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/command_runner.dart';

void main() {
  group('CommandResult', () {
    test('success est true quand exitCode est 0', () {
      final result = CommandResult(exitCode: 0, stdout: 'ok', stderr: '');
      expect(result.success, true);
    });

    test('success est false quand exitCode est non-zéro', () {
      final result = CommandResult(exitCode: 1, stdout: '', stderr: 'erreur');
      expect(result.success, false);
    });

    test('success est false quand exitCode est négatif', () {
      final result = CommandResult(exitCode: -1, stdout: '', stderr: '');
      expect(result.success, false);
    });
  });

  group('CommandRunner', () {
    test('run exécute une commande simple', () async {
      final result = await CommandRunner.run('echo', ['hello']);
      expect(result.success, true);
      expect(result.stdout, 'hello');
    });

    test('run retourne une erreur pour commande inexistante', () async {
      final result = await CommandRunner.run(
        'commande_qui_existe_pas_du_tout_12345',
        [],
      );
      expect(result.success, false);
    });

    test('run capture le stdout', () async {
      final result = await CommandRunner.run('whoami', []);
      expect(result.success, true);
      expect(result.stdout.isNotEmpty, true);
    });

    test('run trim le stdout', () async {
      final result = await CommandRunner.run('echo', ['  test  ']);
      expect(result.stdout, 'test');
    });
  });
}
