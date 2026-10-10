import 'package:flutter/material.dart';
import 'package:blog_studio/controllers/studio_controller.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/models/trash_entry.dart';
import 'package:blog_studio/storage/trash_repository.dart';

class TrashPage extends StatelessWidget {
  const TrashPage({super.key, required this.controller});
  final StudioController controller;
  EditorSession get session => controller.session;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '回收区',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          '恢复文章或小记不会覆盖已有文件，图片始终保留。',
          style: TextStyle(color: Color(0xff888888)),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: FutureBuilder<TrashListing>(
            future: TrashRepository(session.repository!.store).scan(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final listing = snapshot.data!;
              final entries = listing.entries;
              final content = entries.isEmpty
                  ? const Center(
                      child: Text(
                        '回收区是空的',
                        style: TextStyle(color: Color(0xff888888)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(entries[i].title),
                        subtitle: Text(entries[i].originalPath),
                        trailing: TextButton(
                          onPressed: () =>
                              controller.run(session.restore(entries[i].id)),
                          child: const Text('恢复'),
                        ),
                      ),
                    );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (listing.errors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '有 ${listing.errors.length} 条回收记录无法读取，其余内容可正常恢复。原文件已保留。',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff888888),
                        ),
                      ),
                    ),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
