# 拾笺网站模板开发指南

本指南面向模板作者与负责实现模板的 AI，描述当前源码的接入约定。实现目标是：不修改桌面应用，即可识别新模板、编辑其配置、启动本地预览，并通过应用构建和发布到 GitHub Pages。

[应用说明](../README.md) · [模板目录](README.md) · [Butterfly 参考实现](butterfly/README.md)

## 1. 先确定边界

桌面应用负责管理内容、配置、依赖和进程。模板负责读取公开内容、渲染页面和输出静态网站。应用不会提供文章 HTTP API，也不会把资源目录复制进模板源码。

当前接入检查要求 `src/App.vue`，参考工具链是 Vue + Vite + npm。虽然辅助进程通过 dev/build 命令启动网站，但不能据此假设任意其他框架已经得到支持。

模板作者必须遵守：

1. 用户文章、图片和关于正文只存在于博客根目录 `resource/`。
2. 通用信息只从 `blog.json.site` 读取，活动模板只从 `blog.json.activeTemplate` 读取。
3. 主题字段从活动模板的 `template.json` 读取，不硬编码用户选中的配置值。
4. 不读草稿、小记、备份或凭证作为公开内容，不把完整配置文件复制进网站输出。
5. 空博客也能正常启动和构建。不得要求内置一篇示例文章。
6. dev/build 必须接受应用传入的参数。发布结果是静态文件，不依赖线上 Node 服务。

## 2. 两种目录

### 2.1 模板源码

以下以 ID `paper` 为例。它位于本仓库的 `template/paper/`，不是一个用户博客。

```text
template/paper/
├── template.json             # 模板身份与配置定义
├── package.json              # Node 约束与 dev/build 命令
├── package-lock.json         # 可复现安装
├── index.html                # 必需的网页入口
├── vite.config.ts            # 网站工具链配置
├── tsconfig.json             # 使用 TypeScript 时需要
├── scripts/
│   ├── content.mjs           # 推荐复用的公开内容读取适配器
│   └── public-images.mjs     # 推荐复用的共享图片白名单
├── src/
│   ├── App.vue               # 当前应用要求的入口
│   ├── main.ts
│   ├── env.d.ts
│   ├── components/
│   ├── lib/
│   │   ├── markdown.ts
│   │   └── types.ts
│   ├── assets/               # 主题自身的装饰素材
│   └── style.css
└── README.md                 # 作者说明，不安装到用户博客
```

`package.json`、`template.json`、`src/App.vue` 是清单生成器检查的必需路径；应用打开博客还检查 `index.html`。其他文件由工具链需要决定，必须提供实际可运行实现，而不是只满足文件名检查。

不要放 `resource/`、`blog.json`、用户 Markdown、关于正文、依赖目录或构建结果。测试可留在 `tests/`，但不安装到用户博客；运行时代码不得依赖这些测试文件。当前安装器也排除根 `README.md`、`.gitignore` 和 `vitest.config.ts`，不要把运行必需文件放在这些位置。

### 2.2 用户博客

```text
my-blog/
├── blog.json
├── resource/
│   ├── posts/
│   ├── drafts/
│   ├── notes/
│   ├── images/
│   └── about.md
└── template/
    ├── paper/                # 安装后的模板源码
    └── butterfly/
```

初始化只创建空内容目录和默认关于页。添加或切换主题不复制用户内容。运行时的 `node_modules/` 可由应用安装在当前主题目录，不能提交或作为模板下载文件。模板自带图片保留在源码内，不写入共享用户资源。

## 3. 如何被应用识别

### 3.1 标识

目录名、`template.json.id`、`blog.json.activeTemplate` 三者必须一致。当前允许字母、数字、中文、下划线和连字符，首字符必须是字母、数字或中文。推荐使用小写英文 ID，例如 `paper`。不能使用点、空格、斜杠或反斜杠。

`template.json.name` 是界面显示名称，不作为文件路径。

### 3.2 本地模板

将完整代码放入已有博客的 `template/paper/`。应用枚举本地模板目录，校验其配置与目录 ID，合法模板可出现在主题选择列表。切换后应用保存 `activeTemplate`，重新读取配置。已有模板不会因远程版本存在而被覆盖。

