import 'package:blog_studio/ui/components/brand_logo.dart';
import 'package:blog_studio/app/brand.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:blog_studio/controllers/studio_controller.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/services/preview_manager.dart';

class StudioSidebar extends StatelessWidget {
  const StudioSidebar({super.key, required this.controller});
  final StudioController controller;
  EditorSession get session => controller.session;
  PreviewManager get preview => controller.preview;
  String get filter => controller.filter;
  bool get preparingPreview => controller.preparingPreview;
  Widget _nav(String value, IconData icon, String label, int count) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: ListTile(
      dense: true,
      selected: filter == value,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selectedTileColor: const Color(0xffe6e6e6),
      leading: Icon(icon, size: 20),
      title: Text(
        label,
        style: const TextStyle(
          fontFamily: 'CupertinoSystemText',
          fontFamilyFallback: ['PingFang SC'],
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
      trailing:
          [
            'trash',
            'about',
            'configuration',
            'general',
            'publish',
          ].contains(value)
          ? null
          : Text('$count', style: const TextStyle(color: Color(0xff888888))),
      onTap: () => controller.selectSection(value),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final blocked =
        session.busy ||
        session.importing ||
        preparingPreview ||
        (controller.publisher?.busy ?? false);
    return SizedBox(
      width: 206,
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 16, 0, 28),
                      child: Row(
                        children: [
                          BrandLogo(size: 32),
                          SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppBrand.name,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                AppBrand.englishName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xff888888),
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (session.project != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                        child: Text(
                          p.basename(session.project!.root),
                          maxLines: 2,
                          style: const TextStyle(color: Color(0xff777777)),
                        ),
                      ),
                      _nav(
                        'all',
                        Icons.article_outlined,
                        '全部文章',
                        session.index.articles.length,
                      ),
                      _nav(
                        'drafts',
                        Icons.edit_note,
                        '草稿',
                        session.index.articles.where((a) => a.draft).length,
                      ),
                      _nav(
                        'notes',
                        Icons.notes_outlined,
                        '小记',
                        session.notes.articles.length,
                      ),
                      _nav('trash', Icons.delete_outline, '回收区', 0),
                      const SizedBox(height: 12),
                      _nav('about', Icons.person_outline, '关于', 0),
                      _nav('general', Icons.settings_outlined, '通用配置', 0),
                      _nav('configuration', Icons.palette_outlined, '主题配置', 0),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: controller.creationBlocked
                                  ? null
                                  : controller.newArticle,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text(
                                '新建文章',
                                style: TextStyle(
                                  fontFamily: 'CupertinoSystemText',
                                  fontFamilyFallback: ['PingFang SC'],
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: controller.creationBlocked
                                  ? null
                                  : controller.newNote,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xffd9d9d9),
                                ),
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text(
                                '新建小记',
                                style: TextStyle(
                                  fontFamily: 'CupertinoSystemText',
                                  fontFamilyFallback: ['PingFang SC'],
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (session.project != null)
              TextButton.icon(
                onPressed: blocked ? null : controller.openPreview,
                icon: const Icon(Icons.open_in_browser, size: 19),
                label: Text(preparingPreview ? '正在准备预览…' : '浏览本地博客'),
              ),
            if (session.project != null)
              TextButton.icon(
                onPressed: blocked
                    ? null
                    : () => controller.selectSection('publish'),
                icon: const Icon(Icons.publish_outlined, size: 19),
                label: const Text('发布博客'),
              ),
            if (preview.url != null)
              TextButton.icon(
                onPressed: preview.stop,
                icon: const Icon(Icons.stop_circle_outlined, size: 19),
                label: const Text('停止预览'),
              ),
            TextButton.icon(
              onPressed: blocked ? null : controller.pickProject,
              icon: const Icon(Icons.folder_open, size: 19),
              label: Text(session.project == null ? '打开博客目录' : '切换博客'),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                AppBrand.tagline,
                style: TextStyle(fontSize: 12, color: Color(0xff999999)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
