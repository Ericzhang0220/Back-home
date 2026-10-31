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
    required this.outdoorEnvironment,
    required this.onOutdoorEnvironment,
    super.key,
  });

  final SkyWeather skyWeather;
  final bool weatherAuto;
  final double? skyTimeOfDay;
  final ValueChanged<SkyWeather> onSkyWeather;
  final VoidCallback onWeatherAuto;
  final ValueChanged<double> onSkyTimeOfDay;
  final OutdoorEnvironment outdoorEnvironment;
  final ValueChanged<OutdoorEnvironment> onOutdoorEnvironment;

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

  static const Map<OutdoorEnvironment, ({String label, IconData icon})>
  _environments = {
    OutdoorEnvironment.island: (label: 'Island', icon: Icons.landscape_rounded),
    OutdoorEnvironment.waterfall: (
      label: 'Waterfall',
      icon: Icons.water_rounded,
    ),
    OutdoorEnvironment.city: (label: 'City', icon: Icons.location_city_rounded),
    OutdoorEnvironment.forest: (label: 'Forest', icon: Icons.forest_rounded),
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
            for (final entry in _environments.entries)
              ChoiceChip(
                avatar: Icon(entry.value.icon, size: 18),
                label: Text(entry.value.label),
                selected: outdoorEnvironment == entry.key,
                onSelected: (_) => onOutdoorEnvironment(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
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
