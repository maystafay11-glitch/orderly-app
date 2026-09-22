import 'dart:js_interop';

import 'package:web/web.dart' as web;

class WorkerLiveChannelImpl {
  web.EventSource? _source;

  void start({required String streamUrl, required void Function() onChange}) {
    stop();
    if (streamUrl.trim().isEmpty) return;
    try {
      final web.EventSource source = web.EventSource(streamUrl);
      final JSFunction handler = ((web.Event _) {
        onChange();
      }).toJS;
      source
        ..addEventListener('put', handler)
        ..addEventListener('patch', handler)
        ..addEventListener('keep-alive', handler);
      _source = source;
    } catch (_) {
      _source = null;
    }
  }

  void stop() {
    try {
      _source?.close();
    } catch (_) {
      // تجاهل
    }
    _source = null;
  }
}

WorkerLiveChannelImpl createChannel() => WorkerLiveChannelImpl();
