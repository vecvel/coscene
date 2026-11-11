import 'dart:convert';

import 'package:coscene_content/coscene_content.dart';
import 'package:coscene_core/coscene_core.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

class FakeServer implements PackTransport {
  final Map<String, List<int>> files = {};
  int requests = 0;

  @override
  Future<List<int>> get(Uri url) async {
    requests++;
    final bytes = files[url.pathSegments.last];
    if (bytes == null) throw PackException('server answered 404 for ${url.path}');
    return bytes;
  }
}

void main() {
  final base = loadBundledPack();
  late SimpleKeyPair keys;
  late List<int> publicKey;
  late FakeServer server;
  late MemoryPackStore store;

  LevelPack season({int version = 1, List<LevelSpec>? levels}) => LevelPack(
    id: 'season-1',
    version: version,
    minEngineVersion: 1,
    places: const [
      PlaceInfo(11, 'festival', ['balance_levers']),
    ],
    levels:
        levels ??
        [
          for (var i = 0; i < 3; i++)
            LevelSpec.fromJson({...base.levels[i].toJson(), 'id': 'p11-l0${i + 1}', 'place': 11, 'index': i + 1}),
        ],
    strings: const {
      'en': {'place.festival.name': 'Festival', 'place.festival.tagline': 'A seasonal visit'},
    },
  );

  Future<void> publish(List<LevelPack> packs, {SimpleKeyPair? signer}) async {
    final entries = <Map<String, dynamic>>[];
    for (final pack in packs) {
      final file = '${pack.id}.v${pack.version}.json';
      final bytes = utf8.encode(jsonEncode(pack.toJson()));
      server.files[file] = bytes;
      entries.add({
        'id': pack.id,
        'version': pack.version,
        'file': file,
        'sha256': await sha256Hex(bytes),
        'minEngineVersion': pack.minEngineVersion,
      });
    }
    final manifest = utf8.encode(jsonEncode({'formatVersion': 1, 'packs': entries}));
    final signature = await Ed25519().sign(manifest, keyPair: signer ?? keys);
    server.files[manifestName] = manifest;
    server.files[signatureName] = utf8.encode(base64Encode(signature.bytes));
  }

  RemotePackLoader loader({Uri? url}) => RemotePackLoader(
    baseUrl: url ?? Uri.parse('https://cdn.example.com/coscene'),
    transport: server,
    store: store,
    publicKey: publicKey,
  );

  setUp(() async {
    keys = await Ed25519().newKeyPair();
    publicKey = (await keys.extractPublicKey()).bytes;
    server = FakeServer();
    store = MemoryPackStore();
  });

  test('a signed, solvable pack is downloaded and joins the registry', () async {
    await publish([season()]);
    final report = await loader().sync();
    expect(report.updated, ['season-1']);
    expect(report.problems, isEmpty);

    final registry = LevelRegistry.bundled();
    for (final pack in await loader().loadCached()) {
      registry.add(pack, verify: true);
    }
    expect(registry.count, 103);
    expect(registry.place(11)!.id, 'festival');
    expect(registry.extraStrings('en')['place.festival.name'], 'Festival');
  });

  test('an unchanged pack is not downloaded twice', () async {
    await publish([season()]);
    await loader().sync();
    final before = server.requests;
    final report = await loader().sync();
    expect(report.unchanged, ['season-1']);
    expect(server.requests - before, 2, reason: 'only the manifest and its signature');
  });

  test('a manifest signed by someone else is refused', () async {
    await publish([season()], signer: await Ed25519().newKeyPair());
    final report = await loader().sync();
    expect(report.updated, isEmpty);
    expect(report.problems.single, contains('signature'));
    expect(await loader().loadCached(), isEmpty);
  });

  test('a pack changed after signing is refused', () async {
    await publish([season()]);
    final tampered = season(levels: [base.levels[5]]);
    server.files['season-1.v1.json'] = utf8.encode(jsonEncode(tampered.toJson()));
    final report = await loader().sync();
    expect(report.updated, isEmpty);
    expect(report.problems.single, contains('hash'));
  });

  test('a pack with an unsolvable level is refused whole', () async {
    final broken = LevelSpec.fromJson({
      ...base.levels.first.toJson(),
      'id': 'p11-l01',
      'place': 11,
      'initialState': {
        'halfSpan': 2,
        'fixed': [
          {'weight': 5, 'slot': -2},
        ],
        'movable': [
          {'weight': 1, 'slot': null},
        ],
      },
    });
    await publish([
      season(levels: [broken]),
    ]);
    final report = await loader().sync();
    expect(report.updated, isEmpty);
    expect(report.problems.single, contains('no winning setup'));
  });

  test('a pack for a newer engine waits for an app update', () async {
    final future = LevelPack(
      id: 'season-2',
      version: 1,
      minEngineVersion: engineVersion + 1,
      places: season().places,
      levels: season().levels,
    );
    await publish([future]);
    final report = await loader().sync();
    expect(report.updated, isEmpty);
    expect(report.problems.single, contains('newer app'));
  });

  test('a failed sync keeps the packs already on the device', () async {
    await publish([season()]);
    await loader().sync();
    server.files.clear();
    final report = await loader().sync();
    expect(report.problems, isNotEmpty);
    expect((await loader().loadCached()).single.id, 'season-1');
  });

  test('files changed on the device are caught when loading', () async {
    await publish([season()]);
    await loader().sync();
    store.files['season-1.v1.json'] = utf8.encode(jsonEncode(season(levels: [base.levels[7]]).toJson()));
    expect(await loader().loadCached(), isEmpty);
  });

  test('a newer version replaces the old file', () async {
    await publish([season()]);
    await loader().sync();
    await publish([season(version: 2)]);
    final report = await loader().sync();
    expect(report.updated, ['season-1']);
    expect(store.files.keys, containsAll(['season-1.v2.json', manifestName, signatureName]));
    expect(store.files.containsKey('season-1.v1.json'), isFalse);
  });

  test('without a URL nothing is fetched', () async {
    final off = RemotePackLoader(baseUrl: null, transport: server, store: store, publicKey: publicKey);
    expect(off.enabled, isFalse);
    expect((await off.sync()).enabled, isFalse);
    expect(server.requests, 0);
  });

  test('the public key built into the app is a real Ed25519 key', () {
    expect(RemoteConfig.publicKey, hasLength(32));
    expect(RemoteConfig.baseUrl, isNull, reason: 'tests run without COSCENE_PACK_URL');
  });
}
