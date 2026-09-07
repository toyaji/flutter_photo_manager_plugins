import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager_native_image/photo_manager_native_image.dart';

import 'fake_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChannel channel;
  late int frees;

  setUp(() {
    channel = FakeChannel();
    frees = 0;
    PaintingBinding.instance.imageCache.clear();
  });

  NativeImageProvider provider({String id = 'a'}) {
    return NativeImageProvider(
      entity(id: id),
      size: 32,
      channel: channel,
      debugFree: (Pointer<Uint8> p) {
        frees++;
        malloc.free(p);
      },
    );
  }

  test('removing the widget listener cancels and evicts the pending key',
      () async {
    final NativeImageProvider p = provider();
    final ImageStream stream = p.resolve(ImageConfiguration.empty);
    final ImageStreamListener widget = ImageStreamListener((_, __) {});
    stream.addListener(widget);
    await Future<void>.delayed(Duration.zero);
    expect(channel.requested, hasLength(1));
    expect(PaintingBinding.instance.imageCache.pendingImageCount, 1);

    stream.removeListener(widget);
    expect(channel.cancelled, channel.requested);
    expect(PaintingBinding.instance.imageCache.pendingImageCount, 0);

    channel.reply(channel.requested.single, allocateBuffer(4, 4));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(frees, 1);
  });

  test('a delivered image is kept in the cache', () async {
    final NativeImageProvider p = provider(id: 'b');
    final ImageStream stream = p.resolve(ImageConfiguration.empty);
    ImageInfo? received;
    final ImageStreamListener widget =
        ImageStreamListener((ImageInfo info, _) => received = info);
    stream.addListener(widget);
    await Future<void>.delayed(Duration.zero);
    channel.reply(channel.requested.single, allocateBuffer(4, 4));
    await pumpEventQueue();
    expect(received, isNotNull);
    expect(received!.image.width, 4);
    expect(channel.cancelled, isEmpty);
    expect(PaintingBinding.instance.imageCache.currentSize, 1);
    stream.removeListener(widget);
    received!.dispose();
  });

  test('errors reach the stream as NativeImageException', () async {
    final NativeImageProvider p = provider(id: 'c');
    final ImageStream stream = p.resolve(ImageConfiguration.empty);
    Object? error;
    final ImageStreamListener widget = ImageStreamListener(
      (_, __) {},
      onError: (Object e, StackTrace? s) => error = e,
    );
    stream.addListener(widget);
    await Future<void>.delayed(Duration.zero);
    channel.fail(channel.requested.single, 'icloud_not_downloaded');
    await pumpEventQueue();
    expect(
      error,
      isA<NativeImageException>().having(
        (e) => e.code,
        'code',
        NativeImageErrorCode.icloudNotDownloaded,
      ),
    );
    expect(PaintingBinding.instance.imageCache.pendingImageCount, 0);
    stream.removeListener(widget);
  });

  test('imageCache.clear() while loading does not cancel a visible image',
      () async {
    final NativeImageProvider p = provider(id: 'd');
    final ImageStream stream = p.resolve(ImageConfiguration.empty);
    ui.Image? received;
    final ImageStreamListener widget =
        ImageStreamListener((ImageInfo info, _) => received = info.image);
    stream.addListener(widget);
    await Future<void>.delayed(Duration.zero);
    PaintingBinding.instance.imageCache.clear();
    expect(channel.cancelled, isEmpty);
    channel.reply(channel.requested.single, allocateBuffer(4, 4));
    await pumpEventQueue();
    expect(received, isNotNull);
    stream.removeListener(widget);
  });
}
