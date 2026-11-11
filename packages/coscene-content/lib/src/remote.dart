import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coscene_core/coscene_core.dart';
import 'package:cryptography/cryptography.dart';

import 'level_pack.dart';

/// Fetches bytes from the content server.
abstract class PackTransport {
  Future<List<int>> get(Uri url);
}

/// HTTPS only, with a time limit and a size cap.
class HttpPackTransport implements PackTransport {
  HttpPackTransport({this.timeout = const Duration(seconds: 15), this.maxBytes = 4 * 1024 * 1024});
  final Duration timeout;
  final int maxBytes;

  @override
  Future<List<int>> get(Uri url) async {
    if (url.scheme != 'https') throw PackException('remote packs must be served over https');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        throw PackException('server answered ${response.statusCode} for ${url.path}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) throw PackException('${url.path} is larger than allowed');
      }
      return bytes;
    } on SocketException catch (e) {
      throw PackException('no connection: ${e.message}');
    } on TimeoutException {
      throw PackException('the content server took too long');
    } finally {
      client.close(force: true);
    }
  }
}

/// Where downloaded packs are kept between launches.
abstract class PackStore {
  Future<List<int>?> read(String name);
  Future<void> write(String name, List<int> bytes);
  Future<void> delete(String name);
  Future<List<String>> list();
}

/// Files in one folder. Writes go to a temporary file first and are then
/// renamed, so a crash never leaves a half-written pack.
class DirectoryPackStore implements PackStore {
  DirectoryPackStore(this.directory);
  final Directory directory;

  File _file(String name) => File('${directory.path}${Platform.pathSeparator}$name');

