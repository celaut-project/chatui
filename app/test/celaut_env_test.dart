import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_env.dart';
import 'package:argus_wallet/bridge/api/celaut_service_info.dart';
import 'package:argus_wallet/celaut/egress.dart';
import 'package:argus_wallet/celaut/env_store.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/ui/celaut/env_questions_screen.dart';
import 'package:argus_wallet/ui/celaut/env_variables_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The container in memory, with the calls that the screens make.
class _Container {
  final values = <String, String>{};
  final calls = <String>[];
  Object? setError;

  EnvStore get store => EnvStore(
    names: () => [for (final n in values.keys.toList()..sort()) EnvNameView(name: n, changedAt: 1)],
    get: (n) {
      calls.add('get $n');
      return values[n];
    },
    set: (n, v) {
      if (setError != null) throw setError!;
      calls.add('set $n');
      values[n] = v;
    },
    delete: (n) {
      calls.add('delete $n');
      values.remove(n);
    },
  );
}

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  group('the rules of a name and a value', () {
    test('a name is a C identifier that is not reserved', () {
      for (final ok in ['A', '_', 'API_KEY', '_x1']) {
        expect(envNameProblem(ok), isNull, reason: ok);
      }
      expect(envNameProblem(''), EnvProblem.nameEmpty);
      for (final bad in ['1A', 'A-B', 'A B', 'ñ', 'A.B', 'A=B']) {
        expect(envNameProblem(bad), EnvProblem.nameBad, reason: bad);
      }
      expect(envNameProblem(envReservedName), EnvProblem.nameReserved);
      expect(envNameProblem('A' * 257), EnvProblem.nameBad);
    });

    test('a value is text with no NUL and at most 8192 bytes', () {
      expect(envValueProblem('sk-1 ñ'), isNull);
      expect(envValueProblem(''), EnvProblem.valueEmpty);
      expect(envValueProblem('a\u0000b'), EnvProblem.valueNul);
      expect(envValueProblem('a' * 8192), isNull);
      expect(envValueProblem('a' * 8193), EnvProblem.valueLong);
      // The limit counts bytes: 4097 characters of 2 bytes are too long.
      expect(envValueProblem('ñ' * 4097), EnvProblem.valueLong);
    });
  });

  group('the container screen', () {
    testWidgets('an empty container says so', (tester) async {
      await tester.pumpWidget(_app(EnvVariablesScreen(store: _Container().store)));
      expect(find.byKey(const Key('env-empty')), findsOneWidget);
    });

    testWidgets('a variable is added, listed with its value hidden, edited and deleted', (tester) async {
      final c = _Container();
      await tester.pumpWidget(_app(EnvVariablesScreen(store: c.store)));
      await tester.tap(find.byKey(const Key('env-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('env-name')), 'API_KEY');
      await tester.enterText(find.byKey(const Key('env-value')), 'sk-1');
      await tester.tap(find.byKey(const Key('env-save')));
      await tester.pumpAndSettle();
      expect(c.values, {'API_KEY': 'sk-1'});
      expect(find.byKey(const Key('env-row-API_KEY')), findsOneWidget);
      expect(find.text('sk-1'), findsNothing);

      // The edit form hides the value until the eye is tapped.
      await tester.tap(find.byKey(const Key('env-row-API_KEY')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('env-value'))).obscureText, isTrue);
      await tester.tap(find.byKey(const Key('env-eye')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('env-value'))).obscureText, isFalse);
      expect(find.text('sk-1'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('env-value')), 'sk-2');
      await tester.tap(find.byKey(const Key('env-save')));
      await tester.pumpAndSettle();
      expect(c.values, {'API_KEY': 'sk-2'});

      await tester.tap(find.byKey(const Key('env-delete-API_KEY')));
      await tester.pumpAndSettle();
      expect(c.values, isNotEmpty, reason: 'the delete asks first');
      await tester.tap(find.byKey(const Key('env-delete-yes')));
      await tester.pumpAndSettle();
      expect(c.values, isEmpty);
      expect(find.byKey(const Key('env-empty')), findsOneWidget);
    });

    testWidgets('a bad name or value is refused with its reason and nothing is stored', (tester) async {
      final c = _Container();
      await tester.pumpWidget(_app(EnvVariablesScreen(store: c.store)));
      await tester.tap(find.byKey(const Key('env-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('env-name')), '1A');
      await tester.tap(find.byKey(const Key('env-save')));
      await tester.pump();
      expect(find.textContaining('start with a letter'), findsOneWidget);
      expect(find.text('Write a value.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('env-name')), '__nodo_instance_name');
      await tester.enterText(find.byKey(const Key('env-value')), 'x');
      await tester.tap(find.byKey(const Key('env-save')));
      await tester.pump();
      expect(find.textContaining('reserved'), findsOneWidget);
      expect(c.values, isEmpty);
      expect(c.calls, isEmpty);
    });

    testWidgets('a name that exists is not added a second time', (tester) async {
      final c = _Container()..values['A'] = '1';
      await tester.pumpWidget(_app(EnvVariablesScreen(store: c.store)));
      await tester.tap(find.byKey(const Key('env-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('env-name')), 'A');
      await tester.enterText(find.byKey(const Key('env-value')), '2');
      await tester.tap(find.byKey(const Key('env-save')));
      await tester.pump();
      expect(find.textContaining('exists'), findsOneWidget);
      expect(c.values, {'A': '1'});
    });

    testWidgets('an error of Rust shows its text and keeps the form open', (tester) async {
      final c = _Container()..setError = const CelautError(kind: CelautErrorKind.storage, message: 'disk full');
      await tester.pumpWidget(_app(EnvVariablesScreen(store: c.store)));
      await tester.tap(find.byKey(const Key('env-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('env-name')), 'A');
      await tester.enterText(find.byKey(const Key('env-value')), '1');
      await tester.tap(find.byKey(const Key('env-save')));
      await tester.pump();
      expect(find.text('disk full'), findsOneWidget);
      expect(find.byKey(const Key('env-edit')), findsOneWidget);
    });
  });

  group('the questions of a launch', () {
    const declared = [
      DeclaredVariableView(name: 'API_KEY', tags: ['text'], prose: 'The key of the API'),
      DeclaredVariableView(name: 'MODE', tags: ['text'], prose: ''),
      DeclaredVariableView(name: 'TOKEN', tags: [], prose: ''),
    ];

    Future<List<EnvChoice>?> ask(
      WidgetTester tester,
      Future<void> Function() answers, {
      _Container? c,
      List<DeclaredVariableView> variables = declared,
      List<NetworkView> networks = const [],
    }) async {
      List<EnvChoice>? result = const [EnvChoice(name: 'not-set')];
      var done = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              key: const Key('open'),
              onPressed: () async {
                result = await Navigator.of(context).push<List<EnvChoice>>(
                  MaterialPageRoute(
                    builder: (_) => EnvQuestionsScreen(
                      declared: variables,
                      networks: networks,
                      store: (c ?? _Container()).store,
                    ),
                  ),
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await answers();
      expect(done, isTrue, reason: 'the screen closed');
      return result;
    }

    testWidgets('one variable at a time, each a container variable, a typed value or a skip', (tester) async {
      final c = _Container()..values['OPENAI_KEY'] = 'sk-secret';
      final result = await ask(tester, () async {
        expect(find.text('Variable 1 of 3'), findsOneWidget);
        expect(find.text('API_KEY'), findsOneWidget);
        expect(find.text('The key of the API'), findsOneWidget);
        await tester.tap(find.byKey(const Key('env-ask-pick')));
        await tester.pumpAndSettle();
        // The values of the container are not shown.
        expect(find.text('sk-secret'), findsNothing);
        await tester.tap(find.byKey(const Key('env-pick-OPENAI_KEY')));
        await tester.pumpAndSettle();

        expect(find.text('Variable 2 of 3'), findsOneWidget);
        // With no prose, the tags of the format.
        expect(find.byKey(const Key('env-var-text')), findsOneWidget);
        expect(find.text('text'), findsOneWidget);
        await tester.tap(find.byKey(const Key('env-ask-type')));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('env-typed')), 'fast ñ');
        await tester.tap(find.byKey(const Key('env-typed-use')));
        await tester.pumpAndSettle();

        expect(find.text('Variable 3 of 3'), findsOneWidget);
        await tester.tap(find.byKey(const Key('env-ask-skip')));
        await tester.pumpAndSettle();

        // The review shows where each value comes from, and no value.
        expect(find.text('My variable OPENAI_KEY'), findsOneWidget);
        expect(find.text('Typed value'), findsOneWidget);
        expect(find.text('Skipped'), findsOneWidget);
        expect(find.text('fast ñ'), findsNothing);
        expect(find.text('sk-secret'), findsNothing);
        expect(find.byKey(const Key('env-review-note')), findsOneWidget);
        await tester.tap(find.byKey(const Key('env-run')));
        await tester.pumpAndSettle();
      }, c: c);
      expect(result!.map((e) => (e.name, e.container, e.text)), [
        ('API_KEY', 'OPENAI_KEY', null),
        ('MODE', null, 'fast ñ'),
      ]);
      // Reading the values is the job of Rust: the screen never asked for one.
      expect(c.calls, isEmpty);
    });

    NetworkView net(List<String> tags, {String formal = ''}) =>
        NetworkView(tags: tags, prose: '', formal: formal, protocolStack: const []);

    group('a service that can send out what it is given', () {
      test('its exits are read from its networks', () {
        expect(egressOf(const []).level, EgressLevel.none);
        // A group of peers of the service is not an exit.
        expect(egressOf([net(['workers'])]).level, EgressLevel.none);
        final named = egressOf([net(['api.example.com']), net(['pow:ergo']), net(['api.example.com'])]);
        expect(named.level, EgressLevel.named);
        expect(named.hosts, ['api.example.com', 'pow:ergo']);
        // One domain with every address is the worst, wherever it is.
        expect(egressOf([net(['api.example.com']), net(['*'])]).level, EgressLevel.open);
        expect(egressOf([net(['*']), net(['api.example.com'])]).level, EgressLevel.open);
      });

      test('a variable that a parameter of a network takes is known', () {
        final r = egressOf([
          net(['pow:ergo'], formal: 'pow.chain=ergo\npow.block_id=\${BLOCK}'),
        ]);
        expect(r.steered.keys, ['BLOCK']);
        expect(r.steered['BLOCK'], ['pow:ergo']);
        expect(egressOf([net(['workers'])]).steered, isEmpty);
      });

      testWidgets('a service with no exit shows no notice and asks for no acceptance', (tester) async {
        final result = await ask(tester, () async {
          await tester.tap(find.byKey(const Key('env-ask-type')));
          await tester.pump();
          await tester.enterText(find.byKey(const Key('env-typed')), 'v');
          await tester.tap(find.byKey(const Key('env-typed-use')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('env-egress-notice')), findsNothing);
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('env-egress-ack')), findsNothing);
          await tester.tap(find.byKey(const Key('env-run')));
          await tester.pumpAndSettle();
        }, networks: [net(['workers'])]);
        expect(result, hasLength(1));
      });

      testWidgets('every address: the notice shows on each question, and a value needs the acceptance', (
        tester,
      ) async {
        final result = await ask(tester, () async {
          expect(find.byKey(const Key('env-egress-notice')), findsOneWidget);
          expect(find.textContaining('any address'), findsOneWidget);
          await tester.tap(find.byKey(const Key('env-ask-type')));
          await tester.pump();
          await tester.enterText(find.byKey(const Key('env-typed')), 'secret');
          await tester.tap(find.byKey(const Key('env-typed-use')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('env-egress-notice')), findsOneWidget);
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          // The review: Run waits for the acceptance.
          expect(find.byKey(const Key('env-egress-notice')), findsOneWidget);
          expect(tester.widget<FilledButton>(find.byKey(const Key('env-run'))).onPressed, isNull);
          await tester.tap(find.byKey(const Key('env-egress-ack')));
          await tester.pump();
          expect(tester.widget<FilledButton>(find.byKey(const Key('env-run'))).onPressed, isNotNull);
          await tester.tap(find.byKey(const Key('env-run')));
          await tester.pumpAndSettle();
        }, networks: [net(['*'])]);
        expect(result!.map((e) => e.name), ['API_KEY']);
      });

      testWidgets('every address, nothing given: there is nothing to accept', (tester) async {
        final result = await ask(tester, () async {
          for (var i = 0; i < 3; i++) {
            await tester.tap(find.byKey(const Key('env-ask-skip')));
            await tester.pumpAndSettle();
          }
          expect(find.byKey(const Key('env-egress-ack')), findsNothing);
          await tester.tap(find.byKey(const Key('env-run')));
          await tester.pumpAndSettle();
        }, networks: [net(['*'])]);
        expect(result, isEmpty);
      });

      testWidgets('named hosts: the hosts are shown, and only a saved variable needs the acceptance', (
        tester,
      ) async {
        final c = _Container()..values['OPENAI_KEY'] = 'sk-secret';
        final result = await ask(tester, () async {
          expect(find.textContaining('api.example.com'), findsOneWidget);
          // A typed value goes with the notice and nothing more.
          await tester.tap(find.byKey(const Key('env-ask-type')));
          await tester.pump();
          await tester.enterText(find.byKey(const Key('env-typed')), 'typed');
          await tester.tap(find.byKey(const Key('env-typed-use')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('env-egress-ack')), findsNothing);
          expect(tester.widget<FilledButton>(find.byKey(const Key('env-run'))).onPressed, isNotNull);
          // Back, and give a saved variable instead: now it asks.
          await tester.tap(find.byKey(const Key('env-back')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-back')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-back')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-ask-pick')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-pick-OPENAI_KEY')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('env-egress-ack')), findsOneWidget);
          expect(tester.widget<FilledButton>(find.byKey(const Key('env-run'))).onPressed, isNull);
          await tester.tap(find.byKey(const Key('env-egress-ack')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('env-run')));
          await tester.pumpAndSettle();
        }, c: c, networks: [net(['api.example.com'])]);
        expect(result!.single.container, 'OPENAI_KEY');
      });

      testWidgets('a variable that a network takes says that it sets where the service connects', (
        tester,
      ) async {
        await ask(tester, () async {
          // The first variable is not steered, the second one is.
          expect(find.byKey(const Key('env-egress-steers')), findsNothing);
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('env-egress-steers')), findsOneWidget);
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-run')));
          await tester.pumpAndSettle();
        }, networks: [net(['pow:ergo'], formal: 'pow.block_id=\${MODE}')]);
      });
    });

    testWidgets('skipping every variable runs with none', (tester) async {
      final result = await ask(tester, () async {
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('env-run')));
        await tester.pumpAndSettle();
      });
      expect(result, isEmpty);
    });

    testWidgets('the variables of the container with the same name come first', (tester) async {
      final c = _Container()
        ..values['AAA'] = '1'
        ..values['MODE'] = '2';
      await ask(tester, () async {
        await tester.tap(find.byKey(const Key('env-ask-skip')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('env-ask-pick')));
        await tester.pumpAndSettle();
        final same = tester.getTopLeft(find.byKey(const Key('env-pick-MODE')));
        final other = tester.getTopLeft(find.byKey(const Key('env-pick-AAA')));
        expect(same.dy, lessThan(other.dy));
        await tester.tap(find.byKey(const Key('env-pick-AAA')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('env-cancel')));
        await tester.pumpAndSettle();
      }, c: c);
    });

    testWidgets('an empty container says where to add variables', (tester) async {
      await ask(tester, () async {
        await tester.tap(find.byKey(const Key('env-ask-pick')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('env-pick-empty')), findsOneWidget);
        expect(find.textContaining('Environment variables'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('env-cancel')));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('a typed value that the node cannot use is refused with its reason', (tester) async {
      await ask(tester, () async {
        await tester.tap(find.byKey(const Key('env-ask-type')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('env-typed-use')));
        await tester.pump();
        expect(find.text('Write a value.'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('env-typed')), 'a\u0000b');
        await tester.tap(find.byKey(const Key('env-typed-use')));
        await tester.pump();
        expect(find.textContaining('NUL'), findsOneWidget);
        expect(find.text('Variable 1 of 3'), findsOneWidget, reason: 'it stays on the variable');
        await tester.tap(find.byKey(const Key('env-cancel')));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('a typed value is hidden until the eye is tapped', (tester) async {
      await ask(tester, () async {
        await tester.tap(find.byKey(const Key('env-ask-type')));
        await tester.pump();
        expect(tester.widget<TextField>(find.byKey(const Key('env-typed'))).obscureText, isTrue);
        await tester.tap(find.byKey(const Key('env-typed-eye')));
        await tester.pump();
        expect(tester.widget<TextField>(find.byKey(const Key('env-typed'))).obscureText, isFalse);
        await tester.tap(find.byKey(const Key('env-cancel')));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('Back returns to the earlier variable and keeps its answer; Cancel gives null', (tester) async {
      final result = await ask(tester, () async {
        await tester.tap(find.byKey(const Key('env-ask-skip')));
        await tester.pumpAndSettle();
        expect(find.text('Variable 2 of 3'), findsOneWidget);
        await tester.tap(find.byKey(const Key('env-back')));
        await tester.pumpAndSettle();
        expect(find.text('Variable 1 of 3'), findsOneWidget);
        expect(find.textContaining('Chosen: Skipped'), findsOneWidget);
        await tester.tap(find.byKey(const Key('env-cancel')));
        await tester.pumpAndSettle();
      });
      expect(result, isNull);
    });

    testWidgets('the system back goes to the earlier variable, and on the first one it cancels', (tester) async {
      final result = await ask(tester, () async {
        await tester.tap(find.byKey(const Key('env-ask-skip')));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Variable 1 of 3'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      });
      expect(result, isNull);
    });

    testWidgets('a declared name that the node cannot give can only be skipped', (tester) async {
      final result = await ask(
        tester,
        () async {
          expect(find.byKey(const Key('env-bad-name')), findsOneWidget);
          expect(find.byKey(const Key('env-ask-pick')), findsNothing);
          expect(find.byKey(const Key('env-ask-type')), findsNothing);
          await tester.tap(find.byKey(const Key('env-ask-skip')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('env-run')));
          await tester.pumpAndSettle();
        },
        variables: const [DeclaredVariableView(name: '1-bad', tags: [], prose: '')],
      );
      expect(result, isEmpty);
    });

    test('the choices keep the order of the declaration and leave out what was skipped', () {
      final out = envChoices(declared, [const EnvTyped('x'), const EnvSkipped(), const EnvFromContainer('K')]);
      expect(out.map((e) => (e.name, e.container, e.text)), [('API_KEY', null, 'x'), ('TOKEN', 'K', null)]);
      expect(envChoices(declared, [null, null, null]), isEmpty);
    });
  });
}
