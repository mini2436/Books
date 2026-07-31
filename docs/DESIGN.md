---
name: "轻阅 · Private Reader"
description: "以纸墨阅读为中心、以克制透明玻璃承载操作的跨端家庭阅读界面"
colors:
  brand-walnut: "#7A4A24"
  eye-care-green: "#4A6B3F"
  night-amber: "#C3924A"
  paper-background: "#FFFFFF"
  paper-surface: "#FFFFFFF2"
  paper-ink: "#1A1A1A"
  paper-ink-secondary: "#666666"
  paper-ink-tertiary: "#737373"
  paper-line: "#00000014"
  kraft-background: "#F5F0E6"
  kraft-surface: "#F5F0E6F2"
  kraft-ink: "#2C241B"
  kraft-ink-secondary: "#5E5043"
  kraft-ink-tertiary: "#706254"
  kraft-line: "#3C28141A"
  eye-care-background: "#E3EBDE"
  eye-care-surface: "#E3EBDEF2"
  eye-care-ink: "#233222"
  eye-care-ink-secondary: "#4A5E43"
  eye-care-ink-tertiary: "#55694F"
  eye-care-line: "#283C1E1A"
  night-background: "#17171A"
  night-surface: "#1E1E22F2"
  night-ink: "#C8C8C8"
  night-ink-secondary: "#888888"
  night-ink-tertiary: "#87878A"
  night-line: "#FFFFFF14"
  destructive: "#D93025"
typography:
  display:
    fontFamily: "MiSans, Microsoft YaHei, PingFang SC, Noto Sans CJK SC, sans-serif"
    fontSize: "26px"
    fontWeight: 700
    lineHeight: 1.25
  headline:
    fontFamily: "MiSans, Microsoft YaHei, PingFang SC, Noto Sans CJK SC, sans-serif"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.3
  title:
    fontFamily: "MiSans, Microsoft YaHei, PingFang SC, Noto Sans CJK SC, sans-serif"
    fontSize: "18px"
    fontWeight: 600
    lineHeight: 1.4
  body:
    fontFamily: "MiSans, Microsoft YaHei, PingFang SC, Noto Sans CJK SC, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.5
  reader-body:
    fontFamily: "MiSans, SourceHanSerifSC, LXGWWenKai, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.8
  label:
    fontFamily: "MiSans, Microsoft YaHei, PingFang SC, Noto Sans CJK SC, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.3
rounded:
  book-cover: "4px"
  field: "14px"
  action: "16px"
  phone-surface: "20px"
  wide-surface: "22px"
  phone-dialog: "26px"
  wide-dialog: "28px"
  pill: "999px"
spacing:
  unit: "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
  page-phone: "16px"
  page-wide: "24px"
components:
  button-primary:
    backgroundColor: "{colors.brand-walnut}"
    textColor: "#FFFFFF"
    rounded: "{rounded.action}"
    padding: "12px 18px"
    height: "48px"
  button-glass-action:
    backgroundColor: "{colors.paper-surface}"
    textColor: "{colors.paper-ink}"
    rounded: "{rounded.action}"
    padding: "12px 18px"
    height: "48px"
  input-standard:
    backgroundColor: "{colors.paper-surface}"
    textColor: "{colors.paper-ink}"
    rounded: "{rounded.field}"
    height: "48px"
  card-glass:
    backgroundColor: "{colors.paper-surface}"
    textColor: "{colors.paper-ink}"
    rounded: "{rounded.phone-surface}"
    padding: "16px"
  control-segmented:
    backgroundColor: "{colors.paper-surface}"
    textColor: "{colors.paper-ink-secondary}"
    rounded: "{rounded.pill}"
    padding: "4px"
    height: "50px"
---

# Design System: 轻阅 · Private Reader

> 本文档记录当前 Flutter Web、Windows、Android 与平板端的实际设计实现。代码中的主题与组件是最终依据；本文档用于设计评审、页面扩展和 AI 辅助开发。

## Overview

**Creative North Star: “纸页之上的轻透界面”**

轻阅是一套面向家庭私有书库的任务型产品界面。它的视觉重心永远是书籍封面和阅读正文：纸张负责承载内容，透明玻璃负责承载导航、选择、设置和临时操作。玻璃不是背景装饰，而是一种把操作层从阅读层中分离出来的功能材质。

整体气质克制、安静、可靠。暖棕色维持家庭书房与实体书的关联，牛皮纸和护眼主题提供不同环境下的舒适阅读，夜间主题降低亮度与蓝光。界面拒绝营销式大标题、过量卡片、炫技动效和随处模糊；用户应该先看到书与文字，再注意到控件。

响应式变化必须改变结构，而不仅是缩放尺寸：手机使用底部悬浮导航和 Bottom Sheet，平板与桌面使用侧边导航与宽屏面板；阅读正文在宽屏仍保持最大宽度（680px）。常规状态反馈采用 150–250ms；所有非必要动效尊重系统“减少动态效果”设置。

**Key Characteristics:**

