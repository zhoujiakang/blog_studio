# 拾笺 · Butterfly

这是拾笺的 Vue 网站模板。它提供文章列表、正文、目录、归档、标签、分类、搜索、关于页、明暗切换和响应式布局。布局参考 Butterfly 的阅读体验，代码由 Vue 网站项目实现，不运行 Hexo。

## 文件职责

| 文件或目录 | 用途 |
| --- | --- |
| `template.json` | 模板标识、最低应用版本、主题配置表单及初始通用信息 |
| `package.json`、`package-lock.json` | Node 要求、dev/build 命令与依赖版本 |
| `index.html` | 网页入口 |
| `vite.config.ts` | 定位博客、提供公开内容虚拟模块、监听资源、映射图片和构建 |
| `scripts/content.mjs` | 读取博客通用信息、文章、关于页和主题配置 |
| `scripts/public-images.mjs` | 收集公开内容引用的共享图片 |
| `src/App.vue` | 网站布局、页面导航、文章展示和搜索 |
| `src/lib/markdown.ts` | Markdown 渲染、HTML 清理、目录和图片路径处理 |
| `src/lib/types.ts`、`src/env.d.ts` | 网站内容类型与虚拟模块声明 |
| `src/assets/cover.svg` | 模板自带的装饰背景，由 Vue 导入 |
| `tests/`、`vitest.config.ts` | 仓库中的网站测试；不安装到用户博客 |

## 内容与配置

模板读取用户博客根目录的 `blog.json` 和 `resource/`，不会在自己的源码目录保存文章。新博客没有示例文章；仓库测试内容位于 `test/fixtures/butterfly/`，仅供测试。

通用信息读取 `blog.json.site`：博客名称、副标题、作者、简介和头像。仓库 `template.json.site` 仅用于初始化，安装后会移除，不能用它读取运行时站点信息。

当前主题配置是：

| 字段 | 类型 | 网站行为 |
| --- | --- | --- |
| `backgroundImage` | image | 选择共享图片；为空时使用源码内的默认 SVG 背景 |
| `themeColor` | color | 主题强调色，默认 `#87968B` |
| `announcement` | text | 侧栏公告，支持多行输入 |

摘要只取文章的 `description`；没有内容就隐藏。草稿目录和小记目录不参与公开内容读取，正式文章中的 `draft: true` 或 `published: false` 也会排除。关于页读取 `resource/about.md`，不加入文章列表。

## 运行与扩展

不要直接把本目录当作完整博客启动。先在独立用户博客中安装本模板，并设置 `blog.json.activeTemplate = "butterfly"`。然后进入该博客的 `template/butterfly/`：

```sh
npm ci --ignore-scripts --include=dev
npm run dev -- --host 127.0.0.1 --port 5173 --strictPort
```

当前 Node 要求为 `>=22.18.0`。网站使用 hash 路由和相对构建基础路径，以支持 GitHub Pages 仓库子路径。Vite 关闭 public 自动复制，模板装饰素材通过源码导入；用户图片由公开引用白名单提供。

扩展或创建其他模板请按 [开发指南](../DEVELOPMENT.md) 实现并验证。回归测试从本仓库根目录运行：

```sh
(cd template/butterfly && npm ci --ignore-scripts && npm test)
```
