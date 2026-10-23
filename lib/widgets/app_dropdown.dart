import 'package:flutter/material.dart';

/// A compact field around Flutter's native dropdown interaction and menu.
/// The supplied key stays on the DropdownButton so existing focus and lookup
/// targets retain their identity when this presentation is applied.
class AppDropdown<T> extends StatelessWidget {
  final Key? dropdownKey;
  final T? value;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final VoidCallback? onTap;
  final bool isDense, isExpanded;
  final TextStyle? style;
  final Widget? hint, disabledHint, underline, icon;
  final DropdownButtonBuilder? selectedItemBuilder;
  final FocusNode? focusNode;
  final bool autofocus;
  final double? itemHeight, menuMaxHeight;
  final double iconSize;
  final AlignmentGeometry alignment;
  final Color? dropdownColor;
  final BorderRadius? borderRadius;

  // The key belongs to the inner field, not its decorative shell.
  // ignore: use_key_in_widget_constructors
  const AppDropdown({
    Key? key,
    required this.items,
    required this.onChanged,
    this.value,
    this.onTap,
    this.isDense = true,
    this.isExpanded = false,
    this.style,
    this.hint,
    this.disabledHint,
    this.underline,
    this.icon,
    this.selectedItemBuilder,
    this.focusNode,
    this.autofocus = false,
    this.itemHeight = kMinInteractiveDimension,
    this.menuMaxHeight = 320,
    this.iconSize = 18,
    this.alignment = AlignmentDirectional.centerStart,
    this.dropdownColor,
    this.borderRadius,
  }) : dropdownKey = key;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null && items != null && items!.isNotEmpty;
    final textStyle =
        style ?? Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled ? const Color(0xfffafcf7) : const Color(0xffedf0e9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: enabled ? const Color(0xffbccbb7) : const Color(0xffd5ddd0)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              key: dropdownKey,
              value: value,
              items: items,
              onChanged: onChanged,
              onTap: onTap,
              isDense: isDense,
              isExpanded: isExpanded,
              style: textStyle,
              hint: hint,
              disabledHint: disabledHint,
              selectedItemBuilder: selectedItemBuilder ??
                  (items == null
                      ? null
                      : (_) => items!
                          .map((item) => DefaultTextStyle.merge(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              child: item.child))
                          .toList()),
              focusNode: focusNode,
              autofocus: autofocus,
              itemHeight: itemHeight,
              menuMaxHeight: menuMaxHeight,
              icon: icon ?? const Icon(Icons.expand_more_rounded),
              iconSize: iconSize,
              iconEnabledColor: const Color(0xff526e49),
              iconDisabledColor: const Color(0xffa5afa0),
              dropdownColor: dropdownColor ?? const Color(0xfffcfdf9),
              borderRadius: borderRadius ?? BorderRadius.circular(8),
              elevation: 6,
              alignment: alignment,
              underline: underline,
            ),
          ),
        ),
      ),
    );
  }
}
