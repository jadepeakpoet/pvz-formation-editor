import '../widgets/app_dropdown.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'app_language.dart';

/// Rebuilds translated labels while retaining the current navigation and editor.
class LanguageScope extends StatefulWidget {
  final Widget Function() builder;
  const LanguageScope({super.key, required this.builder});
  @override
  State<LanguageScope> createState() => _LanguageScopeState();
}

class _LanguageScopeState extends State<LanguageScope> {
  Timer? timer;
  bool listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Dialogs can also use this scope in an otherwise unlocalized host. A
    // nested scope shares its ancestor's refresh rather than walking it twice.
    final shouldListen =
        context.findAncestorStateOfType<_LanguageScopeState>() == null;
    if (shouldListen == listening) return;
    listening = shouldListen;
    if (listening) {
      AppLanguage.locale.addListener(refresh);
      timer =
          Timer.periodic(const Duration(seconds: 2), (_) => AppLanguage.load());
    } else {
      AppLanguage.locale.removeListener(refresh);
      timer?.cancel();
      timer = null;
    }
  }

  void refresh() {
    void visit(Element element) {
      // Text is derived in component builds. Render objects and their static
      // image assets need not rebuild just because the UI language changed.
      if (element is ComponentElement) element.markNeedsBuild();
      element.visitChildren(visit);
    }

    if (!mounted) return;
    setState(() {});
    (context as Element).visitChildren(visit);
  }

  @override
  void dispose() {
    if (listening) AppLanguage.locale.removeListener(refresh);
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder();
}

class LanguageSelector extends StatefulWidget {
  const LanguageSelector({super.key});
  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector> {
  bool saving = false;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
      valueListenable: AppLanguage.locale,
      builder: (_, language, __) => Row(children: [
            Text(language == 'zh' ? '语言 / Language' : 'Language'),
            const SizedBox(width: 16),
            Expanded(
                child: AppDropdown<String>(
                    key: const ValueKey('app-language'),
                    value: language,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: saving
                        ? null
                        : (value) async {
                            if (value == null) return;
                            setState(() => saving = true);
                            try {
                              await AppLanguage.setLanguage(value);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            AppLanguage.text('语言设置保存失败'))));
                              }
                            } finally {
                              if (mounted) setState(() => saving = false);
                            }
                          })),
          ]));
}
