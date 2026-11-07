part of 'outdoor_landscape.dart';

/// The city's suspension bridge: portal towers with X-bracing on concrete
/// piers, parabolic main cables strung with LEDs, glowing suspenders and a
/// truss deck lit warm from within. Everything hangs off the road's own
/// centreline, so the deck the cars drive on is the deck the cables carry.
extension _CityBridge on CityScene {
  static const _steel = _Rgb.hex(0xA4ABB1);
  static const _concrete = _Rgb.hex(0xA9A69E);
  static const _led = _Rgb.hex(0xDCEBFF);
  static const _cableAcross = 1.35;
  static const double _towerTop = 12.5;

  (double, double, double) _onRoad(double s, double across, double y) {
    final p = _road.at(s);
    return (
      _worldX(p.u - math.sin(p.heading) * across),
      y,
      _worldZ(p.v + math.cos(p.heading) * across),
    );
  }

  /// Horizontal unit vector for flat glows to spread along so they face the
  /// window instead of turning edge-on to it.
  (double, double) _facingRight((double, double, double) p) {
    final dx = OutdoorScene._eyeX - p.$1;
    final dz = _eyeZ - p.$3;
    final length = math.sqrt(dx * dx + dz * dz);
    return (dz / length, -dx / length);
  }

  void _buildBridge(_LitMesh mesh) {
    final road = _road;
    final start = road.bridgeStart;
    final end = road.bridgeEnd;
    final span = end - start;
    final towers = [start + span * 0.22, start + span * 0.8];
    final mid = (towers[0] + towers[1]) / 2;
    final half = (towers[1] - towers[0]) / 2;
    final lowPoint = road.at(mid).y + 0.75;

    double cableY(double s) {
      if (s >= towers[0] && s <= towers[1]) {
        final k = (s - mid) / half;
        return lowPoint + (_towerTop - lowPoint) * k * k;
      }
      // Side spans fall from the tower top to anchor at the deck, with a sag.
      final anchor = s < towers[0] ? start : end;
      final tower = s < towers[0] ? towers[0] : towers[1];
      final t = (s - anchor) / (tower - anchor);
      final anchorY = road.at(anchor).y + 0.2;
      return anchorY + (_towerTop - anchorY) * t - 0.9 * t * (1 - t);
    }

    for (final tower in towers) {
      _buildTower(mesh, tower);
    }
    _buildCables(mesh, start, end, towers, cableY);
    _buildTruss(mesh, start, end);
    _bakeBridgeReflection(start, end, towers, cableY);
  }

  void _buildTower(_LitMesh mesh, double s) {
    final road = _road;
    final p = road.at(s);
    final deck = p.y;
    final pierTop = CityScene._water + 1.0;
    const legAcross = 1.75;
    const topAcross = 1.5;
    const legColor = _Rgb.hex(0x8A9198);
    const legGlow = _Rgb.hex(0x3D4654);
    const braceGlow = _Rgb.hex(0x2C333E);

    double acrossAt(double y) {
      final t = (y - pierTop) / (_towerTop - pierTop);
      return legAcross + (topAcross - legAcross) * t;
    }

    (double, double, double) leg(double side, double y) =>
        _onRoad(s, side * acrossAt(y), y);

    for (final side in const [-1.0, 1.0]) {
      _addBeam(
        mesh,
        leg(side, pierTop),
        leg(side, _towerTop),
        0.46,
        legColor,
        emissive: legGlow,
      );
    }
    void strut(double y, double thickness) => _addBeam(
      mesh,
      leg(-1, y),
      leg(1, y),
      thickness,
      legColor,
      emissive: braceGlow,
    );
    void braced(double y0, double y1) {
      strut(y1, 0.2);
      for (final side in const [-1.0, 1.0]) {
        _addBeam(
          mesh,
          leg(side, y0),
          leg(-side, y1),
          0.13,
          legColor,
          emissive: braceGlow,
        );
      }
    }

    // X-bracing below the deck and above the traffic.
    final underDeck = deck - 0.85;
    final lowerMid = (pierTop + underDeck) / 2;
    braced(pierTop + 0.1, lowerMid);
    braced(lowerMid, underDeck);
    final clear = deck + 2.6;
    final panel = (_towerTop - 0.6 - clear) / 3;
    strut(clear, 0.2);
    for (var i = 0; i < 3; i += 1) {
      braced(clear + panel * i, clear + panel * (i + 1));
    }
    // Saddle across the top, with a single red light.
    strut(_towerTop, 0.5);
    final top = _onRoad(s, 0, _towerTop + 0.6);
    _addBeam(mesh, _onRoad(s, 0, _towerTop), top, 0.07, legColor);
    _addBeacon(mesh, top.$1, top.$2, top.$3);

    // Concrete pier, stepped, with lights around it at the waterline.
    for (final (width, across, y0, y1) in [
      (2.0, 5.4, CityScene._water - 0.6, CityScene._water + 0.45),
      (1.5, 4.7, CityScene._water + 0.45, pierTop),
    ]) {
      final c = _onRoad(s, 0, (y0 + y1) / 2);
      _addBox(
        mesh,
        c.$1,
        c.$2,
        c.$3,
        width: width,
        height: y1 - y0,
        depth: across,
        yaw: p.heading,
        color: _concrete,
        emissive: const _Rgb.hex(0x35332F),
      );
    }
    final lightY = CityScene._water + 0.5;
    for (var i = -3; i <= 3; i += 1) {
      final light = _onRoad(s + 1.05, i * 0.75, lightY);
      final warm = i.isEven;
      _pierLight(light, warm);
    }
    for (final along in const [-0.6, 0.0, 0.6]) {
      _pierLight(_onRoad(s + along, -2.75, lightY), along == 0);
    }
  }

