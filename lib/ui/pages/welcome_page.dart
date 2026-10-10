import 'package:blog_studio/ui/components/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:blog_studio/controllers/studio_controller.dart';
import 'package:blog_studio/services/editor_session.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.controller});
  final StudioController controller;
  EditorSession get session => controller.session;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandLogo(size: 88),
        const SizedBox(height: 24),
        const Text(
          '从一个文件夹开始',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          '打开已有博客，或选择空目录创建新博客。',
          style: TextStyle(color: Color(0xff777777)),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: session.busy || controller.choosingProject
              ? null
              : controller.pickProject,
          icon: const Icon(Icons.folder_open, size: 20),
          label: const Text('选择目录'),
        ),
        if (controller.choosingProject && !session.busy)
          const Padding(padding: EdgeInsets.all(18), child: Text('正在获取模板列表…')),
        if (session.busy)
          const Padding(padding: EdgeInsets.all(18), child: Text('正在下载并准备博客…')),
        if (session.error != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              session.error!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
      ],
    ),
  );
}
