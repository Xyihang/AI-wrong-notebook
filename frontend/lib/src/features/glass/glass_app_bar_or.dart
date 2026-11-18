import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';

/// 顶栏门面：玻璃开启时用 [GlassAppBar]，关闭时回退 Material [AppBar]。
///
/// 用于各页 `Scaffold.appBar`，保证「关闭玻璃」后视觉与旧版本一致。
class GlassAppBarOr extends ConsumerWidget implements PreferredSizeWidget {
  const GlassAppBarOr({
    required this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    super.key,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(glassEnabledProvider);
    if (!enabled) {
      return AppBar(
        title: title,
        actions: actions,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
      );
    }
    return GlassAppBar(
      title: title,
      actions: actions,
      leading: leading,
    );
  }
}
