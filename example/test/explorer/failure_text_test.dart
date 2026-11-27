import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/features/explorer/failure_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GATT errors name the ATT error', () {
    expect(
      explainFailure(GattException(GattError.readNotPermitted, 'read')),
      'Read not permitted (ATT error 0x02)',
    );
    expect(
      explainFailure(GattException(GattError.insufficientEncryption, 'write')),
      'Insufficient encryption (ATT error 0x0F)',
    );
  });

  test('unknown GATT errors show the native status', () {
    expect(
      explainFailure(GattException(GattError.unknown, 'read', nativeCode: 133)),
      'GATT error 133',
    );
  });

  test('timeouts show the duration', () {
    expect(
      explainFailure(
        OperationTimeoutException('read', const Duration(seconds: 10)),
      ),
      'No answer within 10 s',
    );
    expect(
      explainFailure(
        OperationTimeoutException('read', const Duration(milliseconds: 1500)),
      ),
      'No answer within 1500 ms',
    );
  });

  test('connection failures', () {
    expect(
      explainFailure(const DisconnectedException()),
      'Not connected to the device',
    );
    expect(
      explainFailure(
        const ConnectionException('Connection failed', nativeCode: 133),
      ),
      'Could not connect (status 133)',
    );
    expect(explainFailure(const OperationCancelledException()), 'Cancelled');
  });

  test('platform refusals keep their message', () {
    expect(
      explainFailure(
        const NativeOperationException('Android rejected the read request'),
      ),
      'Android rejected the read request',
    );
  });
}
