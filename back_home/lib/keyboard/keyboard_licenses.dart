import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

void registerCharacterKeyboardLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final package in ['rime-pinyin-simp', 'noto-cjk']) {
      final license = await rootBundle.loadString(
        'third_party/$package/LICENSE',
      );
      final notice = await rootBundle.loadString('third_party/$package/NOTICE');
      yield LicenseEntryWithLineBreaks([package], '$notice\n\n$license');
    }
  });
}
