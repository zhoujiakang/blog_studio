# 纸页 paper

拾笺 InkJian 的简约风博客模板。整个页面只有墨色与纸张底色两种颜色，靠留白、字重和细线分区：**顶部导航 + 卡片网格首页，正文是窄栏单栏**。

### 视觉约定

- 纸张底色 `--paper`、强调色 `--accent` 由主题字段驱动，其余 neutrals 由这两者推导。
- 标题使用宋体系衬线（`Songti SC` / `Source Han Serif SC`），正文使用系统无衬线字体。
- 首页容器 880px，卡片网格 `auto-fill / minmax(320px, 1fr)`（桌面两栏，窄屏单栏）；正文容器 680px。
- 无阴影、无圆角、无渐变。分区只使用 1px 细线与「宋体 + 字距」的排版差异。

### 主题字段

| key | 类型 | 默认值 | 用途 |
| --- | --- | --- | --- |
| `backgroundTint` | color | `#FAF9F7` | 整页纸张底色 |
| `accentColor` | color | `#1A1A1A` | 链接、悬停、引用竖线、卡片侧标 |
| `backgroundImage` | image | 空 | 平铺纹理；留空时使用 `src/assets/paper-grain.svg` |
| `announcement` | text（多行） | 空 | 首页顶部公告，留空则不渲染该区块 |
| `footerText` | text（多行） | 空 | 页脚右侧文字，留空只显示站点署名 |

五个字段都会被页面实际使用，取值顺序为 `value ?? default`。

### 目录结构

```text
template/paper/
├── template.json          # 身份 + 五个主题字段
├── package.json           # dev/build 命令，node >= 22.18.0
├── package-lock.json      # 可复现安装
├── index.html             # 网页入口
├── vite.config.ts         # 虚拟内容、图片白名单、监听与安全策略
├── scripts/
│   ├── content.mjs        # 定位博客、解析 Front Matter、公开/私有判定
│   ├── public-images.mjs  # /img 白名单与边界校验
│   └── *.d.mts            # 供 vite.config.ts 使用的类型声明
└── src/
    ├── App.vue            # hash 路由与页面装配
    ├── lib/               # 路由、主题、Markdown 渲染、内容统计
    ├── views/             # 首页 / 归档 / 标签 / 分类 / 关于 / 文章 / 404
    ├── components/        # 页头、页脚、卡片、安全图片
    ├── assets/paper-grain.svg
    └── style.css
```

### 命令

```sh
npm ci --ignore-scripts --include=dev
npm run dev -- --host 127.0.0.1 --port <动态端口> --strictPort
npm run build -- --outDir <绝对输出目录>
```

### 实现要点

- **内容读取**：`scripts/content.mjs` 从模板目录向上寻找 `blog.json`，只读取 `resource/posts/**/*.md`、`resource/about.md`、`blog.json.site` 和 `template/<activeTemplate>/template.json`，跳过 `drafts/`、`notes/`、隐藏项与符号链接。
- **摘要**：只取 Front Matter 的 `description`，缺省、空或纯空白一律隐藏，不以任何方式自动生成。
- **日期**：不带时区的本地日期按 `+08:00` 解释；缺少日期使用 Unix epoch，不使用当前时间。
- **地址**：`slug` 优先，缺省用相对 posts 的路径（含子目录）；重复 ID 直接报错，不静默覆盖。
- **图片**：只把公开内容实际引用的图片放进白名单；dev 时由中间件提供 `/img/<name>`，build 时输出 `img/<name>`。内容为兼容 GitHub Pages 子路径，会把 `/img/x` 改写成相对形式 `img/x`。
- **安全**：dev 前置守卫拒绝 `resource/`、配置文件、`.env*` 与含 `..` 的请求；`server.fs.allow` 只开放模板目录。正文经 marked 解析后由 DOMPurify 清理，清理结果才交给 `v-html`。
- **发布**：`base: './'` + hash 路由，`#/post/<id>` 深链接刷新后仍可打开；产物只有 `index.html`、`assets/`、`img/`，不含 Markdown、配置与 source map。

### 已验证与未验证

已在独立临时博客（Docker 无关的 macOS /tmp 夹具）中实际执行通过：

- 空博客可预览、可构建，缺头像/缺背景时无破损占位。
- 文章排序、子目录 ID、中文标题、标签统计、层级分类统计正确。
- `drafts/`、`notes/`、`draft: true`、`published: false` 均不公开，私有图片 dev 返回 404 且不进入产物。
- 通用信息与五个主题字段修改后即时刷新。
- 常见 Markdown（表格、代码块、引用、列表、图片、外链）渲染正确，正文中的 `<script>` 被清理。
- build 写入指定 `--outDir`，产物清单干净。

未验证：真实 GitHub Pages 仓库发布、桌面对外清单生成（需维护者运行 `dart run tool/generate_template_manifest.dart`）。
