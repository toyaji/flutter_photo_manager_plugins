import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_native_image/photo_manager_native_image.dart';

void main() => runApp(const ExampleApp());

/// Column counts reachable by pinching.
const List<int> kColumnSteps = <int>[2, 3, 4, 6, 10];

/// The two thumbnail sizes this app uses. Which sizes to use is app policy.
const int kBaseSize = 128;
const int kMainSize = 320;

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'photo_manager_native_image example',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const GalleryPage(),
    );
  }
}

/// A pinch-to-zoom grid with an instrumentation panel.
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage>
    with WidgetsBindingObserver {
  List<AssetPathEntity> _albums = const <AssetPathEntity>[];
  AssetPathEntity? _album;
  List<AssetEntity> _assets = const <AssetEntity>[];
  String? _errorText;
  int _columnIndex = 2;
  bool _loadingMore = false;

  // Instrumentation.
  int _jankFrames = 0;
  int _memoryPressureEvents = 0;
  double _pinchBase = 1;
  late final TimingsCallback _timingsCallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timingsCallback = (List<ui.FrameTiming> timings) {
      int jank = 0;
      for (final ui.FrameTiming timing in timings) {
        if (timing.totalSpan.inMicroseconds > 16667) {
          jank++;
        }
      }
      if (jank > 0 && mounted) {
        setState(() => _jankFrames += jank);
      }
    };
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
    NativeImageMetrics.instance.addListener(_onMetrics);
    _load();
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);
    NativeImageMetrics.instance.removeListener(_onMetrics);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onMetrics() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didHaveMemoryPressure() {
    setState(() => _memoryPressureEvents++);
  }

  Future<void> _load() async {
    final PermissionState permission =
        await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      setState(() => _errorText = 'Photo library access was denied.');
      return;
    }
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      filterOption: FilterOptionGroup(
        orders: <OrderOption>[
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _albums = albums);
    if (albums.isNotEmpty) {
      await _selectAlbum(albums.first);
    }
  }

  Future<void> _selectAlbum(AssetPathEntity album) async {
    setState(() {
      _album = album;
      _assets = const <AssetEntity>[];
    });
    final List<AssetEntity> page =
        await album.getAssetListPaged(page: 0, size: 300);
    if (mounted && _album == album) {
      setState(() => _assets = page);
    }
  }

  Future<void> _loadMore() async {
    final AssetPathEntity? album = _album;
    if (album == null || _loadingMore) {
      return;
    }
    _loadingMore = true;
    try {
      final List<AssetEntity> more = await album.getAssetListRange(
        start: _assets.length,
        end: _assets.length + 300,
      );
      if (mounted && _album == album && more.isNotEmpty) {
        setState(() => _assets = <AssetEntity>[..._assets, ...more]);
      }
    } finally {
      _loadingMore = false;
    }
  }

  void _onScaleStart(ScaleStartDetails details) => _pinchBase = 1;

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      return;
    }
    final double ratio = details.scale / _pinchBase;
    if (ratio > 1.35 && _columnIndex > 0) {
      _pinchBase = details.scale;
      setState(() => _columnIndex--);
    } else if (ratio < 0.74 && _columnIndex < kColumnSteps.length - 1) {
      _pinchBase = details.scale;
      setState(() => _columnIndex++);
    }
  }

  void _forceMemoryPressure() {
    // ignore: invalid_use_of_protected_member
    PaintingBinding.instance.handleMemoryPressure();
    didHaveMemoryPressure();
  }

  void _resetMetrics() {
    NativeImageMetrics.instance.reset();
    setState(() {
      _jankFrames = 0;
      _memoryPressureEvents = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int columns = kColumnSteps[_columnIndex];
    return Scaffold(
      appBar: AppBar(
        title: Text(_album?.name ?? 'Native thumbnails'),
        actions: <Widget>[
          if (_albums.isNotEmpty)
            PopupMenuButton<AssetPathEntity>(
              icon: const Icon(Icons.photo_album_outlined),
              onSelected: _selectAlbum,
              itemBuilder: (BuildContext context) => <PopupMenuEntry<AssetPathEntity>>[
                for (final AssetPathEntity album in _albums)
                  PopupMenuItem<AssetPathEntity>(
                    value: album,
                    child: Text(album.name),
                  ),
              ],
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _buildGrid(columns)),
          _MetricsPanel(
            columns: columns,
            jankFrames: _jankFrames,
            memoryPressureEvents: _memoryPressureEvents,
            onReset: _resetMetrics,
            onMemoryPressure: _forceMemoryPressure,
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(int columns) {
    if (_errorText != null) {
      return Center(child: Text(_errorText!));
    }
    if (_album == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final bool dense = columns >= 10;
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification.metrics.extentAfter < 600) {
            _loadMore();
          }
          return false;
        },
        child: GridView.builder(
          key: ValueKey<int>(columns),
          // Kept for Flutter < 3.42, where scrollCacheExtent does not exist.
          // ignore: deprecated_member_use
          cacheExtent: 600,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 1,
            crossAxisSpacing: 1,
          ),
          itemCount: _assets.length,
          itemBuilder: (BuildContext context, int index) {
            return _Cell(asset: _assets[index], dense: dense);
          },
        ),
      ),
    );
  }
}

/// `Stack[base 128, main 320]`: the base layer is shared by every column
/// count, so pinching never re-requests it.
class _Cell extends StatelessWidget {
  const _Cell({required this.asset, required this.dense});

  final AssetEntity asset;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        NativeAssetImage(asset, size: kBaseSize, errorBuilder: _error),
        if (!dense)
          NativeAssetImage(asset, size: kMainSize, errorBuilder: _error),
        if (asset.type == AssetType.video && !dense)
          const Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.play_circle, color: Colors.white, size: 18),
            ),
          ),
      ],
    );
  }

  Widget _error(BuildContext context, Object error, StackTrace? stack) {
    final bool icloud = error is NativeImageException &&
        error.code == NativeImageErrorCode.icloudNotDownloaded;
    return ColoredBox(
      color: Colors.black12,
      child: Icon(
        icloud ? Icons.cloud_download_outlined : Icons.broken_image_outlined,
        size: 16,
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({
    required this.columns,
    required this.jankFrames,
    required this.memoryPressureEvents,
    required this.onReset,
    required this.onMemoryPressure,
  });

  final int columns;
  final int jankFrames;
  final int memoryPressureEvents;
  final VoidCallback onReset;
  final VoidCallback onMemoryPressure;

  @override
  Widget build(BuildContext context) {
    final NativeImageMetrics m = NativeImageMetrics.instance;
    final TextStyle style = Theme.of(context).textTheme.bodySmall!.copyWith(
          fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
        );
    String cell(String label, Object? value) => '$label ${value ?? '-'}';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: DefaultTextStyle(
            style: style,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: 12,
                  children: <Widget>[
                    Text(cell('cols', columns)),
                    Text(cell('req', m.requested)),
                    Text(cell('done', m.completed)),
                    Text(cell('cancel', m.cancelled)),
                    Text(cell('fail', m.failed)),
                    Text(cell('inflight', m.inFlight)),
                    Text(cell('maxInflight', m.maxInFlight)),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  children: <Widget>[
                    Text(cell('p50', m.percentile(0.5)?.toString().padLeft(3))),
                    Text(cell('p95', m.percentile(0.95)?.toString().padLeft(3))),
                    Text(cell('>16ms', jankFrames)),
                    Text(cell('memPressure', memoryPressureEvents)),
                    Text(
                      cell('liveBuf', m.liveBuffers),
                      style: m.liveBuffers == 0
                          ? null
                          : style.copyWith(color: Colors.red),
                    ),
                    Text(cell('cache', imageCache.currentSize)),
                  ],
                ),
                Row(
                  children: <Widget>[
                    TextButton(onPressed: onReset, child: const Text('Reset')),
                    TextButton(
                      onPressed: onMemoryPressure,
                      child: const Text('Memory pressure'),
                    ),
                    TextButton(
                      onPressed: () => debugPrint(
                        'latencies=${m.latenciesMs}',
                      ),
                      child: const Text('Dump'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
