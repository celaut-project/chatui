import 'package:argus_wallet/services/verified_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry ids are well-formed and unique', () {
    final ids = verifiedTokens.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(id), isTrue, reason: id);
    }
  });

  test('look-alikes are flagged, real ones and unrelated names are not', () {
    final fake = impersonatedToken(tokenId: 'c891f9f39b3a3648a969a8f2f744a4d05478c568ed35fe38e7671bc8832b2c93', name: 'SigUSD');
    expect(fake?.ticker, 'SigUSD');
    expect(impersonatedToken(tokenId: '03faf2cb329f2e90d6d23b58d91bbb6c046aa143261cc21f52fbe2824bfcbf04', name: 'SigUSD'), isNull);
    expect(impersonatedToken(tokenId: 'abc', name: 'My NFT #4'), isNull);
    expect(impersonatedToken(tokenId: 'abc', name: 'rsn'), isNotNull);
  });

  test('cautioned tokens are known but not verified', () {
    const neta = '472c3d4ecaa08fb7392ff041ee2e6af75f4a558810a74b28600549d5392810e8';
    expect(isVerifiedToken(neta), isFalse);
    expect(cautionedToken(neta)?.note, contains('abandoned'));
    expect(impersonatedToken(tokenId: neta, name: 'NETA'), isNull);
  });

  test('Rosen map entries are present and well-formed', () {
    expect(isVerifiedToken('e023c5f382b6e96fbd878f6811aac73345489032157ad5affb84aefd4956c297'), isTrue); // rsADA
    expect(isVerifiedToken('886b7721bef42f60c6317d37d8752da8aca01898cae7dae61808c4a14225edc8'), isTrue); // GluonW GAU
    expect(verifiedToken('203ef3066a912f35c488487cc2cb94bdb0d30680dab22551c7e6fdbc70dfcc8e')?.project, 'Rosen Bridge'); // rsETH
    expect(verifiedTokens.length, greaterThan(50));
  });
}
