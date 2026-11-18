import 'dart:async';
import 'dart:io';
import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:anymex_extension_runtime_bridge/Services/Sora/SoraExtensions.dart';
import 'package:anymex_extension_runtime_bridge/Services/Mangayomi/MangayomiExtensions.dart';
import 'package:anymex_extension_runtime_bridge/Settings/KvStore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

const native = MethodChannel('com.animecompanion.extensions');
final services = CompanionServices();
final player = ValueNotifier<VideoPlayerController?>(null);
final playerTitle = ValueNotifier<String>('');

@pragma('vm:entry-point')
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Do not write extension requests, signed URLs or source credentials to logs.
  AnymeXExtensionBridge.onLog = (_, _) {};
  native.setMethodCallHandler((call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
    try {
      if (call.method == 'playVideo') {
        await stopVideo();
        final url = Uri.parse(args['url'] as String);
        if (!['https', 'http'].contains(url.scheme)) {
          throw const FormatException('A direct video link is required');
        }
        final controller = VideoPlayerController.networkUrl(
          url,
          httpHeaders: Map<String, String>.from(args['headers'] as Map? ?? {}),
        );
        await controller.initialize().timeout(const Duration(seconds: 45));
        playerTitle.value = args['title'] as String? ?? 'Video';
        player.value = controller;
        await controller.play();
        return null;
      }
      if (call.method == 'stopVideo') {
        await stopVideo();
        return null;
      }
      return await services.handle(call.method, args);
    } catch (_) {
      // Error text from a source may contain passwords or signed URLs.
      throw PlatformException(
        code: 'extension_failed',
        message:
            'The source could not complete this request. Check your connection, repository and source settings, then try again.',
      );
    }
  });
  runApp(const ExtensionPlayerApp());
}

Future<void> stopVideo() async {
  final previous = player.value;
  player.value = null;
  await previous?.dispose();
}

/// The host owns the native screens and their state. Register the complete
/// upstream manager set deterministically, without its unawaited auto-start.
class CompanionServices {
  Future<void>? _initialization;
  late ExtensionManager _manager;
  final _errors = <String, String>{};
  final _methods = <String, SourceMethods>{};
  final _cancelled = <String>{};
  final _active = <String, SourceMethods>{};

  Future<List<Map<String, dynamic>>> preferenceRows(
    SourceMethods service,
    Map<String, dynamic> args,
  ) async {
    final values = (await service.getPreference())
        .map((p) => p.toJson())
        .toList();
    if (args['manager'] == 'nuvio') {
      values.add(
        SourcePreference(
          key: 'companion.tmdb',
          editTextPreference: EditTextPreference(
            title: 'TMDB API key (optional)',
            summary:
                'Improves metadata matching for sources that need TMDB IDs. Your own key stays on this device.',
            value:
                getVal<String>('companion.tmdbApiKey', defaultValue: '') ?? '',
          ),
        ).toJson(),
      );
    }
    return values;
  }

  Future<void> initialize() =>
      _initialization ??= _initialize().catchError((Object error) {
        _initialization = null;
        throw error;
      });

  Future<void> _initialize() async {
    await AnymeXExtensionBridge.init(
      projectName: 'CompanionExtensions',
      getDirectory: AnymeXExtensionBridge.defaultGetDirectory(
        appFolderName: 'CompanionExtensions',
      ),
    );
    // Logger.init replaces onLog; suppress logs after initialization too.
    AnymeXExtensionBridge.onLog = (_, _) {};
    _manager = ExtensionManager(automaticallyInitialize: false);
    Get.replace<ExtensionManager>(_manager);
    final bridgePath = await RuntimePaths().bridgePath;
    // The backend is bundled and versioned with the app. Opening the hub never
    // downloads an unpinned runtime or asks the user to set up a server.
    final data = await rootBundle.load('assets/anymex_desktop_runtime.jar');
    final bridge = File(bridgePath);
    await bridge.parent.create(recursive: true);
    await bridge.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    AnymeXRuntimeBridge.controller.setReady(true);
    AnymeXRuntimeBridge.onSolveCloudflare = (url) async {
      final result = await native.invokeMapMethod<String, dynamic>(
        'websiteSession',
        {'url': url},
      );
      if (result == null) return false;
      await AnymeXRuntimeBridge.setCookies(
        url,
        result['cookies'] as String? ?? '',
      );
      await AnymeXRuntimeBridge.setUserAgent(
        url,
        result['userAgent'] as String? ?? '',
      );
      return result['solved'] == true;
    };
    // Keep the full upstream ecosystem, including Nuvio and Stremio. TorrServer
    // is not initialized: torrent links remain with the app's TorBox flow.
    final managers = <Extension>[
      DesktopCloudStreamExtensions(),
      DesktopAniyomiExtensions(),
      DesktopKotatsuExtensions(),
      DesktopTsundokuExtensions(),
      DesktopIReaderExtensions(),
      MangayomiExtensions(),
      SoraExtensions(),
      LegadoExtensions(),
      LnReaderExtensions(),
      StremioExtensions(),
      NuvioPluginExtensions(),
    ];
    _manager.managers.assignAll(managers);
    for (final manager in managers) {
      try {
        await manager.initialize();
      } catch (_) {
        _errors[manager.id] = 'Could not start. Tap Retry.';
      }
    }
  }