- 纸面内容与玻璃操作层职责分离。
- 四套阅读主题共用相同语义色位与组件结构。
- 手机、平板、Web、桌面拥有独立材质参数，而非一套数值强行缩放。
- MiSans 统一 UI，阅读正文允许用户选择思源宋体或霞鹜文楷。
- 强调色只用于主操作、选中态和进度，不承担装饰职责。

## Colors

色彩采用“主题背景 + 同主题玻璃表面 + 单一强调色”的克制策略。顶部 YAML 中的颜色是规范值；运行时由 `AppReaderPalette` 映射为 `background`、`panel`、`ink`、`accent`、`line` 等语义角色。

### Primary

- **书脊胡桃棕**：默认白与牛皮纸主题的主操作、选中态、进度和焦点色；单屏面积必须保持克制。
- **护眼苔绿**：仅在护眼主题替代胡桃棕，避免棕色落在绿色纸面上显脏。
- **夜读琥珀**：仅在夜间主题提供低蓝光的高可见操作与选中反馈。

### Neutral

- **清纸白**：默认内容底色；阅读正文保持实色，不叠加玻璃模糊。
- **牛皮纸米色**：模拟温和的实体纸张，只服务阅读与相邻表面。
- **护眼灰绿**：长时间阅读的低刺激底色，文字使用同色相深绿而非中性灰。
- **夜读炭黑**：夜间内容底色；正文使用暖灰，不使用纯白。
- **主题玻璃面**：由对应主题底色生成半透明面板，不能跨主题混用。

### Named Rules

**The One Accent Rule.** 一个界面状态只允许一个主题强调色；未选中控件不得使用高饱和色争夺注意力。

**The Paper Stays Solid Rule.** 阅读正文、封面和需要精确辨认的数据区域保持稳定实色；玻璃仅用于覆盖层、导航、工具栏、对话框和临时控件。

**The Themed Gray Rule.** 有色背景上的次级文字必须使用该主题的同色相深色，不得直接套用通用浅灰。

## Typography

**Display Font:** MiSans（后备为 Microsoft YaHei、PingFang SC、Noto Sans CJK SC、sans-serif）

**Body Font:** MiSans（同一后备栈）

**Reader Font:** MiSans / SourceHanSerifSC / LXGWWenKai（由用户选择）

**Character:** UI 采用单一、现代、低干扰的中文无衬线字体，保证管理界面和多端控件一致。阅读正文与 UI 字体解耦，允许在清晰、书卷感和手写感之间选择。

### Hierarchy

- **Display**（700，26px，1.25）：宽屏页面主标题或关键空状态，不用于按钮和标签。
- **Headline**（700，22px，1.3）：手机页面标题、对话框标题和一级信息组。
- **Title**（600，18px，1.4）：卡片标题、设置分组和详情模块。
- **Body**（400，15px，1.5）：普通 UI 文本；长说明限制在约 65–75 个字符宽度。
- **Reader Body**（400，基准 17px，1.8）：阅读正文，随用户字号和行高偏好缩放。
- **Label**（600，13px，1.3）：按钮、辅助信息和紧凑标签；不得使用全大写与夸张字距。

### Named Rules

**The Reading Type Is Independent Rule.** 修改 UI 字体不得改变阅读正文偏好；修改正文排版不得破坏导航、表单和管理界面的密度。

**The Quiet Hierarchy Rule.** 产品界面依靠 400/600/700 字重和有限字号形成层级，禁止使用展示字体或超大标题制造“营销页”效果。

## Elevation

轻阅采用“色调分层 + 局部背景模糊 + 必要环境阴影”的混合层级。玻璃表面由左上到右下的轻微渐变、细边界和背景模糊共同塑形；阴影只服务浮层和明显离开内容面的组件。普通按钮和高频控件应关闭阴影，以避免边框与大范围软阴影同时堆叠。

### Shadow Vocabulary

- **Subtle Glass**：基础透明度的 70%，阴影强度为平台值的 45%；用于分段控件和嵌入式轻表面。
- **Standard Glass**：平台基础透明度；用于普通卡片和内容分组。
- **Elevated Glass**：更高不透明度；用于操作按钮、Bottom Sheet 与对话框。
- **Floating Glass**：最高层级或独立的悬浮导航；允许环境阴影，但同一视区不得大面积重复。
- **Platform Blur**：手机 12、平板 17、Web 20、桌面 22 sigma；不得在长列表的每个单元格上独立启用。

### Named Rules

**The One Blur Boundary Rule.** 同一覆盖层只建立一个背景模糊边界；嵌套子组件使用透明色调层，不再重复 `BackdropFilter`。

**The Functional Glass Rule.** 如果移除模糊不影响层级和操作理解，该表面就不应该使用玻璃材质。

## Components

### Buttons

