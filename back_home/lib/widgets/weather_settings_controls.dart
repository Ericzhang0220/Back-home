import 'package:flutter/material.dart';

import '../rooms/room_state.dart';

class WeatherSettingsControls extends StatelessWidget {
  const WeatherSettingsControls({
    required this.skyWeather,
    required this.weatherAuto,
    required this.skyTimeOfDay,
    required this.onSkyWeather,
    required this.onWeatherAuto,
    required this.onSkyTimeOfDay,
    super.key,
  });

  final SkyWeather skyWeather;
  final bool weatherAuto;
  final double? skyTimeOfDay;
  final ValueChanged<SkyWeather> onSkyWeather;
  final VoidCallback onWeatherAuto;
  final ValueChanged<double> onSkyTimeOfDay;

  static const List<({String label, double value})> _skyTimes = [
    (label: 'Dawn', value: 0.26),
    (label: 'Day', value: 0.5),
    (label: 'Dusk', value: 0.73),
    (label: 'Night', value: 0.95),
  ];

  String _weatherLabel(SkyWeather weather) => switch (weather) {
    SkyWeather.clear => 'Clear',
    SkyWeather.cloudy => 'Cloudy',
    SkyWeather.overcast => 'Overcast',
    SkyWeather.rain => 'Rain',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('Auto'),
              selected: weatherAuto,
              onSelected: (_) => onWeatherAuto(),
            ),
            for (final weather in SkyWeather.values)
              ChoiceChip(
                label: Text(_weatherLabel(weather)),
                selected: !weatherAuto && skyWeather == weather,
                onSelected: (_) => onSkyWeather(weather),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final time in _skyTimes)
              ChoiceChip(
                label: Text(time.label),
                selected: skyTimeOfDay == time.value,
                onSelected: (_) => onSkyTimeOfDay(time.value),
              ),
          ],
        ),
      ],
    );
  }
}
