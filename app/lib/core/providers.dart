import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'rest_client.dart';

final restClientProvider = Provider<RestClient>((ref) {
  final client = RestClient();
  ref.onDispose(client.close);
  return client;
});

/// The six pilot packages. Content never changes at runtime, so one fetch
/// cached for the session is enough.
final packagesProvider = FutureProvider<List<PackageSummary>>((ref) {
  return ref.watch(restClientProvider).packages();
});