配置被识别不代表网站能够启动；还必须通过本文的 dev/build 验证。应用目前没有“从任意 GitHub 地址安装模板”的界面，不能把这个能力作为模板交付前提。

### 3.3 官方下载列表

要出现在官方远程下载列表中，需要将 `template/paper/` 加入官方仓库，然后由维护者执行：

```sh
# 从仓库根目录运行；只生成清单时无需构建编辑器
flutter pub get
dart run tool/generate_template_manifest.dart
```

提交模板与 `assets/generated/template-manifest.json` 到 `main`。普通用户安装时从官方 `raw.githubusercontent.com` 源下载清单和选中的文件，不需要 Git 命令或 GitHub 登录。

四种版本不要混淆：

| 位置 | 当前约定 |
| --- | --- |
| `blog.json.formatVersion` | 数字 `2`，博客目录格式 |
| `template.json.formatVersion` | 数字 `1`，主题配置结构 |
| 下载清单 `version` | 字符串 `"2"` |
| 清单每个模板的 `protocolVersion` | 数字 `2` |

模板源码必须声明有效的 `minAppVersion`，生成器将其写入清单。当前官方模板为 `0.0.1`。为新模板选取最低版本时，应依据实际使用的应用能力，不随意降低要求。

清单记录相对于该模板目录的文件路径、字节长度、SHA-256。生成器排除依赖、构建目录和隐藏项，但保留 `.gitignore`；拒绝模板内的 `resource/`。不要手写文件校验值，也不要把清单放进模板自身。

下载端限制单文件 20 MiB、所有可用模板清单记录合计 100 MiB、最多 10000 个文件；大型素材应精简。已安装模板不会自动更新。

## 4. 通用配置：blog.json

新建测试博客可以使用以下内容：

```json
{
  "formatVersion": 2,
  "activeTemplate": "paper",
  "site": {
    "title": "我的博客",
    "subtitle": "记录日常与思考",
    "author": "作者",
    "description": "欢迎来到我的文字空间。",
    "avatar": ""
  }
}
```

`site` 的五个字段都是字符串。`description` 是站点简介，和每篇文章的摘要不是同一份数据。`avatar` 为空时不要显示破损图片；应用选图后通常写入 `/img/...`。

应用还可能写入 `publish`，其中是发布目标和状态。模板不需要解释它，不得把 `blog.json` 整体发送到浏览器或输出目录。

不要用 `template.json.site` 作为运行时配置。它仅是新博客初始化的可选初始值：安装器把它提取到 `blog.json.site`，并从安装后的主题配置移除。给已有博客新增主题时不会覆盖通用信息。

## 5. 主题配置：template.json

可直接作为新模板起点：

```json
{
  "formatVersion": 1,
  "id": "paper",
  "name": "纸页",
  "minAppVersion": "0.0.1",
  "fields": [
    {
      "key": "backgroundImage",
      "label": "背景图片",
      "type": "image",
      "description": "为空时使用模板自己的装饰背景。",
      "default": "",
      "value": ""
    },
    {
      "key": "themeColor",
      "label": "主题颜色",
      "type": "color",
      "default": "#87968B",
      "value": "#87968B"
    },
    {
      "key": "announcement",
      "label": "公告",
      "type": "text",
      "multiline": true,
      "default": "欢迎来到我的博客。",
      "value": "欢迎来到我的博客。"
    }
  ],
  "site": {
    "title": "我的博客",
    "subtitle": "记录日常与思考",
    "author": "作者",
    "description": "欢迎来到我的文字空间。",
    "avatar": ""
  }
}
```

### 字段规则

| 属性 | 要求 |
| --- | --- |
| `key` | 唯一；匹配 `^[a-zA-Z][a-zA-Z0-9_]*$` |
| `label` | 字符串，配置页显示的名称 |
| `type` | 本规范使用 `text`、`image` 或 `color` |
| `default` | 必需字符串，用于初始值和恢复默认 |
| `value` | 可选字符串；存在时优先于 default，即使为空 |
| `description` | 可选说明文字 |
| `multiline` | 文字字段可设置 `true`，使用多行输入 |

