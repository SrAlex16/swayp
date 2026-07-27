import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/core/device/device_id_provider.dart';

void main() {
  test('genera un uuid v4 la primera vez y lo persiste', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final deviceId = await container.read(deviceIdProvider.future);

    expect(
      deviceId,
      matches(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('device_id'), deviceId);
  });

  test('en una apertura posterior, lee el mismo valor ya guardado', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'existing-device-id'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final deviceId = await container.read(deviceIdProvider.future);

    expect(deviceId, 'existing-device-id');
  });
}