  @override
  Future<List<int>?> read(String name) async {
    final f = _file(name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String name, List<int> bytes) async {
    await directory.create(recursive: true);
    final tmp = _file('$name.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(_file(name).path);
  }

  @override
  Future<void> delete(String name) async {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<String>> list() async {
    if (!await directory.exists()) return [];
    return [
      await for (final e in directory.list())
        if (e is File) e.uri.pathSegments.last,
    ];
  }
}

class MemoryPackStore implements PackStore {
  final Map<String, List<int>> files = {};

  @override
  Future<List<int>?> read(String name) async => files[name];

  @override
  Future<void> write(String name, List<int> bytes) async => files[name] = List.of(bytes);

  @override
  Future<void> delete(String name) async => files.remove(name);

  @override
  Future<List<String>> list() async => files.keys.toList();
}

/// One pack listed in the remote manifest.
class ManifestEntry {
  ManifestEntry(this.id, this.version, this.file, this.sha256, this.minEngineVersion);
  final String id;
  final int version;
  final String file;
  final String sha256;
  final int minEngineVersion;
}

/// What a sync did.
class SyncReport {
  SyncReport({this.updated = const [], this.unchanged = const [], this.problems = const [], this.enabled = true});
  const SyncReport.disabled() : updated = const [], unchanged = const [], problems = const [], enabled = false;

  final bool enabled;
  final List<String> updated;
  final List<String> unchanged;
  final List<String> problems;
}

const String manifestName = 'manifest.json';
const String signatureName = 'manifest.sig';

String hexOf(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<String> sha256Hex(List<int> bytes) async => hexOf((await Sha256().hash(bytes)).bytes);

/// Downloads new level packs without an app update.
///
/// The server publishes `manifest.json` (which packs exist, with a SHA-256
/// of each), `manifest.sig` (an Ed25519 signature of the manifest), and the
/// pack files. Nothing is trusted unless the signature matches the public
/// key built into the app, each pack matches its hash, and the engine can
/// solve every level in it. Packs are data only; no code is downloaded.
class RemotePackLoader {
  RemotePackLoader({
    required this.baseUrl,
    required this.transport,
    required this.store,
    required List<int> publicKey,
    Engine? engine,
  }) : _publicKey = SimplePublicKey(publicKey, type: KeyPairType.ed25519),
       engine = engine ?? Engine.standard;

  /// Folder URL of the content server, or null to keep remote packs off.
  final Uri? baseUrl;
  final PackTransport transport;
  final PackStore store;
  final Engine engine;
  final SimplePublicKey _publicKey;

  bool get enabled => baseUrl != null;

  static final _safeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,80}\.json$');

  Future<List<ManifestEntry>> _readManifest(List<int> manifest, List<int> signature) async {
    final List<int> sig;
    try {
      sig = base64Decode(utf8.decode(signature).trim());
    } on FormatException {
      throw PackException('manifest signature is not base64');
    }
    final ok = await Ed25519().verify(manifest, signature: Signature(sig, publicKey: _publicKey));
    if (!ok) throw PackException('manifest signature does not match');
    final Object? doc;
    try {
      doc = jsonDecode(utf8.decode(manifest));
    } on FormatException {
      throw PackException('manifest is not valid JSON');
    }
    if (doc is! Map<String, dynamic> || doc['packs'] is! List) {
      throw PackException('manifest has no pack list');
    }
    final entries = <ManifestEntry>[];
    for (final p in doc['packs'] as List) {
      if (p is! Map<String, dynamic>) throw PackException('manifest entry is not an object');
      final id = p['id'], version = p['version'], file = p['file'], hash = p['sha256'];
      if (id is! String || version is! int || file is! String || hash is! String) {
        throw PackException('manifest entry is missing fields');
      }
      if (!_safeName.hasMatch(file) || file == manifestName) {
        throw PackException('manifest names an unsafe file "$file"');
      }
      entries.add(ManifestEntry(id, version, file, hash.toLowerCase(), p['minEngineVersion'] as int? ?? 1));
    }
    return entries;
  }

  Future<LevelPack> _open(ManifestEntry entry, List<int> bytes) async {
    if (await sha256Hex(bytes) != entry.sha256) {
      throw PackException('${entry.file} does not match its hash');
    }
    final pack = LevelPack.fromBytes(bytes);
    if (pack.id != entry.id || pack.version != entry.version) {
      throw PackException('${entry.file} is not ${entry.id} v${entry.version}');
    }
    final problems = pack.verify(engine);
    if (problems.isNotEmpty) throw PackException('${entry.file}: ${problems.first}');
    return pack;
  }

  /// Packs downloaded earlier, checked again before use. Broken or tampered
  /// files are skipped, never thrown.
  Future<List<LevelPack>> loadCached() async {
    final manifest = await store.read(manifestName);
    final signature = await store.read(signatureName);
    if (manifest == null || signature == null) return [];
    final List<ManifestEntry> entries;
    try {
      entries = await _readManifest(manifest, signature);
    } on PackException {
      return [];
    }
    final packs = <LevelPack>[];
    for (final entry in entries) {
      final bytes = await store.read(entry.file);
      if (bytes == null) continue;
      try {
        packs.add(await _open(entry, bytes));
      } on PackException {
        continue;
      }
    }
    return packs;
  }

  /// Fetches the manifest and any packs that changed. The new manifest is
  /// saved last, so an interrupted sync leaves the previous set intact.
  Future<SyncReport> sync() async {
    final base = baseUrl;
    if (base == null) return const SyncReport.disabled();
    final root = base.path.endsWith('/') ? base : base.replace(path: '${base.path}/');
    final updated = <String>[], unchanged = <String>[], problems = <String>[];
    final List<int> manifest, signature;
    final List<ManifestEntry> entries;
    try {
      manifest = await transport.get(root.resolve(manifestName));
      signature = await transport.get(root.resolve(signatureName));
      entries = await _readManifest(manifest, signature);
    } on PackException catch (e) {
      return SyncReport(problems: [e.message]);
    }
    final keep = <String>{manifestName, signatureName};
    for (final entry in entries) {
      keep.add(entry.file);
      if (entry.minEngineVersion > engineVersion) {
        problems.add('${entry.id} needs a newer app');
        continue;
      }
      try {
        final cached = await store.read(entry.file);
        if (cached != null && await sha256Hex(cached) == entry.sha256) {
          unchanged.add(entry.id);
          continue;
        }
        final bytes = await transport.get(root.resolve(entry.file));
        await _open(entry, bytes);
        await store.write(entry.file, bytes);
        updated.add(entry.id);
      } on PackException catch (e) {
        keep.remove(entry.file);
        problems.add(e.message);
      }
    }
    await store.write(manifestName, manifest);
    await store.write(signatureName, signature);
    for (final name in await store.list()) {
      if (!keep.contains(name)) await store.delete(name);
    }
    return SyncReport(updated: updated, unchanged: unchanged, problems: problems);
  }
}