- `text`：普通文字输入，不自动当成 Markdown 或 HTML。若作者希望渲染 Markdown，需自己明确实现及清理规则。
- `image`：字符串为空，或匹配 `/img/[\w/.-]+` 且不含 `..` 路径段。不要把主题源码图片路径或远程 URL 写入该类型的默认值。
- `color`：只支持 `#RRGGBB` 六位十六进制字符串。

当前没有枚举、数字、开关、嵌套对象、分组或动态列表控件。不要为这些能力发明新的配置协议。识别器可能保留未知字段类型，但配置页不提供完整编辑能力，内容适配器也会跳过它们。

模板将 `fields` 转为键值对象，取值顺序为 `value ?? default`。页面必须实际使用每个声明的配置，不要提供无效果的控件。恢复默认只恢复该主题字段，不删除用户图片或文章。

## 6. 文章、关于页和内容适配

### 6.1 读取路径

从正在运行的模板目录向上寻找 `blog.json`，确定博客根目录。不要假设启动时的工作目录永远是仓库根目录，也不要依赖某个人电脑上的绝对路径。

然后读取：

| 路径 | 用途 |
| --- | --- |
| `resource/posts/**/*.md` | 正式文章，支持嵌套目录和大小写 Markdown 扩展名 |
| `resource/about.md` | 单独的关于正文 |
| `resource/images/` | 仅提供公开内容实际引用的图片 |
| `blog.json.site` | 通用配置 |
| `template/<activeTemplate>/template.json` | 当前主题配置 |

不扫描 `drafts/`、`notes/` 或 `.blog-studio/`。跳过隐藏文件和符号链接；不要让它们进入文章列表。

### 6.2 Front Matter

```markdown
---
title: "今天的小事"
date: "2026-10-10 20:00:00"
updated: "2026-10-10 21:00:00"
description: "这是一段我主动填写的摘要。"
tags: ["生活", "记录"]
categories: ["生活/日记"]
cover: "/img/example.jpg"
slug: "daily-example"
published: true
---

## 今天的发现

这里是正文。
```

示例图片仅演示路径，测试时需要实际创建对应图片，也可以删除 cover 字段。

| 属性 | 类型与含义 |
| --- | --- |
| `title` | 字符串；缺省时参考适配器使用文件名 |
| `date` | 字符串；无日期时参考适配器使用 Unix epoch，不使用当前时间制造日期 |
| `updated` | 字符串；缺省沿用 date |
| `description` | 显式文章摘要；缺省、空或仅空白时隐藏 |
| `tags` | 字符串数组；缺省或 null 视为空数组 |
| `categories` | 字符串数组；缺省或 null 视为空数组 |
| `cover` | 字符串；通常为 `/img/...`，为空可不显示或使用模板装饰图 |
| `slug` | 可选字符串，必须生成唯一文章地址；建议非空 |
| `published` | 可选布尔值；false 不公开 |
| `draft` | 可选布尔值；true 不公开 |

字符串日期建议在 YAML 中加引号。本地无时区日期由参考适配器按 `+08:00` 解释并转换为 ISO 字符串；带时区字符串按其自身时区解释。非法类型或日期应报错，不用强制转换掩盖错误。

`categories: ["技术/Flutter"]` 是一个层级路径，`categories: ["技术", "Flutter"]` 是两个独立分类。标签与分类统计仅根据公开文章计算；模板不得把草稿或小记纳入统计。

**禁止自动摘要**：不要取标题、正文前 N 字、`excerpt` 或其他别名来补 `description`。正文内的 `<!-- more -->` 也不表示授权生成摘要。正文保留并渲染自己的内容即可。

slug 缺省时，参考适配器使用文章相对于 posts 目录的路径去掉 `.md`；子目录也参与 ID。必须检测重复 ID，不静默覆盖。未知文章字段由应用保存，但不是通用展示协议；参考 Vite 插件会去掉原始 meta，不把整份 Front Matter 发到浏览器。

### 6.3 给 Vue 的公开数据

推荐复用 [content.mjs](butterfly/scripts/content.mjs)，其主要接口为：