  void _pierLight((double, double, double) p, bool warm) {
    final color = warm ? const _Rgb.hex(0xFFD49A) : const _Rgb.hex(0xE8F1FF);
    _halos.fan(p, 0.17, color, right: _facingRight(p));
  }

  void _buildCables(
    _LitMesh mesh,
    double start,
    double end,
    List<double> towers,
    double Function(double) cableY,
  ) {
    const step = 0.6;
    final steps = ((end - start) / step).floor();
    // The camera sees the road from its -across side: that plane burns
    // brightest, the far one shows through behind it.
    for (final side in const [-1.0, 1.0]) {
      final near = side < 0;
      final across = side * _cableAcross;
      final ledColor = near ? _led : _led.scale(0.36);
      final hangerGlow = near
          ? const _Rgb.hex(0xE4EEFF)
          : const _Rgb.hex(0x56688A);
      for (var i = 0; i < steps; i += 1) {
        final s0 = start + i * step;
        final s1 = s0 + step;
        final a = _onRoad(s0, across, cableY(s0));
        _addBeam(
          mesh,
          a,
          _onRoad(s1, across, cableY(s1)),
          0.05,
          _steel,
          emissive: const _Rgb.hex(0x4A566C),
        );
        // A bead of LEDs on the cable at every suspender.
        final facing = _facingRight(a);
        _halos.fan(a, near ? 0.2 : 0.11, ledColor.scale(0.6), right: facing);
        if (near) {
          // A tight, hot centre so each bead reads as a point of light.
          _halos.fan(a, 0.075, const _Rgb(1, 1, 1), right: facing);
        }
        if (towers.any((tower) => (tower - s0).abs() < 0.5) || i == 0) {
          continue;
        }
        final foot = _onRoad(s0, across, _road.at(s0).y + 0.1);
        _addBeam(mesh, a, foot, 0.026, _steel, emissive: hangerGlow);
        if (near) {
          _hangerGlow(a, foot);
        }
      }
    }
  }

  /// The bloom around a lit suspender, soft on both sides.
  void _hangerGlow(
    (double, double, double) top,
    (double, double, double) foot,
  ) {
    final (rx, rz) = _facingRight(top);
    const width = 0.09;
    const glow = _Rgb(0.15, 0.22, 0.34);
    const dark = _Rgb(0, 0, 0);
    (double, double, double) off((double, double, double) p, double k) =>
        (p.$1 + rx * width * k, p.$2, p.$3 + rz * width * k);
    _halos
      ..quadColors(
        off(foot, -1),
        foot,
        top,
        off(top, -1),
        dark,
        glow,
        glow,
        dark,
      )
      ..quadColors(
        foot,
        off(foot, 1),
        off(top, 1),
        top,
        glow,
        dark,
        dark,
        glow,
      );
  }

