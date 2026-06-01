import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_read.dart';
import '../services/reads_service.dart';
import 'providers.dart';

final readsServiceProvider = Provider<ReadsService>((ref) => ReadsService());

final readsProvider = FutureProvider<List<PlayerRead>>((ref) {
  ref.watch(authUserIdProvider); // re-fetch when user changes
  return ref.watch(readsServiceProvider).fetchReads();
});
