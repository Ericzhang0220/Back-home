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
        _swapControl(TextInput.restorePlatformInputControl, field);
      }
      if (node != _systemForFocus) _systemForFocus = null;
      return;
    }
    _artwork = target?.artworkAsset;
    if (!_installed) {
      _installed = true;
      _swapControl(() => TextInput.setInputControl(_control), field);
    }
    _control.attach(field, field.textInputConfiguration);
    _control.setEditingState(field.widget.controller.value);
    _control.show();
    _redraw();
  }

  /// Swaps the input control under a focused field without closing the field's
  /// input connection.
  ///
  /// By the time focus listeners run, the field has already attached. Swapping
  /// controls then makes the framework hide the outgoing one, and on iOS hiding
  /// the platform keyboard resigns the native text view, which reports the
  /// connection closed and unfocuses the field: the keyboard blinks open and
  /// shut. Parking the connection on a placeholder first leaves the swap no
  /// field to hide; the field then reattaches under the new control, which
  /// reconfigures the native side with or without a system keyboard. The
  /// native view being replaced still reports closing, but with a stale client
  /// id that the framework ignores.
  void _swapControl(VoidCallback swap, EditableTextState? field) {
    // Read-only fields never attach, so there is no connection to protect.
    if (field == null || field.widget.readOnly) {
      swap();
      return;
    }
    final parked = TextInput.attach(
      _ParkedClient(field.widget.controller.value),
      field.textInputConfiguration,
    );
    swap();
    field.requestKeyboard();
    if (parked.attached) parked.close();
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
  // Never hide the platform keyboard from here: on iOS that closes the field's
  // input connection. The native side is configured without a system keyboard
  // whenever this control is installed (see `_swapControl`).
  @override
  void show() {
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

/// Holds the input connection for the instant the input control is swapped.
class _ParkedClient with TextInputClient {
  _ParkedClient(this.value);

  final TextEditingValue value;

  @override
  TextEditingValue? get currentTextEditingValue => value;
  @override
  AutofillScope? get currentAutofillScope => null;
  @override
  void updateEditingValue(TextEditingValue value) {}
  @override
  void performAction(TextInputAction action) {}
  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
  @override
  void connectionClosed() {}
}
