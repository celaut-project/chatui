import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_package.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/launcher.dart';
import 'package:argus_wallet/celaut/package_channel.dart';
import 'package:argus_wallet/celaut/service_transfer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = NodeAddress(host: 'a.example', port: 1);
const _b = NodeAddress(host: 'b.example', port: 2);
const _c = NodeAddress(host: 'c.example', port: 3);
const _d = NodeAddress(host: 'd.example', port: 4);
final _id = 'ab' * 32;

QuoteFailureView _failure(NodeAddress a, CelautErrorKind kind) =>
    QuoteFailureView(address: a, kind: kind, message: kind.name);

QuoteView _quote(NodeAddress a) => QuoteView(
  address: a,
  peerId: 'p',
  costMu: '10',
  initMaintenanceMu: '1',
  maxMaintenanceMu: '1',
  maintenanceSecondsLoop: 10,
  variance: 0,
  comparedNanoErg: '1',
  clientBalanceMu: '100',
);

LaunchSkip _skip(NodeAddress a, CelautErrorKind kind) =>
    LaunchSkip(_quote(a), CelautError(kind: kind, message: kind.name));

PackageView _package({String? id, bool hasService = true}) => PackageView(
  path: '/cache/packages/x.bee',
  bytes: BigInt.from(1000),
  serviceId: id,
  hasService: hasService,
  nodoExport: false,
);

