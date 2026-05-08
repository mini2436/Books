# private_reader_project_promo - Design Spec

> This document is the human-readable design narrative — rationale, audience, style, color choices, content outline. It is read once by downstream roles for context.
>
> The machine-readable execution contract lives in `spec_lock.md` (short form of color / typography / icon / image decisions). Executor re-reads `spec_lock.md` before every SVG page to resist context-compression drift. Keep the two files in sync; if they diverge, `spec_lock.md` wins.

## I. Project Information

| Item | Value |
| ---- | ----- |
| **Project Name** | private_reader_project_promo |
| **Canvas Format** | PPT 16:9 (1280x720) |
| **Page Count** | 8 pages |
| **Design Style** | General Consulting |
| **Target Audience** | 潜在合作方、内部决策者、技术负责人、项目评审对象 |
| **Use Case** | 用于项目宣传、阶段成果展示、商务介绍与路演汇报 |
| **Created Date** | 2026-04-24 |

---

## II. Canvas Specification

| Property | Value |
| -------- | ----- |
| **Format** | PPT 16:9 |
| **Dimensions** | 1280x720 |
| **viewBox** | `0 0 1280 720` |
| **Margins** | left/right 54px, top 42px, bottom 34px |
| **Content Area** | 1172x644 |

---

## III. Visual Theme

### Theme Style

- **Style**: General Consulting
- **Theme**: Light theme
- **Tone**: 商务、稳健、科技感、平台化、可信赖

### Color Scheme

| Role | HEX | Purpose |
| ---- | --- | ------- |
| **Background** | `#F6F8FB` | 页面底色，保持洁净商务感 |
| **Secondary bg** | `#E9EEF5` | 卡片底色、区块衬底 |
| **Primary** | `#0F2747` | 主标题、核心结构线、深色重点 |
| **Accent** | `#1565C0` | 关键数字、流程节点、高亮标签 |
| **Secondary accent** | `#2FA39A` | 次级强调、状态与路线图衔接 |
| **Body text** | `#1A2433` | 正文文本 |
| **Secondary text** | `#5B6678` | 说明文字、注释 |
| **Tertiary text** | `#8893A3` | 页脚、来源、辅助信息 |
| **Border/divider** | `#D6DDE8` | 分割线、边框 |
| **Success** | `#2E8B57` | 正向结果、完成状态 |
| **Warning** | `#C94B4B` | 风险、边界提示 |

### Gradient Scheme (if needed, using SVG syntax)

```xml
<!-- Title gradient -->
<linearGradient id="titleGradient" x1="0%" y1="0%" x2="100%" y2="100%">
  <stop offset="0%" stop-color="#0F2747"/>
  <stop offset="100%" stop-color="#1565C0"/>
</linearGradient>

<!-- Background decorative gradient -->
<radialGradient id="bgDecor" cx="82%" cy="18%" r="56%">
  <stop offset="0%" stop-color="#1565C0" stop-opacity="0.16"/>
  <stop offset="100%" stop-color="#1565C0" stop-opacity="0"/>
</radialGradient>
```

---

## IV. Typography System

### Font Plan

**Typography direction**: modern CJK sans

| Role | Chinese | English | Fallback tail |
| ---- | ------- | ------- | ------------- |
| **Title** | `"Microsoft YaHei", "PingFang SC"` | `Arial` | `sans-serif` |
| **Body** | `"Microsoft YaHei", "PingFang SC"` | `Arial` | `sans-serif` |
| **Emphasis** | `SimSun` | `Georgia` | `serif` |
| **Code** | — | `Consolas, "Courier New"` | `monospace` |

**Per-role font stacks**:

- Title: `"Microsoft YaHei", "PingFang SC", Arial, sans-serif`
- Body: `"Microsoft YaHei", "PingFang SC", Arial, sans-serif`
- Emphasis: `Georgia, SimSun, serif`
- Code: `Consolas, "Courier New", monospace`

### Font Size Hierarchy

**Baseline**: Body font size = 20px

| Purpose | Ratio to body | Example @ body=24 (relaxed) | Example @ body=18 (dense) | Weight |
| ------- | ------------- | --------------------------- | ------------------------- | ------ |
| Cover title (hero headline) | 2.5-5x | 60-120px | 45-90px | Bold / Heavy |
| Chapter / section opener | 2-2.5x | 48-60px | 36-45px | Bold |
| Page title | 1.5-2x | 36-48px | 27-36px | Bold |
| Hero number (consulting KPIs) | 1.5-2x | 36-48px | 27-36px | Bold |
| Subtitle | 1.2-1.5x | 29-36px | 22-27px | SemiBold |
| **Body content** | **1x** | **24px** | **18px** | Regular |
| Annotation / caption | 0.7-0.85x | 17-20px | 13-15px | Regular |
| Page number / footnote | 0.5-0.65x | 12-16px | 9-12px | Regular |