  /// Writes the lit bridge into the river's reflection map.
  void _bakeBridgeReflection(
    double start,
    double end,
    List<double> towers,
    double Function(double) cableY,
  ) {
    final span = end - start;
    _river.setBridgeSpan(
      _onRoad(start, -_cableAcross, 0),
      _onRoad(end, -_cableAcross, 0),
    );
    const hanger = _Rgb(0.55, 0.68, 0.9);
    const truss = _Rgb(0.42, 0.3, 0.16);
    const towerLight = _Rgb(0.13, 0.15, 0.19);
    for (var s = start; s < end; s += 0.6) {
      final along = (s - start) / span;
      final deck = _road.at(s).y;
      final cable = cableY(s);
      for (var y = deck; y < cable; y += 0.25) {
        _river.plotBridge(along, y, hanger, radius: 0.2);
      }
      _river.plotBridge(along, cable, _led, radius: 1);
      for (var y = deck - 0.72; y < deck; y += 0.25) {
        _river.plotBridge(along, y, truss, radius: 1);
      }
    }
    for (final tower in towers) {
      final along = (tower - start) / span;
      for (var y = CityScene._water + 0.5; y < _towerTop; y += 0.2) {
        _river.plotBridge(along - 0.012, y, towerLight, radius: 1);
        _river.plotBridge(along + 0.012, y, towerLight, radius: 1);
      }
    }
  }

  void _buildTruss(_LitMesh mesh, double start, double end) {
    const bay = 0.9;
    const depth = 0.72;
    final bays = ((end - start) / bay).floor();
    const chord = _Rgb.hex(0x7C8288);
    for (final side in const [-1.0, 1.0]) {
      final near = side < 0;
      final across = side * _CityRoad.halfWidth;
      // Warm light from the deck catches the lattice.
      final lit = near ? const _Rgb.hex(0xA87C46) : const _Rgb.hex(0x5C462C);
      for (var i = 0; i < bays; i += 1) {
        final s0 = start + i * bay;
        final sm = s0 + bay / 2;
        final s1 = s0 + bay;
        final top0 = _onRoad(s0, across, _road.at(s0).y - 0.04);
        final top1 = _onRoad(s1, across, _road.at(s1).y - 0.04);
        final low = _onRoad(sm, across, _road.at(sm).y - depth);
        final low1 = _onRoad(s1 + bay / 2, across, _road.at(s1).y - depth);
        _addBeam(mesh, top0, low, 0.05, chord, emissive: lit);
        _addBeam(mesh, low, top1, 0.05, chord, emissive: lit);
        _addBeam(mesh, top0, top1, 0.07, chord, emissive: lit.scale(0.7));
        if (i < bays - 1) {
          _addBeam(mesh, low, low1, 0.08, chord, emissive: lit.scale(0.42));
        }
        if (near) {
          // Glow pooled in the lattice, fading toward the bottom chord.
          const warm = _Rgb(0.2, 0.13, 0.06);
          const dark = _Rgb(0, 0, 0);
          _halos.quadColors(
            _onRoad(s0, across, _road.at(s0).y - depth),
            _onRoad(s1, across, _road.at(s1).y - depth),
            top1,
            top0,
            dark,
            dark,
            warm,
            warm,
          );
        }
      }
    }
    // Cross members tie the two trusses together underneath.
    for (var i = 0; i < bays; i += 2) {
      final s = start + (i + 0.5) * bay;
      final y = _road.at(s).y - depth;
      _addBeam(
        mesh,
        _onRoad(s, -_CityRoad.halfWidth, y),
        _onRoad(s, _CityRoad.halfWidth, y),
        0.07,
        chord,
      );
    }
    // Teal navigation lights slung under the channel.
    for (var t = 0.08; t < 1; t += 0.14) {
      final s = start + (end - start) * t;
      final p = _onRoad(s, -_CityRoad.halfWidth, _road.at(s).y - depth - 0.1);
      _halos.fan(p, 0.2, const _Rgb.hex(0x2BFFC4), right: _facingRight(p));
    }
  }
}
