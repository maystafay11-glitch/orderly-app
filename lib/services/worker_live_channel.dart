import 'package:orderly_app/services/_worker_live_channel_stub.dart'
    if (dart.library.js_interop)
        'package:orderly_app/services/_worker_live_channel_web.dart' as impl;

/// قناة بث Firebase REST (`text/event-stream`) لتحديث الطلبات فور تغيّر heartbeat.
class WorkerLiveChannel {
  WorkerLiveChannel() : _inner = impl.createChannel();

  final impl.WorkerLiveChannelImpl _inner;

  void start({required String streamUrl, required void Function() onChange}) {
    _inner.start(streamUrl: streamUrl, onChange: onChange);
  }

  void stop() => _inner.stop();
}
