import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/discover_notifier.dart';
import '../widgets/message_view.dart';
import '../widgets/stream_tile.dart';
import '../../../../core/layout/breakpoints.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late final DiscoverNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = context.read<DiscoverNotifier>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifier.load());
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DiscoverNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('Découvrir')),
      // Contenu borné et centré au-delà de la rupture (STR-244) : sans cela,
      // une ligne de flux traverse 800 px en paysage pour trois mots. Sans
      // effet sur un téléphone en portrait, où la contrainte ne mord pas.
      body: SafeArea(
        child: ResponsiveContent(
          child: RefreshIndicator(
            onRefresh: _notifier.load,
            child: _buildBody(context, notifier),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DiscoverNotifier notifier) {
    if (notifier.isLoading && notifier.streams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifier.hasError && notifier.streams.isEmpty) {
      return MessageView(
        icon: Icons.wifi_off_outlined,
        message: 'Impossible de charger les flux',
        actionLabel: 'Réessayer',
        onAction: _notifier.load,
      );
    }

    if (notifier.isEmpty) {
      return const MessageView(
        icon: Icons.podcasts_outlined,
        message: 'Aucun flux en direct pour le moment',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: notifier.streams.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => StreamTile(stream: notifier.streams[index]),
    );
  }
}

