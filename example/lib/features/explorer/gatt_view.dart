import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'connection_banner.dart';
import 'explorer_controller.dart';
import 'link_card.dart';
import 'service_card.dart';

/// The discovered services, under the live connection state.
class GattView extends StatelessWidget {
  const GattView(this.explorer, {super.key});

  final ExplorerController explorer;

  @override
  Widget build(BuildContext context) {
    final services = explorer.services;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConnectionBanner(explorer),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: [
              LinkCard(explorer),
              if (services.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'This device lists no services.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: RadarColors.muted),
                  ),
                ),
              for (final service in services)
                ServiceCard(service: service, explorer: explorer),
            ],
          ),
        ),
      ],
    );
  }
}