---

## V. Layout Principles

### Page Structure

- **Header area**: 88px，高度固定，包含页码、标题、摘要结论条
- **Content area**: 540px，承载卡片、原型图、流程和结构信息
- **Footer area**: 42px，放置来源与项目标识

### Layout Pattern Library (combine or break as content demands)

| Pattern | Suitable Scenarios |
| ------- | ----------------- |
| **Single column centered** | 封面、结束页、价值主张页 |
| **Asymmetric split (3:7 / 2:8)** | 左侧图示，右侧结论；或左侧结论，右侧产品画面 |
| **Top-bottom split** | 结构化摘要 + 底部流程图 |
| **Three/four column cards** | 核心能力拆解、里程碑总结 |
| **Matrix grid (2×2)** | 双维度卖点、业务能力归类 |
| **Figure-text overlap** | 封面与产品体验页，利用原型图构建层次 |
| **Negative-space-driven** | 路线图、价值承诺、结语页 |

### Spacing Specification

**Universal** (any container type):

| Element | Recommended Range | Current Project |
| ------- | ---------------- | --------------- |
| Safe margin from canvas edge | 40-60px | 54px |
| Content block gap | 24-40px | 28px |
| Icon-text gap | 8-16px | 12px |

**Card-based layouts**:

| Element | Recommended Range | Current Project |
| ------- | ---------------- | --------------- |
| Card gap | 20-32px | 24px |
| Card padding | 20-32px | 24px |
| Card border radius | 8-16px | 14px |
| Single-row card height | 530-600px | 548px |
| Double-row card height | 265-295px each | 268px |
| Three-column card width | 360-380px each | 374px |

**Non-card containers**:

- 行高保持在正文的 1.45-1.55 倍
- 大图页优先用留白和渐变罩层而不是多重卡片
- 重要原型图保持完整轮廓，避免切得过碎影响可信度

---

## VI. Icon Usage Specification

### Source

- **Built-in icon library**: `templates/icons/`
- **Usage method**: Placeholder format `{{icon:category/icon-name}}`

### Recommended Icon List (fill as needed)

| Purpose | Icon Path | Page |
| ------- | --------- | ---- |
| 平台定位 | `{{icon:chunk/target}}` | Slide 02 |
| 扩展能力 | `{{icon:chunk/card-stack}}` | Slide 03 |
| 离线同步 | `{{icon:chunk/cloud-arrow-up}}` | Slide 03 |
| 团队协作 | `{{icon:chunk/users}}` | Slide 03 |
| 管理控制 | `{{icon:chunk/shield}}` | Slide 05 |
| 数据图景 | `{{icon:chunk/chart-bar}}` | Slide 07 |
| 移动主端 | `{{icon:chunk/mobile}}` | Slide 04 |
| 技术基座 | `{{icon:chunk/server}}` | Slide 06 |
| 创新方向 | `{{icon:chunk/lightbulb}}` | Slide 08 |
| 增长趋势 | `{{icon:chunk/arrow-trend-up}}` | Slide 07 |

---

## VII. Visualization Reference List (if needed)

| Visualization Type | Reference Template | Used In |
| ------------------ | ------------------ | ------- |
| process_flow | `templates/charts/process_flow.svg` | Slide 05 |

---

## VIII. Image Resource List (if needed)

| Filename | Dimensions | Ratio | Purpose | Type | Status | Generation Description |
| -------- | --------- | ----- | ------- | ---- | ------ | --------------------- |
| private-reader-app-icon-preview-rounded.png | 1024x1024 | 1.00 | 封面品牌识别、结束页视觉锚点 | Decorative | Existing | - |
| bookshelf-prototype.png | 914x2084 | 0.44 | 展示书架页真实产品界面 | Photography | Existing | - |
| login-prototype.png | 914x2084 | 0.44 | 展示登录与会话入口界面 | Photography | Existing | - |
| prototype-nav.png | 929x873 | 1.06 | 展示导航架构与后台入口布局 | Illustration | Existing | - |
| reader-kraft-prototype.png | 914x918 | 1.00 | 展示阅读器主题一 | Photography | Existing | - |
| reader-light-prototype.png | 929x918 | 1.01 | 展示阅读器明亮主题 | Photography | Existing | - |
| reader-night-prototype.png | 914x918 | 1.00 | 展示阅读器夜间主题 | Photography | Existing | - |

---

## IX. Content Outline

### Part 1: 项目概览

#### Slide 01 - Cover

