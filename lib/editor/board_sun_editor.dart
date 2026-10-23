import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../platform/app_language.dart';

/// The interactive board sunlight counter; exports keep the painter version.
class BoardSunEditor extends StatefulWidget {
  final int value;
  final bool readOnly;
  final ValueChanged<int> onChanged;

  const BoardSunEditor({
    super.key,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  State<BoardSunEditor> createState() => _BoardSunEditorState();
}

class _BoardSunEditorState extends State<BoardSunEditor> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant BoardSunEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_editing && (widget.readOnly || oldWidget.value != widget.value)) {
      // An external update (including undo) supersedes the in-progress edit.
      _editing = false;
      _invalid = false;
      _focus.unfocus();
    }
  }

  void _focusChanged() {
    if (!_focus.hasFocus && _editing) _finish();
  }

  void _begin() {
    if (widget.readOnly || _editing) return;
    _controller.value = TextEditingValue(
      text: '${widget.value}',
      selection:
          TextSelection(baseOffset: 0, extentOffset: '${widget.value}'.length),
    );
    setState(() {
      _editing = true;
      _invalid = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focus.requestFocus();
    });
  }

  void _finish({bool cancel = false}) {
    if (!_editing || !mounted) return;
    final value = int.tryParse(_controller.text);
    if (!cancel &&
        !widget.readOnly &&
        (value == null || value < 0 || value > 99999999)) {
      setState(() => _invalid = true);
      return;
    }
    setState(() {
      _editing = false;
      _invalid = false;
    });
    _focus.unfocus();
    if (!cancel && !widget.readOnly && value != widget.value) {
      widget.onChanged(value!);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return Semantics(
        button: true,
        enabled: !widget.readOnly,
        label: AppLanguage.text('编辑阳光'),
        value: '${widget.value}',
        child: MouseRegion(
          cursor: widget.readOnly
              ? SystemMouseCursors.basic
              : SystemMouseCursors.text,
          child: GestureDetector(
            key: const ValueKey('board-sun-edit'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.readOnly ? null : _begin,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                  left: 12,
                  top: 3,
                  child: ExcludeSemantics(
                      child: Text('${widget.value}',
                          style: const TextStyle(
                              fontFamily: 'Continuum Bold',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black)))),
            ]),
          ),
        ),
      );
    }
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: BorderSide(
        color: _invalid ? Colors.red.shade700 : const Color(0xff8f682e),
      ),
    );
    return Tooltip(
      message:
          AppLanguage.text(_invalid ? '请输入 0–99999999 的整数' : '回车保存，Esc 取消'),
      child: Semantics(
        liveRegion: _invalid,
        label: _invalid ? AppLanguage.text('请输入 0–99999999 的整数') : null,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _finish(cancel: true);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: const ValueKey('board-sun-input'),
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              isDense: true,
              isCollapsed: true,
              filled: true,
              fillColor:
                  _invalid ? const Color(0xffffe2d7) : const Color(0xfffff2c5),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
              border: border,
              enabledBorder: border,
              focusedBorder: border,
            ),
            onChanged: (_) {
              if (_invalid) setState(() => _invalid = false);
            },
            onSubmitted: (_) => _finish(),
            onTapOutside: (_) => _finish(),
          ),
        ),
      ),
    );
  }
}
