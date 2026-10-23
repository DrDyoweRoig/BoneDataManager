import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const ProviderScope(child: BoneDataManagerApp()));
}

class BoneDataManagerApp extends ConsumerWidget {
  const BoneDataManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(openStoreProvider);
    return MaterialApp(
      title: 'Bone Data Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: store == null
          ? const HomeScreen()
          : Scaffold(appBar: AppBar(title: Text(store.def.name))),
    );
  }
}