- `locateBlog(templateDirectory)`：返回博客根目录、活动模板目录及通用信息。
- `loadContent(templateDirectory)`：返回公开站点、文章、关于正文和主题键值。
- `parsePost(markdown, relativeFilename)`：解析文章；不公开的文章返回 null。

推荐前端形状：

```ts
interface Post {
  id: string;
  title: string;
  body: string;             // Markdown 正文，不含 Front Matter
  date: string;
  updated: string;
  tags: string[];
  categories: string[];
  summary: string;          // 仅来自 description
  cover: string;
}
interface BlogContent {
  site: {
    title: string; subtitle: string; author: string;
    description: string; avatar: string;
  };
  posts: Post[];
  about: string;            // Markdown 正文，不计入 posts
  theme: Record<string, string>;
}
```

参考 Vite 插件在 Node 端读取文件，提供 `virtual:blog-content`：

```ts
import content from 'virtual:blog-content';
const { site, posts, about, theme } = content;
```

文件读取在 dev 或 build 进程执行，不在浏览器中调用 fs。Node 内容适配器不是需要上线的服务器；发布后这些公开数据进入静态网页资源。浏览器端只渲染公开数据。

### 6.4 Markdown 渲染

可复用 [markdown.ts](butterfly/src/lib/markdown.ts) 的 `renderMarkdown(source)`，返回 `{ html, headings }`。它使用 marked 解析、DOMPurify 清理，给标题生成目录 ID，处理站点基础路径下的图片和外链。

自建渲染器也必须清理可执行 HTML。不要将未清理的 Markdown 转换结果直接交给 `v-html`，不要输出脚本、事件属性或 javascript 链接。关于页与文章使用一致的处理。此函数使用浏览器 DOM API，不应直接在 Node 中调用。

## 7. 图片与静态素材

用户图片和模板装饰图片是两类东西：

- 用户图片：根目录 `resource/images/`；内容与配置引用 `/img/...`。
- 模板装饰图片：主题源码 `src/assets/`；通过 Vue/CSS import 让构建工具处理，不复制到用户资源目录。

推荐复用 [public-images.mjs](butterfly/scripts/public-images.mjs)。它从公开文章、关于正文、通用信息和主题值收集图片引用，包括 Markdown、引用式链接和 HTML 引用，拒绝符号链接及危险路径。

dev 时，模板中间件把白名单 `/img/<name>` 映射到共享图片。build 时，只将白名单图片输出为 `img/<name>`。不要把 `resource/images/` 整个复制，否则仅用于小记或草稿的图片会泄漏。

应用发布端也检查公开图片，但这是额外保护，不能替代模板的隐私实现。远程图片如果允许使用，浏览器需要网络；它们不自动下载为共享资源。主题 image 配置仍只能保存本地 `/img/...` 值。

Butterfly 关闭 Vite 的 public 自动复制，默认背景从 `src/assets/cover.svg` 导入。其他模板若使用 public，必须自行确定公开范围，不能把配置、Markdown 或私有资源放入其中。

## 8. dev/build 启动契约

### 8.1 依赖与 npm 脚本

推荐从 Butterfly 复制依赖声明和锁文件，再按需要修改 package 名称并更新锁文件。运行时依赖和构建依赖都要显式声明，不依赖维护者全局安装的 Vite。

关键配置：

```json
{
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite --host 127.0.0.1",
    "build": "vue-tsc --noEmit && vite build"
  },
  "engines": { "node": ">=22.18.0" }
}
```

此片段不是完整 package.json，依赖请以复制的参考实现为基础。提交 package-lock.json；保持与 package.json 一致。当前应用安装有锁文件时使用 npm ci，否则使用 npm install，包含开发依赖并禁用生命周期脚本。模板不能依赖 postinstall 在用户电脑上偷偷执行必需的生成步骤；必需构建步骤应显式放在 dev/build 中。

### 8.2 本地预览

应用在当前模板目录执行：

```sh
npm run dev -- --host 127.0.0.1 --port <动态端口> --strictPort
```