  Extension manager(String id) =>
      _manager.managers.firstWhere((m) => m.id == id);
  ItemType type(Map<String, dynamic> args) =>
      ItemType.values.byName(args['type'] as String);
  Source source(Map<String, dynamic> args, {bool available = false}) {
    final owner = manager(args['manager'] as String);
    final list = available
        ? owner.getAvailableRx(type(args)).value
        : owner.getInstalledRx(type(args)).value;
    return list.firstWhere((s) => s.id == args['source']);
  }

  String key(Map<String, dynamic> args) =>
      '${args['manager']}:${args['type']}:${args['source']}';
  SourceMethods methods(Map<String, dynamic> args) => _methods.putIfAbsent(
    key(args),
    () => manager(args['manager'] as String).createSourceMethods(source(args)),
  );

  Future<void> _refresh(
    Extension owner,
    ItemType kind, {
    bool available = true,
  }) async {
    switch (kind) {
      case ItemType.anime:
        await owner.fetchInstalledAnimeExtensions();
        if (available) await owner.fetchAnimeExtensions();
      case ItemType.manga:
        await owner.fetchInstalledMangaExtensions();
        if (available) await owner.fetchMangaExtensions();
      case ItemType.novel:
        await owner.fetchInstalledNovelExtensions();
        if (available) await owner.fetchNovelExtensions();
    }
  }

  Map<String, dynamic> snapshot() => {
    'managers': _manager.managers
        .map(
          (owner) => {
            'id': owner.id,
            'name': owner.name,
            'types': ItemType.values
                .where(owner.supportsType)
                .map((t) => t.name)
                .toList(),
            'error': _errors[owner.id],
            'repositories': [
              for (final kind in ItemType.values)
                if (owner.supportsType(kind))
                  for (final repo in owner.getReposRx(kind).value)
                    {...repo.toJson(), 'type': kind.name},
            ],
          },
        )
        .toList(),
    'installed': [
      for (final owner in _manager.managers)
        for (final kind in ItemType.values)
          if (owner.supportsType(kind))
            for (final s in owner.getInstalledRx(kind).value)
              {...s.toJson(), 'managerId': owner.id, 'kind': kind.name},
    ],
    'available': [
      for (final owner in _manager.managers)
        for (final kind in ItemType.values)
          if (owner.supportsType(kind))
            for (final s in owner.getAvailableRx(kind).value)
              {...s.toJson(), 'managerId': owner.id, 'kind': kind.name},
    ],
  };

