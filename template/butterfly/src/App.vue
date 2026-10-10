<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import content from 'virtual:blog-content';
import Icon from './components/Icon.vue';
import defaultBackground from './assets/cover.svg';
import { renderMarkdown } from './lib/markdown';
const { site, posts, theme } = content;
const backgroundImage = theme.backgroundImage || '';
const pageSize = 6;
const route = ref(location.hash.slice(1) || '/'),
  page = ref(1),
  mobileMenu = ref(false);
const searchOpen = ref(false),
  query = ref(''),
  searchInput = ref<HTMLInputElement>();
const scrollY = ref(0),
  progress = ref(0),
  copyMessage = ref('复制 Markdown');
const light = ref(false);
try {
  light.value = localStorage.getItem('vue-blog-theme') === 'light';
} catch {
  /* Storage is optional. */
}
const decode = (value: string) => {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
};
const currentPost = computed(() =>
  posts.find(
    (p) =>
      route.value === `/post/${encodeURIComponent(p.id)}` ||
      decode(route.value) === `/post/${p.id}`
  )
);
const section = computed(() => route.value.split('/')[1] || 'home');
const selected = computed(() => decode(route.value.split('/').slice(2).join('/')));
const tagNames = [...new Set(posts.flatMap((p) => p.tags))],
  categoryNames = [...new Set(posts.flatMap((p) => p.categories))];
const filtered = computed(() =>
  posts.filter((p) =>
    section.value === 'tags' && selected.value
      ? p.tags.includes(selected.value)
      : section.value === 'categories' && selected.value
        ? p.categories.includes(selected.value)
        : true
  )
);
const paginated = computed(() =>
  filtered.value.slice((page.value - 1) * pageSize, page.value * pageSize)
);
const pages = computed(() => Math.ceil(filtered.value.length / pageSize));
const results = computed(() =>
  query.value.trim()
    ? posts.filter((p) =>
        `${p.title} ${p.body} ${p.tags.join(' ')}`
          .toLowerCase()
          .includes(query.value.trim().toLowerCase())
      )
    : posts
);
const grouped = computed(() => {
  const groups: Record<string, typeof posts> = {};
  for (const p of filtered.value) (groups[p.date.slice(0, 4)] ||= []).push(p);
  return groups;
});
const rendered = computed(() => renderMarkdown(currentPost.value?.body || content.about));
const title = computed(
  () =>
    currentPost.value?.title ||
    (section.value === 'archives'
      ? '归档'
      : section.value === 'tags'
        ? selected.value || '标签'
        : section.value === 'categories'
          ? selected.value || '分类'
          : section.value === 'about'
            ? '关于'
            : section.value === 'home'
              ? site.title
              : '页面未找到')
);
const urlFor = (id: string) => `#/post/${encodeURIComponent(id)}`;
const asset = (value: string) => {
  if (/^https?:\/\//.test(value)) return value;
  if (/^[a-z]+:/i.test(value)) return '';
  return `${import.meta.env.BASE_URL}${value.replace(/^\/+/, '')}`;
};
// Theme artwork stays in the website; user-selected images live in resource/images.
const background = (value = '') => value ? asset(value) : defaultBackground;
const date = (value: string) =>
  new Date(value)
    .toLocaleDateString('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      timeZone: 'Asia/Shanghai',
    })
    .replaceAll('/', '-');
