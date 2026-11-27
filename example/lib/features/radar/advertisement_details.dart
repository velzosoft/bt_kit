import 'package:bt_kit/bt_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/assigned_numbers.dart';
import '../../bluetooth/hex.dart';

/// The parsed fields of an advertisement, as label and value pairs.
List<(String, String)> describeAdvertisement(
  AdvertisementData data, {
  int maxBytes = 12,
}) => [
  if (data.localName case final name?) ('Name', name),
  if (data.serviceUuids.isNotEmpty)
    ('Services', data.serviceUuids.map(_serviceLabel).join(', ')),
  for (final MapEntry(key: uuid, value: bytes) in data.serviceData.entries)
    ('Data ${_serviceLabel(uuid)}', bytes.toHex(max: maxBytes)),
  for (final MapEntry(key: company, value: bytes)
      in data.manufacturerData.entries)
    (_companyLabel(company), bytes.isEmpty ? '-' : bytes.toHex(max: maxBytes)),
  if (data.txPowerLevel case final power?) ('Tx power', '$power dBm'),
  if (data.appearance case final appearance?)
    ('Appearance', AssignedNumbers.hex16(appearance)),
  if (data.isConnectable case final connectable?)
    ('Connectable', connectable ? 'Yes' : 'No'),
];

/// Short UUIDs stay next to their name; a known 128-bit UUID is too long
/// to be worth showing.
String _serviceLabel(BluetoothUuid uuid) =>
    switch ((AssignedNumbers.serviceName(uuid), uuid.shortValue)) {
      (null, _) => '$uuid',
      (final name?, null) => name,
      (final name?, _) => '$name ($uuid)',
    };

String _companyLabel(int company) {
  final name = AssignedNumbers.companyName(company);
  final id = AssignedNumbers.hex16(company);
  return name == null ? 'Company $id' : '$name $id';
}

/// [describeAdvertisement] as a compact two-column table.
class AdvertisementTable extends StatelessWidget {
  const AdvertisementTable(this.data, {super.key, this.maxBytes = 12});

  final AdvertisementData data;
  final int maxBytes;

  @override
  Widget build(BuildContext context) {
    final rows = describeAdvertisement(data, maxBytes: maxBytes);
    final style = Theme.of(context).textTheme.bodySmall;
    if (rows.isEmpty) {
      return Text('Empty advertisement', style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    label,
                    style: style?.copyWith(color: RadarColors.muted),
                  ),
                ),
                Expanded(child: Text(value, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}
