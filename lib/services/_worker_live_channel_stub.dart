class WorkerLiveChannelImpl {
  void start({required String streamUrl, required void Function() onChange}) {}

  void stop() {}
}

WorkerLiveChannelImpl createChannel() => WorkerLiveChannelImpl();