const words = (body: string) => body.replace(/\s/g, '').length;
const updateScroll = () => {
  scrollY.value = window.scrollY;
  const height = document.documentElement.scrollHeight - window.innerHeight;
  progress.value = height > 0 ? Math.min(100, (window.scrollY / height) * 100) : 0;
};
const updateRoute = () => {
  route.value = location.hash.slice(1) || '/';
  page.value = 1;
  mobileMenu.value = false;
  searchOpen.value = false;
  window.scrollTo(0, 0);
};
const onKey = (event: KeyboardEvent) => {
  if (event.key === 'Escape') searchOpen.value = false;
};
async function showSearch() {
  searchOpen.value = true;
  await nextTick();
  searchInput.value?.focus();
}
function toggleTheme() {
  light.value = !light.value;
  try {
    localStorage.setItem('vue-blog-theme', light.value ? 'light' : 'dark');
  } catch {}
}
function scrollContent() {
  document.getElementById('content')?.scrollIntoView({
    behavior: matchMedia('(prefers-reduced-motion: reduce)').matches
      ? 'instant'
      : 'smooth',
  });
}
function scrollTop() {
  window.scrollTo({ top: 0, behavior: 'smooth' });
}
function scrollHeading(id: string) {
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
}
async function copyBody() {
  try {
    await navigator.clipboard.writeText(currentPost.value?.body || '');
    copyMessage.value = '已复制';
  } catch {
    copyMessage.value = '复制失败，请手动选择正文';
  }
}
watch(
  [route, currentPost],
  () => {
    document.title =
      section.value === 'home'
        ? `${site.title} - ${site.subtitle}`
        : `${title.value} | ${site.title}`;
    document
      .querySelector('meta[name="description"]')
      ?.setAttribute('content', currentPost.value?.summary || site.description);
    copyMessage.value = '复制 Markdown';
  },
  { immediate: true }
);
watch(searchOpen, (value) => {
  document.body.style.overflow = value ? 'hidden' : '';
});
onMounted(() => {
  window.addEventListener('hashchange', updateRoute);
  window.addEventListener('scroll', updateScroll, { passive: true });
  window.addEventListener('keydown', onKey);
});
onUnmounted(() => {
  window.removeEventListener('hashchange', updateRoute);
  window.removeEventListener('scroll', updateScroll);
  window.removeEventListener('keydown', onKey);
  document.body.style.overflow = '';
});
const postIndex = computed(() => posts.findIndex((p) => p.id === currentPost.value?.id));
</script>
<template>
  <div
    class="blog"
    :class="{ light }"
    :style="{
      '--accent': content.theme?.themeColor || '#87968B',
      '--background-image': `url('${background(backgroundImage)}')`,
    }"
  >
    <div class="reading-progress" :style="{ width: `${progress}%` }" />
    <header
      class="hero"
      :class="{ 'home-hero': section === 'home', 'post-hero': currentPost }"
      :style="{
        backgroundImage:
          `url('${background(currentPost?.cover || backgroundImage)}')`,
      }"
    >
      <nav class="top-nav" :class="{ fixed: scrollY > 80 }" aria-label="主导航">
        <a class="site-brand" href="#/">{{ site.title }}<span class="brand-dot" /></a>
        <button
          class="menu-toggle"
          aria-label="展开导航"
          @click="mobileMenu = !mobileMenu"
        >
          <Icon name="book" />
        </button>
        <div class="nav-links" :class="{ open: mobileMenu }">
          <button @click="showSearch"><Icon name="search" :size="17" /> 搜索</button>
          <a href="#/" :class="{ active: section === 'home' }"
            ><Icon name="home" :size="17" /> 首页</a
          >
          <a href="#/archives" :class="{ active: section === 'archives' }"
            ><Icon name="archive" :size="17" /> 归档</a
          >
          <a href="#/tags" :class="{ active: section === 'tags' }"
            ><Icon name="tag" :size="17" /> 标签</a
          >
          <a href="#/categories" :class="{ active: section === 'categories' }"
            ><Icon name="folder" :size="17" /> 分类</a
          >
          <a href="#/about" :class="{ active: section === 'about' }"
            ><Icon name="user" :size="17" /> 关于</a
          >
          <button
            @click="toggleTheme"
            :aria-label="light ? '切换暗色模式' : '切换亮色模式'"
          >
            <Icon :name="light ? 'moon' : 'sun'" :size="18" />
          </button>
        </div>
      </nav>
      <div class="hero-copy">
        <span class="hero-kicker">{{
          section === 'home'
            ? 'A PLACE FOR THOUGHTS & STORIES'
            : currentPost
              ? currentPost.categories.join(' / ') || '文章'
              : 'RECORDS & MEMORIES'
        }}</span>
        <h1>{{ title }}</h1>
        <p v-if="section === 'home'">{{ site.subtitle }}<span class="cursor">|</span></p>
        <div v-else-if="currentPost" class="hero-meta">
          <span
            ><Icon name="calendar" :size="15" /> 发表于 {{ date(currentPost.date) }}</span
          ><span>更新于 {{ date(currentPost.updated) }}</span
          ><span
            >{{ words(currentPost.body) }} 字 ·
            {{ Math.max(1, Math.ceil(words(currentPost.body) / 450)) }} 分钟阅读</span
          >
        </div>
        <p v-else>
          {{
            section === 'archives'
              ? `目前共计 ${posts.length} 篇文章，继续加油！`
              : section === 'about'
                ? '在这里，留下一点自己的声音。'
                : '沿着一个主题，发现更多记录。'
          }}
        </p>
      </div>
      <button
        v-if="section === 'home'"
        class="scroll-down"
        @click="scrollContent"
        aria-label="向下阅读文章"
      >
        <span>SCROLL TO EXPLORE</span><Icon name="down" :size="25" />
      </button>
      <div class="hero-bottom" v-if="section === 'home'">
        <span>记录，让每一个平凡的日子有迹可循。</span
        ><span
          >{{ String(posts.length).padStart(2, '0') }} STORIES / {{ site.author }}</span
        >
      </div>
    </header>
    <main id="content" class="layout">
      <section class="main-column">
        <template v-if="section === 'home'">
          <div class="list-heading">
            <div>
              <span class="eyebrow">RECENT POSTS</span>
              <h2>最近更新<span class="tiny-dot" /></h2>
            </div>
            <span>{{ posts.length }} 篇文章</span>
          </div>
          <article
            v-for="(post, index) in paginated"
            :key="post.id"
            class="post-card panel"
            :class="{ reverse: index % 2 === 1 }"
          >
            <a :href="urlFor(post.id)" class="post-cover"
              ><img
                :src="background(post.cover || backgroundImage)"
                :alt="post.title"
                loading="lazy"
              /><span>{{ post.categories[0] || '随笔' }}</span></a
            >
            <div class="post-info">
              <div class="post-date">
                <Icon name="calendar" :size="14" /> {{ date(post.date) }}<span>·</span
                >{{ Math.max(1, Math.ceil(words(post.body) / 450)) }} 分钟阅读
              </div>
              <h2>
                <a :href="urlFor(post.id)">{{ post.title }}</a>
              </h2>
              <p v-if="post.summary">{{ post.summary }}</p>
              <div class="card-bottom">
                <div class="post-tags">
                  <a
                    v-for="tag in post.tags"
                    :key="tag"
                    :href="`#/tags/${encodeURIComponent(tag)}`"
                    ># {{ tag }}</a
                  >
                </div>
                <a
                  class="read-more"
                  :href="urlFor(post.id)"
                  :aria-label="`阅读 ${post.title}`"
                  ><Icon name="arrow" :size="20"
                /></a>
              </div>
            </div>
          </article>
          <div v-if="!posts.length" class="empty panel">
            <h2>第一篇故事，即将开始。</h2>
            <p>欢迎回来，这里会收藏你的文字。</p>
          </div>
          <nav v-if="pages > 1" class="pagination" aria-label="文章分页">
            <button
              v-for="n in pages"
              :key="n"
              @click="
                page = n;
                scrollContent();
              "
              :class="{ active: page === n }"
            >
              {{ n }}
            </button>
          </nav>
        </template>
        <article v-else-if="currentPost" class="article panel">
          <div v-if="currentPost.summary" class="article-summary">
            {{ currentPost.summary }}
          </div>
          <div class="prose" v-html="rendered.html" />
          <div class="article-license">
            <div><strong>文章作者：</strong>{{ site.author }}</div>
            <div><strong>版权声明：</strong>转载请注明作者与出处。</div>
            <button class="text-button" @click="copyBody">
              <Icon name="note" :size="15" /> {{ copyMessage }}
            </button>
          </div>
          <div class="article-tags">
            <a
              v-for="tag in currentPost.tags"
              :key="tag"
              :href="`#/tags/${encodeURIComponent(tag)}`"
              ><Icon name="tag" :size="14" /> {{ tag }}</a
            >
          </div>
          <div class="post-navigation">
            <a v-if="posts[postIndex - 1]" :href="urlFor(posts[postIndex - 1]!.id)"
              ><small>上一篇</small><strong>{{ posts[postIndex - 1]!.title }}</strong></a
            ><a v-if="posts[postIndex + 1]" :href="urlFor(posts[postIndex + 1]!.id)"
              ><small>下一篇</small><strong>{{ posts[postIndex + 1]!.title }}</strong></a
            >
          </div>
        </article>
        <section v-else-if="section === 'about'" class="about panel">
          <span class="eyebrow">HELLO, WORLD</span>
          <h2>你好，我是 {{ site.author }}。</h2>
          <div class="prose" v-html="rendered.html" />
          <div class="about-sign">
            {{ site.subtitle }}<Icon name="feather" :size="32" />
          </div>
        </section>
        <section
          v-else-if="['archives', 'tags', 'categories'].includes(section)"
          class="collection panel"
        >
          <template v-if="(section === 'tags' || section === 'categories') && !selected"
            ><h2>
              {{
                section === 'tags'
                  ? `标签 · ${tagNames.length}`
                  : `分类 · ${categoryNames.length}`
              }}
            </h2>
            <div class="taxonomy" :class="{ categories: section === 'categories' }">
              <a
                v-for="(name, index) in section === 'tags' ? tagNames : categoryNames"
                :key="name"
                :href="`#/${section}/${encodeURIComponent(name)}`"
                :style="{ '--tag-size': `${17 + (index % 3) * 4}px` }"
                >{{ name
                }}<sup>{{
                  posts.filter((p) =>
                    (section === 'tags' ? p.tags : p.categories).includes(name)
                  ).length
                }}</sup></a
              >
            </div></template
          >
          <template v-else
            ><h2>
              {{ section === 'archives' ? '文章总览' : selected }}
              <span class="collection-count">{{ filtered.length }} 篇文章</span>
            </h2>
            <div v-if="!filtered.length" class="empty">
              <p>这个主题下暂时没有文章。</p>
              <a :href="`#/${section}`" class="text-button">返回全部主题</a>
            </div>
            <div class="timeline" v-for="(items, year) in grouped" :key="year">
              <h3>{{ year }}</h3>
              <a
                v-for="post in items"
                :key="post.id"
                :href="urlFor(post.id)"
                class="timeline-post"
                ><img
                  :src="background(post.cover || backgroundImage)"
                  :alt="post.title"
                  loading="lazy" />
                <div>
                  <time>{{ date(post.date) }}</time>
                  <h4>{{ post.title }}</h4>
                </div>
                <Icon name="arrow" :size="17"
              /></a></div
          ></template>
        </section>
        <section v-else class="empty panel">
          <span class="error-code">404</span>
          <h2>这一页，还没有故事。</h2>
          <a href="#/" class="primary-button"
            >返回首页 <Icon name="arrow" :size="17"
          /></a>
        </section>
      </section>
      <aside class="sidebar">
        <section class="profile panel">
          <img v-if="site.avatar" :src="asset(site.avatar)" :alt="`${site.author} 的头像`" class="avatar" />
          <h2>{{ site.author }}</h2>
          <p>{{ site.description }}</p>
          <div class="profile-stats">
            <a href="#/archives"
              ><span>文章</span><strong>{{ posts.length }}</strong></a
            ><a href="#/tags"
              ><span>标签</span><strong>{{ tagNames.length }}</strong></a
            ><a href="#/categories"
              ><span>分类</span><strong>{{ categoryNames.length }}</strong></a
            >
          </div>
          <a class="primary-button" href="#/about"
            ><Icon name="feather" :size="17" /> 关于我</a
          >

        </section>
        <section class="panel sidebar-card announcement">
          <h3><Icon name="megaphone" :size="19" /> 公告</h3>
          <p>{{ theme.announcement }}</p>
        </section>
        <section
          v-if="currentPost && rendered.headings.length"
          class="panel sidebar-card toc"
        >
          <h3><Icon name="list" :size="19" /> 文章目录</h3>
          <button
            v-for="heading in rendered.headings"
            :key="heading.id"
            @click="scrollHeading(heading.id)"
            :style="{ paddingLeft: `${(heading.level - 1) * 10}px` }"
          >
            {{ heading.text }}
          </button>
        </section>
        <section class="panel sidebar-card">
          <h3><Icon name="clock" :size="18" /> 最新文章</h3>
          <a
            v-for="post in posts.slice(0, 5)"
            :key="post.id"
            :href="urlFor(post.id)"
            class="recent-post"
            ><img :src="background(post.cover || backgroundImage)" alt="" loading="lazy" />
            <div>
              <span>{{ post.title }}</span
              ><small>{{ date(post.date) }}</small>
            </div></a
          >
        </section>
        <section v-if="categoryNames.length" class="panel sidebar-card">
          <h3><Icon name="folder" :size="18" /> 分类</h3>
          <a
            v-for="category in categoryNames"
            :key="category"
            :href="`#/categories/${encodeURIComponent(category)}`"
            class="category-link"
            ><span>{{ category }}</span
            ><span>{{
              posts.filter((p) => p.categories.includes(category)).length
            }}</span></a
          >
        </section>
        <section v-if="tagNames.length" class="panel sidebar-card">
          <h3><Icon name="tag" :size="18" /> 标签</h3>
          <div class="sidebar-tags">
            <a
              v-for="tag in tagNames"
              :key="tag"
              :href="`#/tags/${encodeURIComponent(tag)}`"
              >{{ tag }}</a
            >
          </div>
        </section>
        <section class="panel sidebar-card site-info">
          <h3><Icon name="chart" :size="18" /> 网站资讯</h3>
          <p>
            文章数目 <span>{{ posts.length }}</span>
          </p>
          <p>
            最近更新
            <span>{{
              posts[0]
                ? date(
                    [...posts].sort((a, b) => b.updated.localeCompare(a.updated))[0]!
                      .updated
                  )
                : '暂无'
            }}</span>
          </p>
          <p>驱动 <span>Vue 3 · Vite</span></p>
        </section>
      </aside>
    </main>
    <footer>
      <p>© {{ new Date().getFullYear() }} {{ site.author }}</p>
      <p>{{ site.subtitle }}</p>
      <span>拾笺 InkJian · Butterfly 风格</span>
    </footer>
    <div class="right-tools">
      <button @click="toggleTheme" :aria-label="light ? '切换暗色模式' : '切换亮色模式'">
        <Icon :name="light ? 'moon' : 'sun'" :size="19" /></button
      ><button v-if="scrollY > 300" @click="scrollTop" aria-label="回到顶部">
        <Icon name="up" :size="19" />
      </button>
    </div>
    <Teleport to="body"
      ><div v-if="searchOpen" class="search-overlay" @click.self="searchOpen = false">
        <section
          class="search-dialog"
          role="dialog"
          aria-modal="true"
          aria-labelledby="search-title"
        >
          <div class="search-dialog-header">
            <h2 id="search-title">搜索文章</h2>
            <button aria-label="关闭搜索" @click="searchOpen = false">
              <Icon name="close" />
            </button>
          </div>
          <label class="search-input"
            ><Icon name="search" /><input
              ref="searchInput"
              v-model="query"
              placeholder="搜索标题、正文、标签…"
              aria-label="搜索关键词" /></label
          ><span class="search-count">{{ results.length }} 篇文章</span>
          <div class="search-results">
            <a
              v-for="post in results"
              :key="post.id"
              :href="urlFor(post.id)"
              @click="searchOpen = false"
              ><strong>{{ post.title }}</strong>
              <p v-if="post.summary">{{ post.summary }}</p>
              <small>{{ date(post.date) }}</small></a
            >
            <p v-if="!results.length" class="empty">
              没有找到相关文章，换一个关键词试试。
            </p>
          </div>
          <div class="search-hint">按 ESC 关闭</div>
        </section>
      </div></Teleport
    >
  </div>
</template>