void main() {
  group('the offer of a failed launch', () {
    test('a node that has it and a node that does not: send from one to the other', () {
      final offer = transferOfferOf(
        LaunchFailure(
          LaunchFailureKind.noQuotes,
          quoteFailures: [
            _failure(_a, CelautErrorKind.serviceMissing),
            _failure(_b, CelautErrorKind.nodeClosed),
          ],
        ),
      )!;
      expect(offer.source, TransferSource.node);
      expect(offer.from, _b);
      expect(offer.to, _a);
      expect(offer.missing, [_a]);
    });

    test('a node that quoted has the service, whatever stopped its start', () {
      final offer = transferOfferOf(
        LaunchFailure(
          LaunchFailureKind.allFailed,
          quoteFailures: [_failure(_a, CelautErrorKind.serviceMissing)],
          skipped: [_skip(_c, CelautErrorKind.protocol)],
        ),
      )!;
      expect(offer.from, _c);
    });

    test('nodes that do not answer say nothing: the service comes from a file', () {
      final offer = transferOfferOf(
        LaunchFailure(
          LaunchFailureKind.noQuotes,
          quoteFailures: [
            _failure(_a, CelautErrorKind.serviceMissing),
            _failure(_b, CelautErrorKind.unreachable),
            _failure(_c, CelautErrorKind.timeout),
            _failure(_d, CelautErrorKind.identityMismatch),
          ],
        ),
      )!;
      expect(offer.source, TransferSource.file);
      expect(offer.from, isNull);
      expect(offer.to, _a);
    });

    test('every reason that nodo gives only for a service that it has makes a holder', () {
      for (final kind in [
        CelautErrorKind.nodeClosed,
        CelautErrorKind.noRoom,
        CelautErrorKind.insufficientCredit,
        CelautErrorKind.rateLimited,
        CelautErrorKind.launchFailed,
        CelautErrorKind.policyRefused,
        CelautErrorKind.unsupportedArchitecture,
      ]) {
        final offer = transferOfferOf(
          LaunchFailure(
            LaunchFailureKind.noQuotes,
            quoteFailures: [_failure(_a, CelautErrorKind.serviceMissing), _failure(_b, kind)],
          ),
        )!;
        expect(offer.from, _b, reason: kind.name);
      }
    });

    test('the nodes that lack it, in order and once, from failures and skips', () {
      final offer = transferOfferOf(
        LaunchFailure(
          LaunchFailureKind.allFailed,
          quoteFailures: [
            _failure(_b, CelautErrorKind.serviceMissing),
            _failure(_b, CelautErrorKind.serviceMissing),
          ],
          skipped: [_skip(_a, CelautErrorKind.serviceMissing)],
        ),
      )!;
      expect(offer.missing, [_b, _a]);
      expect(offer.to, _b);
      expect(offer.source, TransferSource.file);
    });

    test('no node lacks the service: no offer', () {
      expect(
        transferOfferOf(
          LaunchFailure(
            LaunchFailureKind.allFailed,
            quoteFailures: [_failure(_a, CelautErrorKind.noRoom)],
            skipped: [_skip(_b, CelautErrorKind.insufficientCredit)],
          ),
        ),
        isNull,
      );
      expect(transferOfferOf(const LaunchFailure(LaunchFailureKind.noNodes)), isNull);
    });
  });

  group('the transfer', () {
    late List<String> calls;
    PackageView inspected = _package();
    String? dir = '/data/app';

    ServiceTransfer make() => ServiceTransfer(
      fetch: (source, id, d) async {
        calls.add('fetch ${source.host} $id $d');
        return _package(id: id);
      },
      inspect: (path) async {
        calls.add('inspect $path');
        return inspected;
      },
      send: (node, id, initialMu, path) async {
        calls.add('send ${node.host} $id $initialMu $path');
        return _quote(node);
      },
      progress: () => TransferView(stage: TransferStage.idle, bytes: BigInt.zero),
      cancel: () => calls.add('cancel'),
      privateDir: () async => dir,
    );

    setUp(() {
      calls = [];
      inspected = _package();
      dir = '/data/app';
    });

    test('from a node: get it into the private directory, then send that file', () async {
      final offer = TransferOffer(source: TransferSource.node, from: _b, to: _a, missing: const [_a]);
      final quote = await make().fromNode(offer, _id, '7');
      expect(quote.address, _a);
      expect(calls, [
        'fetch b.example $_id /data/app',
        'send a.example $_id 7 /cache/packages/x.bee',
      ]);
    });

    test('from a node, with no private directory: refused, nothing moves', () async {
      dir = null;
      final offer = TransferOffer(source: TransferSource.node, from: _b, to: _a, missing: const [_a]);
      await expectLater(
        make().fromNode(offer, _id, null),
        throwsA(isA<PackageRefused>().having((e) => e.reason, 'reason', PackageRefusal.noDirectory)),
      );
      expect(calls, isEmpty);
    });

    test('from a file of this service, or that does not say its id: it is sent', () async {
      inspected = _package(id: _id.toUpperCase());
      await make().fromFile(_a, _id, null, '/picked.bee');
      inspected = _package();
      await make().fromFile(_a, _id, null, '/picked.bee');
      expect(calls.where((c) => c.startsWith('send')), hasLength(2));
      expect(calls.first, 'inspect /picked.bee');
    });

    test('a file of another service, or with no Service part, is refused before any send', () async {
      inspected = _package(id: 'cd' * 32);
      await expectLater(
        make().fromFile(_a, _id, null, '/picked.bee'),
        throwsA(isA<PackageRefused>().having((e) => e.reason, 'reason', PackageRefusal.otherService)),
      );
      inspected = _package(id: _id, hasService: false);
      await expectLater(
        make().fromFile(_a, _id, null, '/picked.bee'),
        throwsA(isA<PackageRefused>().having((e) => e.reason, 'reason', PackageRefusal.noService)),
      );
      expect(calls.where((c) => c.startsWith('send')), isEmpty);
    });

    test('an error of the node goes to the caller', () async {
      final transfer = ServiceTransfer(
        inspect: (path) async => _package(),
        send: (node, id, initialMu, path) async =>
            throw const CelautError(kind: CelautErrorKind.transferFailed, message: 'cut'),
        progress: () => TransferView(stage: TransferStage.idle, bytes: BigInt.zero),
        cancel: () {},
      );
      await expectLater(
        transfer.fromFile(_a, _id, null, '/p.bee'),
        throwsA(isA<CelautError>().having((e) => e.kind, 'kind', CelautErrorKind.transferFailed)),
      );
    });
  });

  group('the Android channel', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> methods;

    void answer(Object? Function(MethodCall call) reply) {
      messenger.setMockMethodCallHandler(AndroidPackageChannel.channel, (call) async {
        methods.add(call.method);
        return reply(call);
      });
    }

    setUp(() => methods = []);
    tearDown(() => messenger.setMockMethodCallHandler(AndroidPackageChannel.channel, null));

    test('a picked file and the metered network', () async {
      answer((call) => call.method == 'isMetered'
          ? true
          : {'path': '/cache/packages/picked-1.bee', 'bytes': 2048, 'name': 'echo.celaut.bee'});
      const channel = AndroidPackageChannel(android: true);
      final picked = await channel.pick();
      expect(picked!.path, '/cache/packages/picked-1.bee');
      expect(picked.bytes, 2048);
      expect(picked.name, 'echo.celaut.bee');
      expect(await channel.isMetered(), isTrue);
      expect(methods, ['pickPackage', 'isMetered']);
    });

    test('a cancelled pick, an error, or no channel give no file and never throw', () async {
      const channel = AndroidPackageChannel(android: true);
      answer((_) => null);
      expect(await channel.pick(), isNull);
      answer((_) => throw PlatformException(code: 'copy_failed'));
      expect(await channel.pick(), isNull);
      expect(await channel.isMetered(), isFalse);
      messenger.setMockMethodCallHandler(AndroidPackageChannel.channel, null);
      expect(await channel.pick(), isNull);
      expect(await channel.isMetered(), isFalse);
    });

    test('off Android it does nothing', () async {
      answer((_) => true);
      const channel = AndroidPackageChannel(android: false);
      expect(await channel.pick(), isNull);
      expect(await channel.isMetered(), isFalse);
      expect(methods, isEmpty);
    });
  });
}