- **Layout**: 深蓝渐变背景 + 左侧主标题 + 右侧品牌图标与三块能力标签
- **Title**: Private Reader
- **Subtitle**: 面向团队与机构的私有阅读平台
- **Info**: 自托管、多用户、可扩展、离线优先

#### Slide 02 - 项目定位

- **Layout**: 左侧结论区，右侧 2x2 能力矩阵
- **Title**: 一个能兼顾阅读体验与平台治理的私有阅读基础设施
- **Takeaway**: 项目不是单点阅读工具，而是一套覆盖读者端、后台端与资源入库链路的完整平台能力。
- **Content**:
  - 机构级私有化部署
  - 多用户权限体系
  - 统一阅读闭环
  - 后续可向 Web/Desktop 收敛

### Part 2: 产品能力

#### Slide 03 - 核心能力

- **Layout**: 四张 KPI / capability cards + 下方能力补充条
- **Title**: 第一阶段已经打通四条关键业务链路
- **Takeaway**: 账号体系、阅读闭环、离线同步、后台与扫描能力都已形成可演示、可继续演进的基线。
- **Content**:
  - 登录与会话恢复
  - 书架到阅读器闭环
  - 批注 / 书签 / 进度同步
  - 后台管理与资源扫描

#### Slide 04 - 产品体验

- **Layout**: 左侧产品结论与体验标签，右侧原型图拼贴
- **Title**: Flutter App 已具备真实可感知的阅读体验与管理入口
- **Takeaway**: 从登录、书架到阅读器与后台入口，产品体验已经形成连续路径，而不是零散页面集合。
- **Content**:
  - 登录、书架、阅读器完整路径
  - 手机与平板统一代码基线
  - 浮层式阅读器交互
  - 多阅读主题与设置能力

#### Slide 05 - 管理与导入

- **Layout**: 上方一句结论，左侧后台能力清单，右侧扫描导入流程图
- **Title**: 管理后台把“资源接入到内容入库”的动作真正流程化
- **Takeaway**: 系统不仅服务读者，也服务管理者，让 WebDAV 书库接入、扫描和入库形成高效链路。
- **Content**:
  - 用户 / 角色 / 书籍 / 批注 / 资源扫描
  - 扫描源配置
  - 扫描任务触发
  - 图书入库与后台可见

### Part 3: 技术与发展

#### Slide 06 - 技术架构

- **Layout**: 左侧三层架构示意，右侧技术要点卡片
- **Title**: 架构以可扩展与可交付为目标，兼顾当前落地与未来演进
- **Takeaway**: 后端、格式插件、Flutter 多端基座之间已经形成清晰边界，为 Native Image 和多端扩展预留了空间。
- **Content**:
  - Kotlin + Spring Boot 3
  - plugin-api / plugin-epub / plugin-pdf / plugin-txt
  - Flutter app / data / features / shared 分层
  - Native-ready 与多端迁移路线

#### Slide 07 - 阶段成果

- **Layout**: 左侧大号结论数字组，右侧阶段成果与边界说明
- **Title**: 阶段一已达到“可提交、可继续演进”的交付状态
- **Takeaway**: 当前基线足以用于演示、评审和后续投资判断，且后续方向已经明确，不存在主线摇摆。
- **Content**:
  - 3 类格式插件已集成
  - 3 类角色体系已跑通
  - 5 个后台核心分区可用
  - Web 端已移除，前端路线收敛到 Flutter

#### Slide 08 - 路线图与价值

- **Layout**: 左侧未来路线图，右侧合作价值总结
- **Title**: 下一阶段将把既有能力升级为统一的多端阅读与管理平台
- **Takeaway**: 项目价值不止于“做出一个 App”，而在于沉淀一套可持续扩展的数字阅读平台基座。
- **Content**:
  - 后台先行适配 Web/Desktop
  - 统一前端壳层与设计 token
  - 迁移书架、账户、阅读器能力
  - 形成面向团队与机构的长期平台价值

---

## X. Speaker Notes Requirements

- 每页控制在 2-4 句，采用“结论先行 + 支撑解释”结构
- 第 2 页起使用 `[过渡]` 标签开启，与上一页形成自然衔接
- 涉及事实数字时只引用已知材料中的真实数量，不补造业务数据
- 每页保留 `要点：` 与 `时长：` 字段，方便后续路演裁剪

---

## XI. Technical Constraints Reminder

- 全部页面使用 PPT 兼容 SVG 语法，不使用 `<style>`、`class`、`foreignObject`、`rgba()`、`<g opacity>`
- 全部字体栈遵守 PPT-safe 规则
- 全部图标仅使用 `chunk` 图标库，不混用
- 全部图片均来自 `images/` 中现有素材
- 数据表达只使用项目文档中可验证的事实，不虚构商业指标
