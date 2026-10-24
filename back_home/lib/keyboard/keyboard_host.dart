import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'keyboard_catalog.dart';
import 'keyboard_editing.dart';
import 'keyboard_licenses.dart';
import 'keyboard_panel.dart';
import 'keyboard_store.dart';

class KeyboardStoreScope extends InheritedNotifier<KeyboardStore> {
  const KeyboardStoreScope({
    super.key,
    required KeyboardStore store,
    required super.child,
  }) : super(notifier: store);
  static KeyboardStore? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<KeyboardStoreScope>()
      ?.notifier;
}

/// Marks an AI input without changing its controller, formatters or selection.
class KeyboardTarget extends InheritedWidget {
  const KeyboardTarget({
    super.key,
    required this.isAi,
    this.artworkAsset,
    required super.child,
  });
  final bool isAi;
  final String? artworkAsset;
  @override
  bool updateShouldNotify(KeyboardTarget oldWidget) =>
      oldWidget.isAi != isAi || oldWidget.artworkAsset != artworkAsset;
}

class AppKeyboardHost extends StatefulWidget {
  const AppKeyboardHost({super.key, required this.store, required this.child});
  final KeyboardStore store;
  final Widget child;
  @override
  State<AppKeyboardHost> createState() => _AppKeyboardHostState();
}

class _AppKeyboardHostState extends State<AppKeyboardHost> {
  late final _CharacterInputControl _control;
  bool _installed = false;
  bool _scheduled = false;
  FocusNode? _systemForFocus;
  String? _artwork;

  @override
  void initState() {
    super.initState();
    registerCharacterKeyboardLicenses();
    _control = _CharacterInputControl()..addListener(_redraw);
    widget.store.addListener(_focusChanged);
    FocusManager.instance.addListener(_focusChanged);
  }

  void _redraw() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_scheduled) return;
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _focusChanged() {
    if (!mounted) return;
    final node = FocusManager.instance.primaryFocus;
    final context = node?.context;
    final field = context?.findAncestorStateOfType<EditableTextState>();
    final target = context?.getInheritedWidgetOfExactType<KeyboardTarget>();
    final useCustom =
        field != null &&
        !field.widget.readOnly &&
        !field.widget.obscureText &&
        node != _systemForFocus &&
        widget.store.ready &&
        widget.store.enabled &&
        (widget.store.scope == KeyboardUseScope.allPages ||
            target?.isAi == true);
    if (!useCustom) {
      if (_installed) {
        _installed = false;
        _control.hide();
        TextInput.restorePlatformInputControl();
        if (field != null) {
          unawaited(
            SystemChannels.textInput.invokeMethod<void>(
              'TextInput.updateConfig',
              field.textInputConfiguration.toJson(),
            ),
          );
        }
      }
      if (node != _systemForFocus) _systemForFocus = null;
      return;
    }
    _artwork = target?.artworkAsset;
    if (!_installed) {
      _installed = true;
      TextInput.setInputControl(_control);
    }
    _control.attach(field, field.textInputConfiguration);
    _control.setEditingState(field.widget.controller.value);
    // Refresh an already-open native connection as well as future connections.
    // TextInputControl makes Flutter use type=none for new native clients.
    final config = field.textInputConfiguration.toJson();
    config['inputType'] = TextInputType.none.toJson();
    unawaited(
      SystemChannels.textInput.invokeMethod<void>(
        'TextInput.updateConfig',
        config,
      ),
    );
    _control.show();
    _redraw();
  }

  void _useSystem() {
    _control.editing.commitComposition();
    _systemForFocus = FocusManager.instance.primaryFocus;
    _focusChanged();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    widget.store.removeListener(_focusChanged);
    _control.removeListener(_redraw);
    if (_installed) TextInput.restorePlatformInputControl();
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final visible = _installed && _control.visible;
    final height = visible
        ? math.min(media.size.height * 0.49, 312 + media.viewPadding.bottom)
        : 0.0;
    return KeyboardStoreScope(
      store: widget.store,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaQuery(
            data: media.copyWith(
              viewInsets: media.viewInsets.copyWith(
                bottom: visible ? height : media.viewInsets.bottom,
              ),
              padding: visible
                  ? media.padding.copyWith(bottom: 0)
                  : media.padding,
            ),
            child: widget.child,
          ),
          if (visible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height,
              child: FocusScope(
                canRequestFocus: false,
                child: TextFieldTapRegion(
                  child: CharacterKeyboard(
                    skin: widget.store.activeSkin,
                    artworkAsset: _artwork,
                    editing: _control.editing,
                    actionLabel: _control.actionLabel,
                    onAction: _control.action,
                    onHide: () => FocusManager.instance.primaryFocus?.unfocus(),
                    onSystem: _useSystem,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CharacterInputControl extends ChangeNotifier with TextInputControl {
  _CharacterInputControl() {
    editing = KeyboardEditing(
      onEdit: (value) {
        if (client != null) TextInput.updateEditingValue(value);
      },
    );
    editing.lexicon = PinyinLexicon.cached;
    unawaited(
      PinyinLexicon.load()
          .then((lexicon) {
            if (_disposed) return;
            editing.lexicon = lexicon;
            editing.sync(editing.value);
            notifyListeners();
          })
          .catchError((Object _) {}),
    );
  }
  late final KeyboardEditing editing;
  TextInputClient? client;
  TextInputConfiguration configuration = const TextInputConfiguration();
  bool visible = false;
  bool _disposed = false;
  String get actionLabel => switch (configuration.inputAction) {
    TextInputAction.newline => 'Return',
    TextInputAction.next => 'Next',
    TextInputAction.search => 'Search',
    TextInputAction.send => 'Send',
    _ => 'Done',
  };
  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    if (!identical(this.client, client)) {
      editing.pinyin = '';
      if (configuration.inputType == TextInputType.number ||
          configuration.inputType == TextInputType.phone) {
        editing.chinese = false;
        editing.symbols = true;
      }
    }
    this.client = client;
    this.configuration = configuration;
    editing.sync(client.currentTextEditingValue ?? TextEditingValue.empty);
  }

  @override
  void detach(TextInputClient client) {
    if (!identical(this.client, client)) return;
    this.client = null;
    editing.pinyin = '';
    hide();
  }

  @override
  void updateConfig(TextInputConfiguration configuration) =>
      this.configuration = configuration;
  @override
  void show() {
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    if (!visible) {
      visible = true;
      notifyListeners();
    }
  }

  @override
  void hide() {
    if (visible) {
      visible = false;
      notifyListeners();
    }
  }

  @override
  void setEditingState(TextEditingValue value) => editing.sync(value);
  void action() => client?.performAction(configuration.inputAction);
  @override
  void dispose() {
    _disposed = true;
    editing.dispose();
    super.dispose();
  }
}
