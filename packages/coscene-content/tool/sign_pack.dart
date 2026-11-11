// Prepares a folder of pack files for upload to the content server.
//
//   dart run tool/sign_pack.dart <folder> [path/to/pack_signing_key.json]
//
// Every *.json pack in the folder is checked by the engine (all levels must
// load and be solvable). Then manifest.json and manifest.sig are written
// next to them. Upload the whole folder to the URL the app was built with
// (--dart-define=COSCENE_PACK_URL=https://...).
import 'dart:convert';
import 'dart:io';

import 'package:coscene_content/src/level_pack.dart';
import 'package:coscene_content/src/remote.dart';
import 'package:coscene_core/coscene_core.dart';
import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/sign_pack.dart <folder> [key file]');
    exit(64);
  }
  final dir = Directory(args[0]);
  final keyFile = File(args.length > 1 ? args[1] : '../../secrets/pack_signing_key.json');
  if (!dir.existsSync() || !keyFile.existsSync()) {
    stderr.writeln('Folder or key file not found.');
    exit(66);
  }
  final key = jsonDecode(keyFile.readAsStringSync()) as Map<String, dynamic>;
  final pair = await Ed25519().newKeyPairFromSeed(base64Decode(key['privateKey'] as String));

  final packs = <Map<String, dynamic>>[];
  final files = dir.listSync().whereType<File>().where((f) {
    final name = f.uri.pathSegments.last;
    return name.endsWith('.json') && name != manifestName;
  }).toList()..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final bytes = file.readAsBytesSync();
    final pack = LevelPack.fromBytes(bytes);
    final problems = pack.verify(Engine.standard);
    if (problems.isNotEmpty) {
      stderr.writeln('${file.path} is not publishable:');
      problems.forEach(stderr.writeln);
      exit(1);
    }
    packs.add({
      'id': pack.id,
      'version': pack.version,
      'file': file.uri.pathSegments.last,
      'sha256': await sha256Hex(bytes),
      'minEngineVersion': pack.minEngineVersion,
    });
    stdout.writeln('${pack.id} v${pack.version}: ${pack.levels.length} levels checked');
  }
  if (packs.isEmpty) {
    stderr.writeln('No pack files found in ${dir.path}.');
    exit(1);
  }
  final manifest = utf8.encode('${jsonEncode({'formatVersion': 1, 'packs': packs})}\n');
  final signature = await Ed25519().sign(manifest, keyPair: pair);
  File('${dir.path}/$manifestName').writeAsBytesSync(manifest);
  File('${dir.path}/$signatureName').writeAsStringSync('${base64Encode(signature.bytes)}\n');
  stdout.writeln('Wrote $manifestName and $signatureName. Upload the folder as it is.');
}
