# 网站模板源码目录

这里存放供拾笺下载的网站模板，不是一个已经创建好的用户博客。每个直接子目录对应一个模板，目录名必须与该模板 `template.json.id` 一致。

```text
template/
├── README.md
├── DEVELOPMENT.md            # 唯一的公开模板接入规范
└── butterfly/
    ├── template.json
    ├── package.json
    ├── package-lock.json
    ├── index.html
    ├── vite.config.ts
    ├── scripts/
    └── src/
```

模板只包含网站源码、配置和自身装饰素材。不放 `resource/`、用户文章、关于正文、`node_modules/` 或构建产物。初始化时，应用在用户目录创建空公共资源，再把网站代码安装到 `template/<id>/`。所有模板读取同一份公共内容。

应用从 `zhoujiakang/blog_studio` 的 `main` 读取 `assets/generated/template-manifest.json` 和对应模板文件，验证长度与 SHA-256；不需要模板分支，不把模板源码打进桌面安装包。修改模板源码后，维护者应在恢复 Flutter 依赖后运行：

```sh
dart run tool/generate_template_manifest.dart
```

将模板和清单一起提交。清单生成不等于网站验证，仍需在独立测试博客中运行和构建。已安装模板不会自动更新；应用升级也不覆盖其配置或源码。

- [模板开发指南](DEVELOPMENT.md)：结构、内容协议、配置、启动、构建、验证和 AI 实现要求。
- [Butterfly 说明](butterfly/README.md)：现有模板的入口与配置。
- [应用 README](../README.md)：桌面应用架构与开发命令。
