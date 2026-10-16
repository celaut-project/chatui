import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_package.dart';
import 'package:argus_wallet/celaut/package_channel.dart';
import 'package:argus_wallet/celaut/package_library.dart';
import 'package:argus_wallet/celaut/service_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

final _id = 'ab' * 32;

LibraryPackageView _view({String? id, String name = 'echo', bool present = true}) => LibraryPackageView(
  serviceId: id ?? _id,
  name: name,
  path: '/data/packages/library/${id ?? _id}.bee',
  bytes: BigInt.from(4096),
  importedAt: 5,
  nodoExport: true,
  present: present,
);

void main() {
  late List<String> calls;
  var stored = <LibraryPackageView>[];
  String? dir = '/data/app';
  Object? importError;

  PackageLibrary make() => PackageLibrary(
    importPackage: (path, name, d) async {
      calls.add('import $path $name $d');
      if (importError != null) throw importError!;
      return _view(name: name);
    },
    list: () => stored,
    remove: (id) async => calls.add('remove $id'),
    privateDir: () async => dir,
  );

  setUp(() {
    calls = [];
    stored = [];
    dir = '/data/app';
    importError = null;
  });

  test('a picked file is loaded into the private directory with the name of the file', () async {
    final loaded = await make().importPicked(
      const PickedPackage(path: '/cache/picked-1.bee', bytes: 10, name: 'echo.celaut.bee'),
    );
    expect(calls, ['import /cache/picked-1.bee echo.celaut.bee /data/app']);
    expect(loaded.serviceId, _id);
  });

  test('with no private directory the file is refused and nothing is loaded', () async {
    dir = null;
    await expectLater(
      make().importPicked(const PickedPackage(path: '/c.bee', bytes: 1, name: 'c')),
      throwsA(isA<PackageRefused>().having((e) => e.reason, 'reason', PackageRefusal.noDirectory)),
    );
    dir = '';
    await expectLater(
      make().importPicked(const PickedPackage(path: '/c.bee', bytes: 1, name: 'c')),
      throwsA(isA<PackageRefused>()),
    );
    expect(calls, isEmpty);
  });

  test('a file that is not a service package is an error of the core, for the screen', () async {
    importError = const CelautError(kind: CelautErrorKind.invalidInput, message: 'no Service part');
    await expectLater(
      make().importPicked(const PickedPackage(path: '/c.bee', bytes: 1, name: 'c')),
      throwsA(isA<CelautError>().having((e) => e.message, 'message', 'no Service part')),
    );
  });

  test('find gives a loaded service by id, in any case, only if its file is there', () {
    stored = [_view(), _view(id: 'cd' * 32, present: false)];
    final library = make();
    expect(library.find(_id)?.serviceId, _id);
    expect(library.find(_id.toUpperCase())?.serviceId, _id);
    expect(library.find('cd' * 32), isNull, reason: 'the file is gone');
    expect(library.find('ef' * 32), isNull);
    expect(library.list(), hasLength(2));
  });

  test('remove asks the core to delete the service', () async {
    await make().remove(_id);
    expect(calls, ['remove $_id']);
  });
}
