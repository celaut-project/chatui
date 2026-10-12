import 'package:argus_wallet/services/incoming_payment_watcher.dart';
import 'package:argus_wallet/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _titleTests();
  final a = {'tx_id': 'a', 'value_nano_erg': 1000000000, 'height': 0};
  final b = {'tx_id': 'b', 'value_nano_erg': -500, 'height': 0};
  final c = {'tx_id': 'c', 'value_nano_erg': 2000000000, 'height': 10};

  test('the first observation only primes the watcher', () {
    final w = IncomingPaymentWatcher();
    expect(w.observe([a, b]), isEmpty);
    expect(w.observe([a, b]), isEmpty);
  });

  test('a new incoming transaction is reported once', () {
    final w = IncomingPaymentWatcher()..observe([b]);
    final fresh = w.observe([a, b]);
    expect(fresh.map((t) => t['tx_id']), ['a']);
    expect(w.observe([a, b]), isEmpty);
  });

  test('outgoing transactions and reset are not reported', () {
    final w = IncomingPaymentWatcher()..observe([a]);
    expect(w.observe([a, b]), isEmpty);
    w.reset();
    expect(w.observe([a, b, c]), isEmpty);
  });

  test('confirmation of an already-seen pending tx is not a new payment', () {
    final w = IncomingPaymentWatcher()..observe([a]);
    expect(w.observe([{...a, 'height': 12}]), isEmpty);
  });
}

void _titleTests() {
  test('a payment is titled by whether it is in a block yet', () {
    expect(incomingTitle(pending: true), 'Payment on the way');
    expect(incomingTitle(pending: false), 'Payment received');
  });
}