必须使用传入的端口，不能端口被占后静默切换；监听本机地址，不启动云端服务。当前启动器通常等待 20 秒，模板应在合理时间提供根路径的 HTTP 页面，退出或取消时能被停止。

模板自己监听文章、关于页、图片、通用配置和主题配置变化，更新公开数据并刷新页面。应用不替模板维护文章 HTTP 接口。

预览服务必须阻止直接访问资源原文件、配置、备份、环境文件和源码中的敏感数据。不要为了跨目录读取文章，把整个博客根目录加入无约束的浏览器文件访问范围。复用参考 Vite 中间件、文件白名单与 deny 设置，并在改动后验证。

### 8.3 静态构建与 GitHub Pages

应用在当前模板目录执行：

```sh
npm run build -- --outDir <已创建的绝对临时目录>
```

必须将结果写入传入目录，不能硬编码只写自己目录的 dist。命令退出码必须反映失败，完成后该目录必须有 `index.html`。构建不部署、不登录 GitHub、不修改用户内容。提交与部署由桌面应用完成。

网站必须适用于 `https://用户名.github.io/仓库名/`，不能假设域名根路径。推荐 Vite `base: './'` 和 hash 路由；图片、脚本和 CSS 都要考虑基础路径。使用 history 路由时必须自行实现 Pages 深链接恢复，应用不会提供服务器 rewrite。

构建输出示例：

```text
临时输出/
├── index.html
├── assets/                   # 编译后的 JS/CSS/主题素材
└── img/                      # 公开引用的共享图片
```

不输出原始 Markdown、source map、package.json、锁文件、blog.json、template.json、隐藏文件、符号链接或私有内容。当前应用也拒绝路径包含 `resource`、`template`、`node_modules`、`source` 的输出文件。不要把这些名字用于产物目录。

发布限制为单文件 40 MiB、总计 100 MiB、最多 3000 个文件。`.nojekyll` 与发布标记由应用添加，模板不生成。发布到真实仓库前，先在临时输出目录验证页面和隐私。

## 9. 推荐开发方式

最稳妥的起点是复制 Butterfly，并保留内容与启动适配层，主要替换网站界面：

1. 复制 `template/butterfly/` 到 `template/paper/`，不复制任何依赖或构建结果。
2. 修改 `template.json` 的 ID、名称、字段和初始通用信息，保持目录 ID 一致。
3. 修改 package 名称，更新锁文件；保留可用的 dev/build 和 Node 约束。
4. 复用 content、public-images、Markdown 清理器及 Vite 适配逻辑；替换 App.vue、组件、样式和主题素材。
5. 移除无效字段，不把 Butterfly 专属页面或图片路径当成通用协议。
6. 新模板测试若复用了原模板测试，必须调整断言与夹具，不依赖原主题布局。
7. 在独立测试博客验证后，生成清单并提交源码。

可以重写适配层，但必须实现相同的路径、隐私、命令和产物契约。没有必要修改 Flutter 控制器、业务服务或增加新的应用 API。

### 独立测试博客示例

下面从仓库根目录执行。paper 源码需已经存在，shell 示例面向当前 macOS 开发环境。

```sh
fixture="$(mktemp -d /tmp/inkjian-paper.XXXXXX)"
mkdir -p "$fixture/template" "$fixture/resource/posts" \
  "$fixture/resource/drafts" "$fixture/resource/notes" "$fixture/resource/images"
cp -R template/paper "$fixture/template/paper"
cat > "$fixture/blog.json" <<'JSON'
{
  "formatVersion": 2,
  "activeTemplate": "paper",
  "site": {
    "title": "模板测试", "subtitle": "", "author": "测试作者",
    "description": "", "avatar": ""
  }
}
JSON
printf '# 关于\n\n这是独立测试博客。\n' > "$fixture/resource/about.md"
cd "$fixture/template/paper"
npm ci --ignore-scripts --include=dev
npm run dev -- --host 127.0.0.1 --port 5173 --strictPort
```

先检查没有文章时的页面。停止服务后，在同一个测试模板目录验证构建：

```sh
output="$(mktemp -d /tmp/inkjian-paper-output.XXXXXX)"
npm run build -- --outDir "$output"
```

