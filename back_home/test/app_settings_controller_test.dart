import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/settings/app_settings_controller.dart';
import 'package:back_home/widgets/weather_settings_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weather Auto restores current weather and current time together', () {
    final controller = AppSettingsController();

    controller.setSkyWeather(SkyWeather.rain);
    controller.setSkyTimeOfDay(0.73);

    expect(controller.weatherAuto, isFalse);
    expect(controller.skyWeather, SkyWeather.rain);
    expect(controller.skyTimeOfDay, 0.73);

    controller.setWeatherAuto();

    expect(controller.weatherAuto, isTrue);
    expect(controller.skyTimeOfDay, isNull);
  });

  test('a manual time turns off combined Auto mode', () {
    final controller = AppSettingsController();

    controller.setSkyTimeOfDay(0.95);

    expect(controller.weatherAuto, isFalse);
    expect(controller.skyTimeOfDay, 0.95);
  });

  testWidgets('weather controls no longer show a separate Live chip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeatherSettingsControls(
            skyWeather: SkyWeather.clear,
            weatherAuto: true,
            skyTimeOfDay: null,
            onSkyWeather: (_) {},
            onWeatherAuto: () {},
            onSkyTimeOfDay: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Live'), findsNothing);
  });
}
