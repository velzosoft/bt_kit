import 'package:material_ui/material_ui.dart';

import '../../bluetooth/device_kind.dart';
import '../../widgets/kind_style.dart';

/// What is being hunted: the kind's icon, a name and a detail line.
class TargetHeader extends StatelessWidget {
  const TargetHeader({
    super.key,
    required this.kind,
    required this.title,
    required this.detail,
  });

  final DeviceKind kind;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        KindAvatar(kind, size: 48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                detail,
                style: text.bodyMedium?.copyWith(color: kind.color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
