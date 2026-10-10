import 'package:blog_studio/ui/components/operation_progress.dart';
import 'package:flutter/material.dart';
import 'package:blog_studio/controllers/publish_controller.dart';

class PublishingPage extends StatelessWidget {
  const PublishingPage({super.key, required this.controller});
  final PublishController controller;
  Future<void> _publish(BuildContext context) async {
    if (controller.state?.pending != true) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('发布到公开网站'),
          content: const Text(
            '正式文章、关于页及其使用的图片将公开。草稿和小记保留在本地。\n\n应用会自动准备所需组件、构建当前主题并上传网页。需要时会下载运行组件和博客依赖。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('发布博客'),
            ),
          ],
        ),
      );
      if (approved != true) return;
    }
    await controller.publish();
  }

  Widget _section(String title, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    margin: const EdgeInsets.only(bottom: 18),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xffe9e9e9)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final target = c.target;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '发布博客',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                '将当前主题的博客发布到 GitHub Pages。',
                style: TextStyle(color: Color(0xff888888)),
              ),
              const SizedBox(height: 28),
              if (!c.configured)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xfff5f5f5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '当前构建尚未配置 GitHub 登录。开发者完成 GitHub App 注册并按 README 配置后，即可启用发布。',
                  ),
                ),
              _section(
                'GitHub 账号',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_circle_outlined, size: 22),
                        const SizedBox(width: 10),
                        Expanded(child: Text(c.account?.login ?? '尚未连接')),
                        if (c.account == null)
                          FilledButton(
                            onPressed: c.busy || !c.configured
                                ? null
                                : c.connect,
                            child: const Text('连接 GitHub'),
                          )
                        else
                          TextButton(
                            onPressed: c.busy ? null : c.disconnect,
                            child: const Text('断开连接'),
                          ),
                      ],
                    ),
                    if (c.authorization != null) ...[
                      const SizedBox(height: 16),
                      const Text('在浏览器中输入以下授权码，完成后应用会自动继续：'),
                      const SizedBox(height: 8),
                      SelectableText(
                        c.authorization!.userCode,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            c.browser.open(c.authorization!.verificationUri),
                        child: const Text('重新打开授权页面'),
                      ),
                    ],
                  ],
                ),
              ),
              _section(
                '发布位置',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.account != null) ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          '${target?.fullName}:${c.repositories.length}:${c.busy}',
                        ),
                        initialValue:
                            c.repositories.any(
                              (r) => r.target.fullName == target?.fullName,
                            )
                            ? target!.fullName
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '发布仓库',
                          hintText: '选择一个公开仓库',
                        ),
                        items: c.repositories
                            .map(
                              (r) => DropdownMenuItem(
                                value: r.target.fullName,
                                child: Text(r.target.fullName),
                              ),
                            )
                            .toList(),
                        onChanged: c.busy
                            ? null
                            : (name) {
                                if (name != null) {
                                  c.selectRepository(
                                    c.repositories
                                        .firstWhere(
                                          (r) => r.target.fullName == name,
                                        )
                                        .target,
                                  );
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: c.busy ? null : c.createRepository,
                            icon: const Icon(Icons.add, size: 17),
                            label: const Text('新建仓库'),
                          ),
                          TextButton.icon(
                            onPressed: c.busy ? null : c.openInstallation,
                            icon: const Icon(
                              Icons.lock_open_outlined,
                              size: 17,
                            ),
                            label: const Text('授权发布仓库'),
                          ),
                          TextButton.icon(
                            onPressed: c.busy ? null : c.refreshRepositories,
                            icon: const Icon(Icons.refresh, size: 17),
                            label: const Text('刷新仓库'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '新建公开仓库后，在授权页面只选择这个仓库，再回来刷新。请选择空仓库或仅含 README 的新仓库。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xff888888),
                        ),
                      ),
                    ] else
                      const Text(
                        '连接账号后选择网站的发布位置。',
                        style: TextStyle(color: Color(0xff888888)),
                      ),
                    if (target != null) ...[
                      const SizedBox(height: 16),
                      Text('已关联：${target.fullName}'),
                      const SizedBox(height: 6),
                      SelectableText(
                        (c.state?.url ?? target.website).toString(),
                        style: const TextStyle(color: Color(0xff777777)),
                      ),
                    ],
                  ],
                ),
              ),
              _section(
                '发布状态',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.publishing ||
                        c.error.isNotEmpty ||
                        c.startedAt != null) ...[
                      OperationProgress(
                        stages: const ['仓库检查', '网页构建', '上传', '上线确认'],
                        current: c.step,
                        running: c.publishing && !c.cancelling,
                        startedAt: c.startedAt,
                      ),
                      const SizedBox(height: 14),
                    ] else if (c.busy) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      c.message.isNotEmpty
                          ? c.message
                          : c.state?.pending == true
                          ? '网页已上传，等待确认上线。'
                          : c.state?.publishedAt == null
                          ? '尚未发布。'
                          : '上次上线：${_time(c.state!.publishedAt!)}',
                    ),
                    if (c.error.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        c.error,
                        style: const TextStyle(color: Color(0xff9b4c42)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed:
                              c.busy || target == null || c.account == null
                              ? null
                              : () => _publish(context),
                          icon: const Icon(Icons.publish_outlined, size: 18),
                          label: Text(
                            c.state?.pending == true
                                ? '继续确认上线'
                                : c.error.isNotEmpty
                                ? '重试发布'
                                : c.state?.publishedAt == null
                                ? '发布博客'
                                : '发布更新',
                          ),
                        ),
                        if (c.state?.url != null)
                          OutlinedButton(
                            onPressed: c.openWebsite,
                            child: const Text('打开网站'),
                          ),
                        if (c.publishing || c.authorization != null)
                          TextButton(
                            onPressed: c.cancelling ? null : c.cancel,
                            child: Text(
                              c.cancelling
                                  ? '正在取消…'
                                  : c.state?.pending == true
                                  ? '暂停确认'
                                  : '取消',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _time(DateTime value) {
    final d = value.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
