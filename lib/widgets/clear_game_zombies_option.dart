import 'package:flutter/material.dart';
import '../platform/app_language.dart';

class ClearGameZombiesOption extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const ClearGameZombiesOption({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) => Tooltip(
      message: AppLanguage.text('应用阵型前清除游戏中已有的僵尸。'),
      child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 32, height: 36,
                child: Checkbox(value: value,
                    onChanged: onChanged == null ? null : (next) => onChanged!(next!))),
            Flexible(child: Text(AppLanguage.text('清除场上僵尸'), style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 6),
          ])));
}