再向测试博客根目录添加文章、图片和私有内容，重复检查。`activeTemplate` 必须指向正在测试的模板；不要在应用运行同一博客时手工切换其配置，也不要用真实用户博客作为测试夹具。

## 10. 验收清单

交付模板前必须给出实际执行结果，不能把文件存在当成测试通过。

- [ ] ID、配置字段和最低版本有效，本地模板可识别和切换。
- [ ] 空博客可预览、可构建；缺头像、缺背景、无标签时无破损占位。
- [ ] 修改通用信息和三个支持的主题字段，页面表现正确。
- [ ] 文章子目录、中文标题、标签、分类路径、唯一地址与排序正确。
- [ ] 有 description 才显示摘要；删除后隐藏，不从任何位置补摘要。
- [ ] about 单独显示，不参与文章、标签、分类数量。
- [ ] drafts、notes、draft true、published false 均不公开。
- [ ] 正文、封面、头像、主题字段、关于页的共享图片均能访问。
- [ ] 只供私有内容使用的图片不进入输出，也不能通过 dev URL 直接访问。
- [ ] 常见 Markdown、表格、代码块、引用与图片渲染正确，可执行 HTML 被清理。
- [ ] dev 使用指定地址和端口；保存内容与配置后刷新；进程可以停止。
- [ ] build 使用指定 outDir；输出 index.html，不写用户资源、不包含私有文件。
- [ ] 模拟 GitHub Pages 子路径，刷新文章深链接后仍能打开。
- [ ] 清单生成成功，模板文件校验一致；提交中无依赖、构建产物或用户资源。
- [ ] 应用内预览与构建流程验证通过。真实 GitHub 发布需要账户和专用测试仓库，未执行时明确说明。

## 11. 交给其他 AI 的实现提示词

把本指南与仓库一起交给 AI，再补充需要的风格与 ID：

> 请为拾笺 InkJian 新增网站模板，模板 ID 为 paper，视觉要求为【填写需求】。先完整阅读 template/DEVELOPMENT.md，并查看 template/butterfly 的内容适配、图片白名单和启动构建实现。只在 template/paper 内新增模板源码，不修改桌面应用，不加入用户文章或 resource，不复制 node_modules、dist、build。保留 blog.json + resource + template 的博客边界；读取 blog.json.site 与公共 posts/about/images，主题字段只用 text/image/color。必须实现指定端口的 dev 和指定绝对 outDir 的 build，支持 GitHub Pages 子路径，清理 Markdown HTML，保护草稿、小记、配置及私有图片。摘要只取显式 description，无值就隐藏。请先复用现有适配层，再实现新的 Vue 页面与样式；提供可运行的文件、依赖声明、锁文件、template.json 和 README。在独立临时博客执行验收清单，报告实际结果与未验证项；最后提醒维护者生成并提交模板下载清单。不要宣称未执行的发布或平台测试已通过。

## 12. 源码对照

| 实现 | 可核对的约定 |
| --- | --- |
| [ProjectService](../lib/services/project_service.dart) | 博客打开与入口文件检查 |
| [TemplateService](../lib/services/template_service.dart) | 本地及远程模板发现、激活 |
| [TemplateInstaller](../lib/services/template_installer.dart) | 下载校验、代码安装、空资源创建、初始 site 提取 |
| [TemplateConfiguration](../lib/storage/template_configuration.dart) | 字段结构、类型与保存 |
| [清单生成器](../tool/generate_template_manifest.dart) | 模板发现、最低版本、清单字段 |
| [预览辅助代码](../integrations/preview/server.mjs) | dev 命令、端口、就绪与停止 |
| [构建辅助代码](../integrations/preview/build.mjs) | build 参数与网页入口 |
| [BlogBuilder](../lib/services/publishing/blog_builder.dart) | 输入检查、产物限制与隐私保护 |
| [参考 Vite 配置](butterfly/vite.config.ts) | 虚拟内容、白名单图片、监听与基础路径 |

本文说明当前实现，不承诺任意框架、任意远程安装源、自动主题更新或额外字段控件。协议变更时必须同步更新实现、指南、测试和分发清单。