  Future<dynamic> handle(String operation, Map<String, dynamic> args) async {
    if (operation == 'shutdown') {
      for (final service in _methods.values) {
        await service.stopHttpServer();
      }
      _methods.clear();
      if (_initialization != null) {
        await AnymeXExtensionBridge.isar.close();
        AnymeXExtensionBridge.dispose();
      }
      return null;
    }
    if (operation == 'cancel') {
      final token = args['token'] as String;
      _cancelled.add(token);
      await _active[token]?.cancelRequest(token);
      // Bound tokens when a cancelled request has already finished.
      if (_cancelled.length > 256) _cancelled.remove(_cancelled.first);
      return null;
    }
    await initialize();
    if (operation == 'initialize' || operation == 'snapshot') return snapshot();
    if (operation == 'refresh' || operation == 'retry') {
      for (final owner in _manager.managers.where(
        (m) => args['manager'] == null || m.id == args['manager'],
      )) {
        try {
          if (operation == 'retry') await owner.initialize();
          for (final kind in ItemType.values.where(owner.supportsType)) {
            await _refresh(owner, kind);
          }
          _errors.remove(owner.id);
        } catch (_) {
          _errors[owner.id] =
              'Could not refresh. Check the repository and try again.';
        }
      }
      return snapshot();
    }
    if (operation == 'addRepo' || operation == 'removeRepo') {
      final url = Uri.parse(args['url'] as String);
      if (url.scheme != 'https' ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty) {
        throw const FormatException('Use an HTTPS repository URL');
      }
      final owner = manager(args['manager'] as String);
      final kind = type(args);
      if (!owner.supportsType(kind))
        throw const FormatException('Unsupported content type');
      if (operation == 'addRepo') {
        await owner.addRepo(url.toString(), kind);
      } else {
        await owner.removeRepo(url.toString(), kind);
        owner.purgeRepoFromAvailable(url.toString(), kind);
      }
      await _refresh(owner, kind);
      return snapshot();
    }
    if (operation == 'updateAll') {
      final failures = <String>{};
      for (final owner in _manager.managers) {
        for (final kind in ItemType.values.where(owner.supportsType)) {
          final pending = owner
              .getInstalledRx(kind)
              .value
              .where((s) => s.hasUpdate == true)
              .toList();
          for (final s in pending) {
            try {
              await owner.updateSource(s);
            } catch (_) {
              failures.add(owner.id);
            }
          }
          await _refresh(owner, kind, available: false);
        }
      }
      for (final id in failures) {
        _errors[id] = 'Some extensions could not update. Retry individually.';
      }
      _methods.clear();
      return snapshot();
    }
    if (['install', 'update', 'uninstall'].contains(operation)) {
      final owner = manager(args['manager'] as String);
      final s = source(args, available: operation == 'install');
      if (operation == 'install') await owner.installSource(s);
      if (operation == 'update') await owner.updateSource(s);
      if (operation == 'uninstall') await owner.uninstallSource(s);
      final previous = _methods.remove(key(args));
      await previous?.stopHttpServer();
      await _refresh(owner, type(args));
      return snapshot();
    }
    final token = args['token'] as String? ?? '';
    if (_cancelled.remove(token)) throw StateError('Cancelled');
    final service = methods(args);
    _active[token] = service;
    final parameters = SourceParams(cancelToken: token);
    try {
      dynamic result;
      switch (operation) {
        case 'browse':
          final page = args['page'] as int? ?? 1;
          final query = args['query'] as String? ?? '';
          final filters = args['filters'] as List? ?? [];
          final mode = args['mode'] as String? ?? 'popular';
          final pages = mode == 'search'
              ? await service.search(
                  query,
                  page,
                  filters,
                  parameters: parameters,
                )
              : mode == 'latest'
              ? await service.getLatestUpdates(page, parameters: parameters)
              : await service.getPopular(page, parameters: parameters);
          result = pages.toJson();
        case 'detail':
          result = (await service.getDetail(
            DMedia.fromJson(Map<String, dynamic>.from(args['media'] as Map)),
            parameters: parameters,
          )).toJson();
        case 'pages':
          result = (await service.getPageList(
            DEpisode.fromJson(
              Map<String, dynamic>.from(args['episode'] as Map),
            ),
            parameters: parameters,
          )).map((p) => p.toJson()).toList();
        case 'videos':
          result = (await service.getVideoList(
            DEpisode.fromJson(
              Map<String, dynamic>.from(args['episode'] as Map),
            ),
            parameters: parameters,
          )).map((v) => v.toJson()).toList();
        case 'novel':
          result = await service.getNovelContent(
            args['title'] as String? ?? '',
            args['url'] as String,
            parameters: parameters,
          );
        case 'preferences':
          result = await preferenceRows(service, args);
        case 'setPreference':
          if (args['manager'] == 'nuvio' && args['key'] == 'companion.tmdb') {
            setVal('companion.tmdbApiKey', (args['value'] as String).trim());
          } else {
            final preferences = await service.getPreference();
            final preference = preferences.firstWhere(
              (p) => p.key == args['key'] && p.id == args['id'],
            );
            if (!await service.setPreference(preference, args['value'])) {
              throw StateError('Preference was not saved');
            }
          }
          result = await preferenceRows(service, args);
        default:
          throw UnsupportedError(operation);
      }
      if (_cancelled.remove(token)) throw StateError('Cancelled');
      return result;
    } finally {
      _active.remove(token);
    }
  }
}

class ExtensionPlayerApp extends StatelessWidget {
  const ExtensionPlayerApp({super.key});
  @override
  Widget build(BuildContext context) => GetMaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: ValueListenableBuilder<VideoPlayerController?>(
      valueListenable: player,
      builder: (context, controller, _) => controller == null
          ? const ColoredBox(color: Colors.black)
          : PlayerScreen(controller: controller),
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.controller, super.key});
  final VideoPlayerController controller;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final v = c.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          playerTitle.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          tooltip: 'Close video',
          icon: const Icon(Icons.close),
          onPressed: () => native.invokeMethod<void>('closePlayer'),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: v.hasError
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'This video could not play. Try another source or quality.',
                        ),
                      )
                    : AspectRatio(
                        aspectRatio: v.aspectRatio,
                        child: VideoPlayer(c),
                      ),
              ),
            ),
            if (v.isBuffering) const LinearProgressIndicator(),
            VideoProgressIndicator(
              c,
              allowScrubbing: true,
              padding: const EdgeInsets.all(16),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Back 10 seconds',
                  onPressed: () =>
                      c.seekTo(v.position - const Duration(seconds: 10)),
                  icon: const Icon(Icons.replay_10),
                ),
                IconButton(
                  tooltip: v.isPlaying ? 'Pause' : 'Play',
                  onPressed: () => v.isPlaying ? c.pause() : c.play(),
                  icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: 'Forward 10 seconds',
                  onPressed: () =>
                      c.seekTo(v.position + const Duration(seconds: 10)),
                  icon: const Icon(Icons.forward_10),
                ),
                PopupMenuButton<double>(
                  tooltip: 'Playback speed',
                  onSelected: c.setPlaybackSpeed,
                  itemBuilder: (_) => [
                    for (final speed in [0.75, 1.0, 1.25, 1.5, 2.0])
                      PopupMenuItem(value: speed, child: Text('${speed}x')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
