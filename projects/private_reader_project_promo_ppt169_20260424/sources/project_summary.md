# Private Reader 项目宣传素材汇总

## 项目定位

Private Reader 是一套可自托管的多用户电子书平台，当前以 `backend/ + mobile/` 为持续演进的主线基线，兼顾私有化部署、离线同步、可扩展图书格式处理与 Flutter 多端收敛能力。

## 核心卖点

- 自托管：适合团队、机构、企业搭建私有阅读与知识分发平台
- 多用户：区分普通用户、管理员、超级管理员
- 阅读闭环：登录、书架、图书详情、阅读器、目录、章节切换、书签、批注、阅读设置、阅读进度
- 离线优先：支持批注、书签、阅读进度同步基础能力
- 后台管理：支持用户、角色、书籍、批注、资源扫描管理
- 扫描入库：支持 WebDAV 扫描源维护、扫描任务发起与图书入库
- 技术可扩展：后端采用编译期集成插件，当前已覆盖 `TXT / EPUB / PDF`
- 多端路线：Flutter App 为统一前端基础，后续向 Web/Desktop 收敛

## 当前完成度

- 已形成“后端能力 + Flutter App 可用闭环 + 移动端管理后台”的稳定迭代基础
- 手机与平板采用统一 Flutter 代码基线，并已做平板适配
- Web、桌面与移动端的前端工作统一在 Flutter 工程中持续优化

## 可用于 PPT 的真实素材

- `bookshelf-prototype.png`
- `login-prototype.png`
- `prototype-nav.png`
- `reader-kraft-prototype.png`
- `reader-light-prototype.png`
- `reader-night-prototype.png`
- `private-reader-app-icon-preview-rounded.png`

## 事实型数字

- 3 类已集成格式插件：`plugin-epub / plugin-pdf / plugin-txt`
- 3 类系统角色：普通用户 / 管理员 / 超级管理员
- 5 个后台核心分区：用户 / 角色 / 书籍 / 批注 / 资源扫描
- 4 条核心主链路：登录与会话恢复 / 书架到阅读器闭环 / 同步能力 / 管理与扫描

## 主要来源

- `README.md`
- `docs/功能总览.md`
- `docs/详细功能文档.md`
- `docs/后端架构文档.md`
- `docs/Flutter应用架构文档.md`
- `docs/Flutter多端持续优化路线.md`