- **Shape:** 常规按钮使用 16px 圆角；工具栏和短标签按钮可使用完整药丸形。
- **Primary:** 实色主题强调色、白色文字，最小高度 48px；只用于页面唯一主操作。
- **Glass Action:** `GlassSurface` elevated 层级，强调色以约 12% 混入面板，边界使用约 28% 强调色；图标 19px，水平间距 9px，无投影。
- **State:** 禁用态透明度 52%；加载态保留按钮尺寸、显示 18px 进度指示并阻止点击；透明度过渡 160ms，减少动态效果时立即切换。
- **Touch Target:** 所有独立操作至少 44×44px，主操作高度 48px。

### Chips

- **Style:** 未选中态使用主题软背景、主题文字与细分割线；选中态使用强调色 18% 混色。
- **State:** 仅筛选、标签和紧凑状态使用 Chip；不能替代主要按钮。

### Cards / Containers

- **Corner Style:** 手机玻璃面 20px，宽屏 22px；图书封面固定 4px，避免把书籍塑造成 UI 卡片。
- **Background:** 使用当前主题 `panel` 生成的半透明渐变，不得固定为白色。
- **Shadow Strategy:** 默认按层级决定；列表中的重复卡片优先关闭模糊或阴影。
- **Border:** 深色主题用低透明白边，浅色主题使用正文色低透明边；边界负责分离而非装饰。
- **Internal Padding:** 默认 16px；紧凑控件 4–12px；页面边距手机 16px、宽屏 24px。

### Inputs / Fields

- **Style:** 主题面板色约 42%（浅色）或 50%（夜间）填充，14px 圆角，最小高度 48px。
- **Focus:** 焦点边界切换为 1.5px 主题强调色；不得依赖仅有颜色之外的低对比变化。
- **Error / Disabled:** 错误信息使用明确语义与破坏性红色；禁用态保留可读标签并禁止触发。

### Navigation

- **Phone:** 底部透明悬浮导航，为内容预留安全区加 92px 的底部空间。
- **Tablet / Desktop:** 左侧垂直悬浮导航；选中图标与标签使用主题强调色，未选中态使用次级文字色。
- **Web:** 沿用宽屏结构与独立玻璃参数；不得直接复制手机导航布局。
- **Motion:** 结构与显隐过渡通常为 180–280ms，表达状态变化，不播放装饰性入场序列。

### Glass Surface

`GlassSurface` 是材质唯一入口，统一管理表面等级、主题 tint、圆角、边界、模糊和阴影。业务页面不得自行拼装另一套“玻璃卡片”；特殊场景通过 `level`、`blur`、`shadow`、`tint` 和 `border` 参数表达。

- **轻量玻璃:** 默认模式，使用固定方向渐变、平台模糊参数和环境阴影，适用于全部既有玻璃组件。
- **液态玻璃模式:** 由用户在“我的”页面显式开启并持久化；全部 `GlassSurface`、`GlassCard` 及其派生的弹窗、Bottom Sheet、分段控件和操作按钮共同响应。它增加鼠标方向高光、渐变边缘与近距离阴影，不改变字体、尺寸、布局和交互语义。
- **局部回退:** 对性能敏感或必须保持稳定实色的特殊表面显式设置 `enableLiquidGlass: false`；正文、封面本体和非玻璃数据区域不接入材质切换。

### Dialogs and Bottom Sheets

- **Dialog:** 手机水平留白 18px、宽屏 40px；最大宽度 520px / 600px，圆角 26px / 28px。
- **Bottom Sheet:** 仅顶部使用对话框圆角，由 elevated 玻璃承载；手机端从底部出现，宽屏优先使用侧边面板。
- **Actions:** 使用可换行的尾部对齐操作区，间距 8px，避免窄屏按钮溢出。

## Do's and Don'ts

### Do:

- **Do** 让书籍封面、正文和阅读进度成为每个页面的第一视觉重心。
- **Do** 通过 `AppReaderPalette` 和 `GlassPlatformStyle` 获取主题与平台参数。
- **Do** 在手机、平板、Web、桌面之间改变导航和面板结构。
- **Do** 把动效控制在状态反馈所需的 150–250ms 左右，并尊重减少动态效果设置。
- **Do** 对高频列表关闭重复的背景模糊或阴影，优先保证滚动和翻页性能。
- **Do** 确保正文和普通文字达到 4.5:1，对大字号文字至少达到 3:1。

### Don't:

- **Don't** 在阅读正文背景上覆盖大面积玻璃、动态高光或实时折射。
- **Don't** 为每个内容块创建玻璃卡片；能用留白、排版和分割线表达层级时，禁止增加容器。
- **Don't** 嵌套多个 `BackdropFilter`，也不要在封面网格的每本书上独立启用模糊。
- **Don't** 同时使用明显边框和超过 16px 的装饰性软阴影塑造普通卡片。
- **Don't** 使用渐变文字、霓虹色、装饰性网格背景、重复条纹或营销式大指标。
- **Don't** 在不同页面发明不同形状的“保存”或“确认”按钮；相同操作必须共享组件语言。
- **Don't** 为追求风格重新发明标准表单、菜单、滚动条或模态交互。
- **Don't** 让强调色覆盖未选中、禁用或纯装饰状态。
