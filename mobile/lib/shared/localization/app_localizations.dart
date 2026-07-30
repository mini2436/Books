import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('zh', 'CN'), Locale('en')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('zh', 'CN'));
  }

  bool get isEnglish => locale.languageCode == 'en';

  String tr(String source) {
    if (!isEnglish || source.isEmpty) return source;
    return _english[source] ?? _translateDynamic(source) ?? source;
  }

  String? _translateDynamic(String source) {
    Match? match;

    match = RegExp(r'^(\d+) 本(?:书|藏书)?$').firstMatch(source);
    if (match != null) return '${match[1]} books';
    match = RegExp(r'^(\d+) 本离线书籍$').firstMatch(source);
    if (match != null) return '${match[1]} offline books';
    match = RegExp(r'^(\d+) (?:条|项)批注$').firstMatch(source);
    if (match != null) return '${match[1]} annotations';
    match = RegExp(r'^(.+) · (\d+) 条批注$').firstMatch(source);
    if (match != null) return '${match[1]} · ${match[2]} annotations';
    match = RegExp(
      r'^仅显示当前用户有批注的书籍。已选择 (\d+) 本，共 (\d+) 条批注。$',
    ).firstMatch(source);
    if (match != null) {
      return 'Only books annotated by the current user are shown. ${match[1]} books and ${match[2]} annotations selected.';
    }
    match = RegExp(r'^已导出 (\d+) 本书的 (\d+) 条批注$').firstMatch(source);
    if (match != null) {
      return 'Exported ${match[2]} annotations from ${match[1]} books';
    }
    match = RegExp(r'^(\d+) 项$').firstMatch(source);
    if (match != null) return '${match[1]} items';
    match = RegExp(r'^共 (\d+) 人$').firstMatch(source);
    if (match != null) return '${match[1]} people';
    match = RegExp(r'^(\d+) 人$').firstMatch(source);
    if (match != null) return '${match[1]} people';
    match = RegExp(r'^(\d+) 个分组$').firstMatch(source);
    if (match != null) return '${match[1]} groups';
    match = RegExp(r'^(\d+) 个扫描源$').firstMatch(source);
    if (match != null) return '${match[1]} scan sources';
    match = RegExp(r'^(\d+) 条近期记录$').firstMatch(source);
    if (match != null) return '${match[1]} recent records';
    match = RegExp(r'^已选择 (\d+) 个用户$').firstMatch(source);
    if (match != null) return '${match[1]} users selected';
    match = RegExp(r'^已选择 (\d+) 本书$').firstMatch(source);
    if (match != null) return '${match[1]} books selected';
    match = RegExp(r'^限定 (\d+) 本$').firstMatch(source);
    if (match != null) return 'Limit to ${match[1]} books';
    match = RegExp(r'^导入 (\d+) 本书$').firstMatch(source);
    if (match != null) return 'Import ${match[1]} books';
    match = RegExp(r'^已读 (\d+)%$').firstMatch(source);
    if (match != null) return '${match[1]}% read';
    match = RegExp(r'^阅读进度 ([\d.]+)%$').firstMatch(source);
    if (match != null) return '${match[1]}% read';
    match = RegExp(r'^第 (\d+) / (\d+) 章$').firstMatch(source);
    if (match != null) return 'Chapter ${match[1]} of ${match[2]}';
    match = RegExp(r'^第 (\d+) / (\d+) 页$').firstMatch(source);
    if (match != null) return 'Page ${match[1]} of ${match[2]}';
    match = RegExp(r'^第 (\d+) 页$').firstMatch(source);
    if (match != null) return 'Page ${match[1]}';
    match = RegExp(r'^找到 (\d+) 本书$').firstMatch(source);
    if (match != null) return '${match[1]} books found';
    match = RegExp(r'^当前显示 (\d+) 本$').firstMatch(source);
    if (match != null) return 'Showing ${match[1]} books';
    match = RegExp(r'^显示 (\d+) 条$').firstMatch(source);
    if (match != null) return 'Show ${match[1]}';
    match = RegExp(r'^用户 #(\d+) · (\d+) 本书$').firstMatch(source);
    if (match != null) return 'User #${match[1]} · ${match[2]} books';
    match = RegExp(r'^最近缓存 (.+)$').firstMatch(source);
    if (match != null) return 'Last cached ${match[1]}';
    match = RegExp(r'^(.+) · (\d+) 本可离线$').firstMatch(source);
    if (match != null) return '${match[1]} · ${match[2]} offline';
    match = RegExp(r'^已加入“(.+)”$').firstMatch(source);
    if (match != null) return 'Added to “${match[1]}”';
    match = RegExp(r'^已删除“(.+)”的离线文件$').firstMatch(source);
    if (match != null) return 'Removed the offline copy of “${match[1]}”';
    match = RegExp(r'^“(.+)”已可离线阅读$').firstMatch(source);
    if (match != null) return '“${match[1]}” is available offline';
    match = RegExp(r'^定位：(.+)$').firstMatch(source);
    if (match != null) return 'Location: ${match[1]}';
    match = RegExp(r'^分类 · (.+)$').firstMatch(source);
    if (match != null) return 'Group · ${match[1]}';
    match = RegExp(r'^(.+) · 暂停$').firstMatch(source);
    if (match != null) return '${tr(match[1]!)} · Paused';
    match = RegExp(r'^今天 (.+)$').firstMatch(source);
    if (match != null) return 'Today ${match[1]}';
    match = RegExp(r'^昨天 (.+)$').firstMatch(source);
    if (match != null) return 'Yesterday ${match[1]}';
    match = RegExp(r'^保存失败：(.+)$').firstMatch(source);
    if (match != null) return 'Could not save: ${match[1]}';
    match = RegExp(r'^密码修改失败：(.+)$').firstMatch(source);
    if (match != null) return 'Could not change password: ${match[1]}';
    match = RegExp(r'^分组更新失败：(.+)$').firstMatch(source);
    if (match != null) return 'Could not update group: ${match[1]}';
    match = RegExp(r'^批注加载失败：(.+)$').firstMatch(source);
    if (match != null) return 'Could not load annotations: ${match[1]}';
    match = RegExp(r'^批注导出失败：(.+)$').firstMatch(source);
    if (match != null) return 'Could not export annotations: ${match[1]}';
    match = RegExp(r'^PDF 加载失败：(.+)$').firstMatch(source);
    if (match != null) return 'Could not load PDF: ${match[1]}';
    match = RegExp(r'^分组已改为“(.+)”，更新 (\d+) 本书$').firstMatch(source);
    if (match != null) {
      return 'Group renamed to “${match[1]}”; ${match[2]} books updated';
    }
    match = RegExp(r'^分组重命名失败：(.+)$').firstMatch(source);
    if (match != null) return 'Could not rename group: ${match[1]}';
    match = RegExp(r'^删除“(.+)”的本地文件。在线书架中的书籍不会被删除。$').firstMatch(source);
    if (match != null) {
      return 'Remove the downloaded files for “${match[1]}”? The book will remain in your online library.';
    }
    match = RegExp(r'^已选择“(.+)”，发现 (\d+) 个支持的图书文件。$').firstMatch(source);
    if (match != null) {
      return 'Selected “${match[1]}”; ${match[2]} supported book files found.';
    }
    match = RegExp(r'^确定删除已勾选的 (\d+) 本图书吗？').firstMatch(source);
    if (match != null) {
      return 'Delete the ${match[1]} selected books? Access grants, annotations, bookmarks, and reading progress will also be removed.';
    }
    match = RegExp(r'^将删除“(.+)”的扫描配置和文件摘要。').firstMatch(source);
    if (match != null) {
      return 'Delete the scan configuration and file index for “${match[1]}”? Imported books will remain in the library.';
    }
    match = RegExp(r'^“(.+)”下载失败：(.+)$').firstMatch(source);
    if (match != null) return 'Could not download “${match[1]}”: ${match[2]}';
    match = RegExp(r'^《(.+)》已经加入书库。$').firstMatch(source);
    if (match != null) return '“${match[1]}” was added to the library.';
    match = RegExp(r'^(\d+)月(\d+)日 (.+)$').firstMatch(source);
    if (match != null) return '${match[1]}/${match[2]} ${match[3]}';
    match = RegExp(r'^(\d+)年(\d+)月(\d+)日 (.+)$').firstMatch(source);
    if (match != null) {
      return '${match[2]}/${match[3]}/${match[1]} ${match[4]}';
    }
    match = RegExp(r'^(\d+)/(\d+) 本$').firstMatch(source);
    if (match != null) return '${match[1]} of ${match[2]} books';
    match = RegExp(r'^(\d+) 本藏书 · (\d+) 本可离线 · (\d+) 项待同步$').firstMatch(source);
    if (match != null) {
      return '${match[1]} books · ${match[2]} offline · ${match[3]} pending';
    }
    match = RegExp(r'^(\d+) 本藏书 · (\d+) 本可离线 · 已同步$').firstMatch(source);
    if (match != null) {
      return '${match[1]} books · ${match[2]} offline · Synced';
    }
    match = RegExp(r'^(\d+) 本藏书 · 离线模式 · (\d+) 本可离线$').firstMatch(source);
    if (match != null) {
      return '${match[1]} books · Offline · ${match[2]} available';
    }
    match = RegExp(r'^(\d+) 本离线藏书 · (\d+) 项待同步$').firstMatch(source);
    if (match != null) return '${match[1]} offline books · ${match[2]} pending';
    match = RegExp(r'^(.+) 扫描完成，导入 (\d+) 本，标记缺失 (\d+) 本$').firstMatch(source);
    if (match != null) {
      return '${match[1]} scan complete: ${match[2]} imported, ${match[3]} missing';
    }
    match = RegExp(r'^(.+) 扫描完成，上传 (\d+) 本，(.+)$').firstMatch(source);
    if (match != null) {
      return '${match[1]} scan complete: ${match[2]} uploaded, ${tr(match[3]!)}';
    }
    match = RegExp(r'^(.+)，用户 (\d+)，(\d+) 本离线书籍$').firstMatch(source);
    if (match != null) {
      return '${match[1]}, user ${match[2]}, ${match[3]} offline books';
    }
    match = RegExp(r'^每 (\d+) 分钟自动扫描$').firstMatch(source);
    if (match != null) return 'Scan automatically every ${match[1]} minutes';
    match = RegExp(r'^批量删除 (\d+) 本$').firstMatch(source);
    if (match != null) return 'Delete ${match[1]} books';
    match = RegExp(r'^修改 (.+) 的密码$').firstMatch(source);
    if (match != null) return 'Change password for ${match[1]}';
    match = RegExp(r'^格式 v(\d+)$').firstMatch(source);
    if (match != null) return 'Format v${match[1]}';
    match = RegExp(r'^创建于 (.+)$').firstMatch(source);
    if (match != null) return 'Created ${match[1]}';
    match = RegExp(r'^(用户|书籍|批注|书签|历史|进度) (\d+)$').firstMatch(source);
    if (match != null) {
      const labels = {
        '用户': 'Users',
        '书籍': 'Books',
        '批注': 'Annotations',
        '书签': 'Bookmarks',
        '历史': 'History',
        '进度': 'Progress',
      };
      return '${labels[match[1]]} ${match[2]}';
    }
    match = RegExp(r'^(全量备份|书籍备份|用户数据备份) · 创建于 (.+)$').firstMatch(source);
    if (match != null) return '${tr(match[1]!)} · Created ${match[2]}';
    match = RegExp(r'^下次执行 (.+)$').firstMatch(source);
    if (match != null) return 'Next run ${match[1]}';
    match = RegExp(r'^上次完成 (.+)$').firstMatch(source);
    if (match != null) return 'Last completed ${match[1]}';
    match = RegExp(r'^共保留 (\d+) 份备份，可随时下载或清理。$').firstMatch(source);
    if (match != null) {
      return '${match[1]} backups retained. Download or clean them up at any time.';
    }
    match = RegExp(r'^(定期备份|手动导出) · (.+) · (.+)$').firstMatch(source);
    if (match != null) return '${tr(match[1]!)} · ${match[2]} · ${match[3]}';
    match = RegExp(r'^(.+)（备份文件中的用户）$').firstMatch(source);
    if (match != null) return '${match[1]} (user in backup file)';
    match = RegExp(r'^(.+)（现在系统中的用户）$').firstMatch(source);
    if (match != null) return '${match[1]} (user in current system)';
    match = RegExp(r'^正在恢复 (\d+)%$').firstMatch(source);
    if (match != null) return 'Restoring ${match[1]}%';
    match = RegExp(r'^正在上传备份文件 (\d+)%$').firstMatch(source);
    if (match != null) return 'Uploading backup ${match[1]}%';
    match = RegExp(r'^正在恢复数据库 (\d+)/(\d+)$').firstMatch(source);
    if (match != null) return 'Restoring database ${match[1]}/${match[2]}';
    match = RegExp(r'^正在恢复书籍文件 (\d+)/(\d+)$').firstMatch(source);
    if (match != null) return 'Restoring book files ${match[1]}/${match[2]}';
    match = RegExp(r'^已恢复书籍文件 (\d+)/(\d+)$').firstMatch(source);
    if (match != null) return 'Restored book files ${match[1]}/${match[2]}';
    match = RegExp(r'^总进度 (\d+)% · 已用时 (.+)$').firstMatch(source);
    if (match != null) return 'Overall ${match[1]}% · Elapsed ${match[2]}';
    match = RegExp(
      r'^只处理已映射用户和勾选的 (\d+) 类数据；替换模式不会影响其他类型。$',
    ).firstMatch(source);
    if (match != null) {
      return 'Only mapped users and the ${match[1]} selected data types are affected. Replace mode leaves every other type unchanged.';
    }
    match = RegExp(r'^将只替换已映射用户的“(.+)”。其他用户和未勾选的数据类型保持不变。$').firstMatch(source);
    if (match != null) {
      final types = match[1]!.split('、').map(tr).join(', ');
      return 'Replace only $types for mapped users. Other users and unselected data types remain unchanged.';
    }
    match = RegExp(r'^将把已选择的“(.+)”合并到目标用户；未勾选的数据类型保持不变。$').firstMatch(source);
    if (match != null) {
      final types = match[1]!.split('、').map(tr).join(', ');
      return 'Merge the selected $types into target users. Unselected data types remain unchanged.';
    }
    match = RegExp(r'^将从书签列表移除“(.+)”。$').firstMatch(source);
    if (match != null) return 'Remove “${match[1]}” from bookmarks.';
    match = RegExp(r'^扫描计划包含本地目录中不存在的文件：(.+)$').firstMatch(source);
    if (match != null) {
      return 'The scan plan contains a missing local file: ${match[1]}';
    }
    match = RegExp(r'^正在上传 (\d+)/(\d+) · (.+) · (\d+)%$').firstMatch(source);
    if (match != null) {
      return 'Uploading ${match[1]}/${match[2]} · ${match[3]} · ${match[4]}%';
    }
    match = RegExp(r'^正在解析 (\d+)/(\d+) · (.+)$').firstMatch(source);
    if (match != null) {
      return 'Processing ${match[1]}/${match[2]} · ${match[3]}';
    }
    match = RegExp(r'^跳过 (\d+) 本，标记缺失 (\d+) 本$').firstMatch(source);
    if (match != null) return '${match[1]} skipped, ${match[2]} marked missing';
    match = RegExp(r'^已创建用户 (.+)$').firstMatch(source);
    if (match != null) return 'Created user ${match[1]}';
    match = RegExp(r'^已导入《(.+)》$').firstMatch(source);
    if (match != null) return 'Imported “${match[1]}”';
    match = RegExp(r'^已更新 (.+) 的角色$').firstMatch(source);
    if (match != null) return 'Updated the role for ${match[1]}';
    match = RegExp(r'^已更新《(.+)》的书籍信息$').firstMatch(source);
    if (match != null) return 'Updated book information for “${match[1]}”';
    match = RegExp(r'^已更新扫描源 (.+)$').firstMatch(source);
    if (match != null) return 'Updated source ${match[1]}';
    match = RegExp(r'^已将书籍分配给 (.+)$').firstMatch(source);
    if (match != null) return 'Granted book access to ${match[1]}';
    match = RegExp(r'^已将图书分组更新为 (.+)$').firstMatch(source);
    if (match != null) return 'Book group updated to ${match[1]}';
    match = RegExp(r'^已启用 (.+)$').firstMatch(source);
    if (match != null) return 'Enabled ${match[1]}';
    match = RegExp(r'^已删除 (\d+) 本图书$').firstMatch(source);
    if (match != null) return 'Deleted ${match[1]} books';
    match = RegExp(r'^已删除同步任务 (.+)，已导入图书仍保留在书库中$').firstMatch(source);
    if (match != null) {
      return 'Deleted source ${match[1]}; imported books remain';
    }
    match = RegExp(r'^已识别 (\d+) 个支持的图书文件$').firstMatch(source);
    if (match != null) return '${match[1]} supported book files found';
    match = RegExp(r'^已停用 (.+)$').firstMatch(source);
    if (match != null) return 'Disabled ${match[1]}';
    match = RegExp(r'^已新增扫描源 (.+)$').firstMatch(source);
    if (match != null) return 'Added source ${match[1]}';
    match = RegExp(r'^已修改 (.+) 的密码$').firstMatch(source);
    if (match != null) return 'Changed password for ${match[1]}';
    match = RegExp(r'^已移除 (.+) 的图书访问权限$').firstMatch(source);
    if (match != null) return 'Removed book access for ${match[1]}';
    match = RegExp(r'^已重新生成《(.+)》的结构化正文$').firstMatch(source);
    if (match != null) return 'Rebuilt structured content for “${match[1]}”';
    match = RegExp(r'^正在比较 (\d+) 个本地文件摘要$').firstMatch(source);
    if (match != null) return 'Comparing ${match[1]} local file fingerprints';
    match = RegExp(r'^正在上传 (\d+)/(\d+) · (.+)$').firstMatch(source);
    if (match != null) return 'Uploading ${match[1]}/${match[2]} · ${match[3]}';
    match = RegExp(r'^正在上传 (.+)，上传后还需要解析，请勿关闭窗口$').firstMatch(source);
    if (match != null) {
      return 'Uploading ${match[1]}; processing follows. Keep this window open.';
    }
    match = RegExp(r'^正在上传图书 (\d+)%$').firstMatch(source);
    if (match != null) return 'Uploading book ${match[1]}%';
    match = RegExp(r'^PDF 临时文件准备失败：(.+)$').firstMatch(source);
    if (match != null) {
      return 'Could not prepare the temporary PDF: ${match[1]}';
    }
    match = RegExp(r'^此书尚未下载，连接服务器后请先在书架中下载到本地。\n(.+)$').firstMatch(source);
    if (match != null) {
      return 'This book has not been downloaded. Connect to the server and download it from the library first.\n${match[1]}';
    }
    match = RegExp(
      r'^书架加载失败。请连接服务器，或先在联网时下载书籍。\n当前服务：(.+)\n(.+)$',
    ).firstMatch(source);
    if (match != null) {
      return 'Could not load the library. Connect to the server, or download books before going offline.\nServer: ${match[1]}\n${match[2]}';
    }
    match = RegExp(r'^(.+) · (.+)$').firstMatch(source);
    if (match != null) {
      final left = tr(match[1]!);
      final right = tr(match[2]!);
      if (left != match[1] || right != match[2]) return '$left · $right';
    }

    return null;
  }

  static const _english = <String, String>{
    '轻阅': 'Private Reader',
    '回到你的私人书架': 'Return to your private library',
    '服务地址': 'Server address',
    '请输入服务地址': 'Enter the server address',
    '用户名': 'Username',
    '请输入用户名': 'Enter your username',
    '密码': 'Password',
    '请输入密码': 'Enter your password',
    '登录': 'Sign in',
    '离线使用': 'Use offline',
    '离线使用仅显示本机已缓存书籍；阅读进度保存在本机，重新登录原服务器和账户后同步。':
        'Offline mode shows books cached on this device. Reading progress stays here and syncs after you sign back in to the same server and account.',
    '选择离线书库': 'Choose an offline library',
    '请选择要进入的服务器和账户。离线产生的阅读进度只会同步回所选身份。':
        'Choose a server and account. Offline reading progress will sync only to that identity.',
    '取消': 'Cancel',
    '取消全选': 'Clear selection',
    '全选': 'Select all',
    '导出批注': 'Export annotations',
    '正在导出': 'Exporting',
    '选择保存位置': 'Choose save location',
    '保存批注 Markdown': 'Save annotation Markdown',
    '进入离线阅读': 'Open offline library',
    '时间未知': 'Unknown time',
    '书架': 'Library',
    '批注': 'Annotations',
    '后台': 'Admin',
    '我': 'Profile',
    '离线书籍': 'Offline books',
    '可读书籍': 'Available books',
    '本地暂存': 'Saved locally',
    '待同步': 'Pending sync',
    '阅读设置': 'Reading settings',
    '主题、字号、字体与行高': 'Theme, text size, font, and line spacing',
    '修改密码': 'Change password',
    '验证当前密码后更新登录密码': 'Verify your current password before changing it',
    '夜间模式': 'Dark mode',
    'APP 与阅读界面同步切换深色主题': 'Use the dark theme throughout the app and reader',
    '同步状态': 'Sync status',
    '离线操作将在网络恢复后自动补偿':
        'Offline changes sync automatically when the network returns',
    '返回登录': 'Back to sign in',
    '退出登录': 'Sign out',
    '未登录': 'Not signed in',
    '仅使用本机缓存 · 不连接服务器': 'On-device cache only · Server disconnected',
    '编辑个人名称': 'Edit display name',
    '个人名称': 'Display name',
    '留空将恢复显示登录账号': 'Leave blank to show the account username',
    '保存': 'Save',
    '个人名称已更新': 'Display name updated',
    '头像已更新': 'Profile picture updated',
    '无法读取所选图片，请重新选择':
        'The selected image could not be read. Choose another image.',
    '请输入当前密码，并设置新的登录密码。': 'Enter your current password and choose a new one.',
    '密码已修改': 'Password changed',
    '当前密码': 'Current password',
    '请输入当前密码': 'Enter your current password',
    '新密码': 'New password',
    '至少 6 位': 'At least 6 characters',
    '显示密码': 'Show password',
    '隐藏密码': 'Hide password',
    '确认新密码': 'Confirm new password',
    '确认修改': 'Confirm change',
    '两次输入的密码不一致': 'The passwords do not match',
    '密码至少 6 位': 'Password must be at least 6 characters',
    '语言': 'Language',
    '中文': '中文',
    '英文': 'English',
    '切换语言': 'Change language',
    '选择界面语言': 'Choose interface language',
    '当前界面语言': 'Current interface language',
    '搜索你的藏书': 'Search your library',
    '搜索藏书': 'Search library',
    '刷新书架': 'Refresh library',
    '搜索书名、作者或格式': 'Search by title, author, or format',
    '全部': 'All',
    '最近阅读': 'Recently read',
    '已读书籍': 'Finished',
    '未读书籍': 'Unread',
    '全部分组': 'All groups',
    '未分组': 'Ungrouped',
    '当前筛选下没有书籍': 'No books match these filters',
    '没有找到匹配的书': 'No matching books',
    '试试更换搜索词，或切换到其他分组查看。': 'Try another search or choose a different group.',
    '书架空空如也，先从后台导入一本书吧。':
        'Your library is empty. Import a book from Admin to get started.',
    '书架暂时没加载出来': 'The library could not be loaded',
    '重新加载': 'Reload',
    '重试': 'Try again',
    '开始阅读': 'Start reading',
    '关闭': 'Close',
    '书籍信息': 'Book information',
    '简介': 'Description',
    '暂无书籍简介': 'No description yet',
    '本书批注': 'Annotations in this book',
    '这本书还没有批注': 'This book has no annotations yet',
    '当前分组': 'Current group',
    '无分组': 'No group',
    '新增分组…': 'New group…',
    '输入新分组名称': 'Enter a new group name',
    '创建并加入': 'Create and add',
    '请输入分组名称': 'Enter a group name',
    '已设为无分组': 'Moved to Ungrouped',
    '删除离线下载？': 'Remove offline download?',
    '删除下载': 'Remove download',
    '离线下载失败': 'Offline download failed',
    '当前书籍格式暂不支持离线阅读': 'This book format is not available offline',
    '批注中心': 'Annotation center',
    '搜索批注内容、笔记或日期': 'Search annotations, notes, or dates',
    '没有找到匹配的批注。': 'No matching annotations.',
    '还没有批注，去阅读器里划一段喜欢的内容吧。':
        'No annotations yet. Select a passage in the reader to create one.',
    '未命名批注': 'Untitled annotation',
    '无摘录文本': 'No selected text',
    '打开原文': 'Open in reader',
    '删除这条批注？': 'Delete this annotation?',
    '删除后将同步移除这条批注和附带笔记。':
        'This annotation and its note will be removed from every synced device.',
    '删除': 'Delete',
    '阅读器': 'Reader',
    '无效的书籍参数': 'Invalid book information',
    'PDF 正在加载中': 'Loading PDF',
    '自动滚动暂不支持 PDF': 'Auto-scroll is not available for PDF',
    '已读完本书': 'You have finished this book',
    '批注内容': 'Note',
    '新增批注': 'New annotation',
    '写下批注': 'Write a note',
    '编辑批注': 'Edit annotation',
    '保存批注': 'Save annotation',
    '更新批注': 'Update annotation',
    '高亮': 'Highlight',
    '下划线': 'Underline',
    '波浪线': 'Wavy underline',
    '点线': 'Dotted underline',
    '无线条': 'No underline',
    '颜色': 'Color',
    '目录': 'Contents',
    '书签': 'Bookmarks',
    '添加当前位置书签': 'Bookmark current location',
    '当前位置已加书签': 'Current location is bookmarked',
    '自动滚动': 'Auto-scroll',
    '暂停自动滚动': 'Pause auto-scroll',
    '设置': 'Settings',
    '当前书签': 'Current bookmark',
    '历史书签': 'Bookmark history',
    '还没有书签，先为当前位置加一个吧。': 'No bookmarks yet. Add one for your current location.',
    '未命名书签': 'Untitled bookmark',
    '上一章': 'Previous chapter',
    '下一章': 'Next chapter',
    '上一页': 'Previous page',
    '下一页': 'Next page',
    '正在计算章节进度': 'Calculating chapter progress',
    '触摸正文即可暂停，滚动到章节末尾会继续下一章。':
        'Tap the text to pause. Auto-scroll continues into the next chapter.',
    '主题': 'Theme',
    '默认白': 'Light',
    '护眼': 'Comfort',
    '牛皮纸': 'Kraft',
    '夜间': 'Night',
    '字号': 'Text size',
    '行高': 'Line spacing',
    '字体': 'Font',
    '系统默认': 'System default',
    '清晰黑体': 'Clean sans',
    '阅读衬线': 'Reading serif',
    '自然阅读节奏': 'Natural reading rhythm',
    '紧凑': 'Compact',
    '标准': 'Standard',
    '宽松': 'Relaxed',
    '适合浏览': 'For browsing',
    '适合精读': 'For focused reading',
    '慢速': 'Slow',
    '正常': 'Normal',
    '快速': 'Fast',
    '平滑翻页': 'Smooth page turn',
    '后台管理': 'Administration',
    '用户管理': 'Users',
    '书籍管理': 'Books',
    '批注管理': 'Annotations',
    '书签管理': 'Bookmarks',
    '资源扫描': 'Library sources',
    '备份恢复': 'Backup & restore',
    '仅超级管理员可使用备份恢复': 'Only super admins can use backup and restore',
    '完整备份包含账号、书籍和阅读数据，馆员账号无法导出或覆盖系统数据。':
        'Full backups contain accounts, books, and reading data. Librarians cannot export or replace system data.',
    '系统备份与恢复': 'System backup & restore',
    '完整保存数据库、封面、正文缓存以及服务器当前可读取的书籍原文件。建议在升级或迁移前生成一份新备份。':
        'Save the database, covers, content cache, and every book file currently readable by the server. Create a fresh backup before upgrades or migrations.',
    '导出完整备份': 'Export full backup',
    '导出备份': 'Export backup',
    '导入与恢复': 'Import & restore',
    '全量': 'Full',
    '全量备份': 'Full backup',
    '书籍备份': 'Book backup',
    '用户数据备份': 'User-data backup',
    '用户数据': 'User data',
    '生成可完整迁移到另一套轻阅服务的 ZIP 文件。':
        'Create a ZIP that fully migrates to another Private Reader server.',
    '仅导出书籍、封面、正文缓存与原文件。':
        'Export only books, covers, content cache, and original files.',
    '按用户和数据类型导出阅读数据，恢复时再映射目标用户。':
        'Export reading data by user and type, then map target users during restore.',
    '批注、书签、阅读历史与进度': 'Annotations, bookmarks, reading history, and progress',
    '全部相关书籍': 'All related books',
    '选择用户（必选）': 'Choose users (required)',
    '不选择时导出全部书籍；相同文件会在恢复时自动去重。':
        'With no selection, all books are exported. Identical files are deduplicated on restore.',
    '书籍权限': 'Book access',
    '个人分组': 'Personal groups',
    '阅读历史': 'Reading history',
    '阅读进度': 'Reading progress',
    '导出全量备份': 'Export full backup',
    '导出书籍备份': 'Export book backup',
    '导出用户数据': 'Export user data',
    '生成可迁移到另一套轻阅服务的 ZIP 文件。':
        'Create a ZIP that can be migrated to another Private Reader server.',
    '账号、权限与系统配置': 'Accounts, permissions, and system settings',
    '书籍、封面与结构化正文': 'Books, covers, and structured content',
    '批注、书签与阅读进度': 'Annotations, bookmarks, and reading progress',
    '正在生成备份': 'Creating backup',
    '导出系统备份': 'Export system backup',
    '备份不会暂停阅读服务，但大书库导出期间会增加磁盘读取压力。':
        'Reading remains available, but exporting a large library increases disk activity.',
    '恢复系统备份': 'Restore system backup',
    '先校验备份类型和内容，再按范围恢复到当前系统。':
        'Validate the backup type and contents, then restore only its scope.',
    '先校验文件并查看摘要，确认后再覆盖当前系统。':
        'Validate the file and review its summary before replacing this system.',
    '移除文件': 'Remove file',
    '正在处理': 'Working',
    '开始全量恢复': 'Start full restore',
    '选择轻阅完整备份文件': 'Choose a full Private Reader backup',
    '选择轻阅备份文件': 'Choose a Private Reader backup',
    '仅支持由系统导出的 .zip 文件': 'Only system-exported .zip files are supported',
    '选择文件': 'Choose file',
    '备份校验通过': 'Backup validated',
    '目标用户映射': 'Target user mapping',
    '选择恢复范围': 'Choose restore scope',
    '全量备份包含完整数据，但不必全部覆盖；可以只导入书籍，或只恢复指定用户的阅读数据。':
        'A full backup contains everything, but you can import only books or restore reading data for selected users.',
    '完整系统': 'Full system',
    '仅书籍': 'Books only',
    '选择用户数据': 'Choose user data',
    '只恢复勾选的类型；选择“替换所选范围”时，也只会清理这些类型对应的数据。':
        'Restore only selected types. Replace selected scope also clears only those types.',
    '不恢复此用户': 'Skip this user',
    '源系统的 ID 不会直接使用。请逐个指定数据要恢复到当前系统的哪个用户。':
        'Source IDs are never reused. Choose the target account in this system for every source user.',
    '只为需要恢复的源用户选择目标用户；未选择的用户会保持跳过，源系统 ID 不会直接使用。':
        'Choose targets only for source users you want to restore. Unselected users are skipped and source IDs are never reused.',
    '选择当前系统用户': 'Choose a user in this system',
    '合并数据': 'Merge data',
    '替换所选范围': 'Replace selected scope',
    '导入书籍备份': 'Import book backup',
    '恢复用户数据': 'Restore user data',
    '全量恢复不可撤销。请先导出当前系统备份，并确认文件来源可信。':
        'A full restore cannot be undone. Export the current system and use only a trusted file.',
    '用户数据只会写入手动映射的目标用户；替换模式仅清理备份包含的范围。':
        'User data is written only to manually mapped accounts. Replace mode clears only the included scope.',
    '系统会先校验文件；相同原文件的书籍会自动去重。':
        'The file is validated first. Books with identical originals are deduplicated.',
    '确认导入书籍？': 'Import these books?',
    '确认恢复用户数据？': 'Restore this user data?',
    '确认导入': 'Confirm import',
    '确认恢复': 'Confirm restore',
    '请为备份中的每个用户选择当前系统的目标用户。':
        'Choose a target account in this system for every user in the backup.',
    '请至少选择一个源用户并指定当前系统的目标用户。':
        'Choose at least one source user and a target account in this system.',
    '请至少选择一种要恢复的用户数据。': 'Choose at least one user data type to restore.',
    '恢复不可撤销。请先导出当前系统备份，并确认所选文件来源可信。':
        'A restore cannot be undone. Export the current system first and only use a backup from a trusted source.',
    '正在校验备份内容…': 'Validating backup…',
    '确认覆盖当前系统？': 'Replace the current system?',
    '当前系统中的账号、书籍和阅读数据将被备份内容替换。完成后所有设备都需要重新登录。':
        'Accounts, books, and reading data in this system will be replaced by the backup. Every device must sign in again afterward.',
    '请输入“恢复系统”继续': 'Enter “恢复系统” to continue',
    '恢复系统': '恢复系统',
    '确认全量恢复': 'Confirm full restore',
    '备份已生成，但未能保存到所选位置。':
        'The backup was created but could not be saved to the selected location.',
    '正在整理数据库与书籍文件，备份较大时可能需要几分钟':
        'Collecting database and book files. Large backups may take several minutes.',
    '系统备份导出失败，请稍后重试。':
        'The system backup could not be exported. Try again shortly.',
    '正在校验备份文件': 'Validating backup file',
    '请选择完整系统备份文件，用户数据备份不能在此处全量恢复':
        'Choose a full system backup. A user-data backup cannot be restored here.',
    '无法读取备份文件，请确认文件完整且来源可信。':
        'The backup could not be read. Make sure it is complete and from a trusted source.',
    '正在恢复系统数据，请勿关闭应用或中断服务器':
        'Restoring system data. Do not close the app or interrupt the server.',
    '系统恢复失败，服务器已回滚本次数据变更。':
        'The restore failed and the server rolled back this change.',
    '备份上传完成，等待服务器开始校验': 'Upload complete. Waiting for server validation.',
    '正在准备恢复书籍文件': 'Preparing book files for restore',
    '正在恢复数据库': 'Restoring database',
    '正在完成数据校验': 'Finalizing data validation',
    '系统恢复成功': 'System restore completed',
    '系统恢复成功，即将返回登录页': 'System restore completed. Returning to sign in.',
    '恢复失败，系统数据已回滚': 'Restore failed. System data was rolled back.',
    '恢复仍在服务器执行，暂时无法读取详细进度':
        'The restore is still running, but detailed progress is temporarily unavailable.',
    '正在校验备份': 'Validating backup',
    '完整系统备份已保存': 'Full system backup saved',
    '书籍备份已保存': 'Book backup saved',
    '用户数据备份已保存': 'User-data backup saved',
    '备份下载已启动，请在浏览器或系统下载列表中查看进度':
        'Backup download started. Check your browser or system downloads for progress.',
    '定期备份': 'Scheduled backups',
    '按计划自动生成三种完整归档，并保留在服务器供随时下载。':
        'Automatically create all three archive types and retain them on the server for download.',
    '按周备份': 'Weekly',
    '按月备份': 'Monthly',
    '正在计算下次执行时间': 'Calculating the next run',
    '当前未启用': 'Not enabled',
    '全部用户数据': 'All user data',
    '启用后每 7 天执行一次；每次任务都会分别生成全量、书籍和用户数据备份。':
        'Runs every 7 days when enabled. Each run creates full, book, and user-data backups.',
    '启用后每月执行一次；每次任务都会分别生成全量、书籍和用户数据备份。':
        'Runs monthly when enabled. Each run creates full, book, and user-data backups.',
    '备份历史': 'Backup history',
    '手动导出和定期任务生成的备份会保留在这里。':
        'Manual exports and scheduled backups are retained here.',
    '暂无历史备份': 'No backup history',
    '完成一次手动导出，或启用定期备份后即可在此回溯。':
        'Complete a manual export or enable scheduled backups to build history.',
    '手动导出': 'Manual export',
    '下载备份': 'Download backup',
    '清理备份': 'Clean up backup',
    '保存历史备份': 'Save backup from history',
    '清理历史备份？': 'Clean up this backup?',
    '继续清理': 'Continue',
    '再次确认永久删除': 'Confirm permanent deletion',
    '保留备份': 'Keep backup',
    '永久删除': 'Delete permanently',
    '正在保存定期备份设置': 'Saving scheduled backup settings',
    '定期备份已启用': 'Scheduled backups enabled',
    '定期备份已停用': 'Scheduled backups disabled',
    '正在准备历史备份下载': 'Preparing backup download',
    '正在下载历史备份': 'Downloading backup',
    '历史备份已保存': 'Backup saved',
    '正在清理历史备份': 'Cleaning up backup',
    '历史备份已清理': 'Backup removed',
    '插件': 'Plugins',
    '添加用户': 'Add user',
    '新建后台用户': 'Create user',
    '初始密码': 'Initial password',
    '角色': 'Role',
    '创建': 'Create',
    '创建中...': 'Creating…',
    '启用用户': 'Enable user',
    '停用用户': 'Disable user',
    '当前启用': 'Enabled',
    '当前停用': 'Disabled',
    '超级管理员': 'Super admin',
    '馆员': 'Librarian',
    '读者': 'Reader',
    '可管理用户、角色与全部后台能力': 'Can manage users, roles, and all admin features',
    '可管理图书、批注与扫描任务': 'Can manage books, annotations, and scan jobs',
    '仅使用阅读与同步功能': 'Can read and sync only',
    '书籍查找': 'Find books',
    '查找书名、作者或分组': 'Search by title, author, or group',
    '导入图书': 'Import books',
    '导入完成': 'Import complete',
    '导入失败': 'Import failed',
    '上传中...': 'Uploading…',
    '保存中...': 'Saving…',
    '删除中...': 'Deleting…',
    '正在重建...': 'Rebuilding…',
    '书名': 'Title',
    '请输入书名': 'Enter a title',
    '作者（可选）': 'Author (optional)',
    '留空可清除作者': 'Leave blank to clear the author',
    '格式': 'Format',
    '来源': 'Source',
    '状态': 'Status',
    '更新时间': 'Updated',
    '结构化正文': 'Structured content',
    '已生成': 'Generated',
    '未生成': 'Not generated',
    '源文件缺失': 'Source file missing',
    '保存书籍信息': 'Save book information',
    '重建结构化正文': 'Rebuild structured content',
    '确认重建': 'Confirm rebuild',
    '扫描源': 'Library sources',
    '新增扫描源': 'Add source',
    '编辑扫描源': 'Edit source',
    '名称': 'Name',
    '资源类型': 'Source type',
    '本地上传目录': 'Local upload folder',
    'WebDAV 托管扫描': 'Managed WebDAV scan',
    'WebDAV 地址': 'WebDAV address',
    '远程目录': 'Remote folder',
    '扫描周期（分钟）': 'Scan interval (minutes)',
    '启用定时扫描': 'Enable scheduled scans',
    '仅手动扫描': 'Manual scans only',
    '开始扫描': 'Start scan',
    '立即扫描': 'Scan now',
    '确认手动扫描': 'Confirm manual scan',
    '选择目录并扫描': 'Choose folder and scan',
    '所选目录': 'Selected folder',
    '尚未选择目录': 'No folder selected',
    '删除任务': 'Delete source',
    '删除同步任务？': 'Delete this sync source?',
    '暂无导入记录': 'No import history',
    '最近导入记录': 'Recent imports',
    '上次扫描': 'Last scan',
    '尚未扫描': 'Not scanned yet',
    '请求失败': 'Request failed',
    '网络请求失败': 'Network request failed',
    '服务器未返回有效数据': 'The server returned invalid data',
    '登录状态已失效': 'Your session is no longer valid',
    '登录状态已过期，请重新登录。': 'Your session expired. Sign in again.',
    '当前设备还没有离线缓存，请先登录并下载书籍。':
        'This device has no offline books yet. Sign in and download a book first.',
    '无法读取本地离线书库，请稍后重试。':
        'The offline library could not be read. Try again shortly.',
    '当前账号没有后台权限。': 'This account does not have admin access.',
    '离线使用模式不可添加': 'This action is unavailable in offline mode',
    'Web 端暂不支持离线书库': 'Offline libraries are not yet available on the web',
    '当前平台不支持选择本地目录': 'Folder selection is not supported on this platform',
    '当前平台无法读取本地目录文件': 'This platform cannot read files from a local folder',
    '图片加载中': 'Loading image',
    '图片无法加载': 'Image could not be loaded',
    '关闭图片预览': 'Close image preview',
    '复制': 'Copy',
    '跳转': 'Go to location',
    '完成': 'Done',
    '简体中文': '简体中文',
    '输入书名、作者、简介或分组': 'Search by title, author, description, or group',
    '搜索书名、作者、分组或格式': 'Search by title, author, group, or format',
    '搜索用户、摘录、笔记或日期': 'Search users, excerpts, notes, or dates',
    '清空': 'Clear',
    '书籍批注': 'Book annotations',
    '书籍分组': 'Book groups',
    '图书分组': 'Book group',
    '分组名称': 'Group name',
    '修改分组名称': 'Rename group',
    '分组': 'Group',
    '例如：经典文学 / 待整理 / 管理样书':
        'For example: Classics / To organize / Admin samples',
    '没有找到匹配的书籍批注。': 'No matching book annotations.',
    '还没有书签': 'No bookmarks yet',
    '删除这条书签？': 'Delete this bookmark?',
    '管理后台账号、启用状态与当前角色。': 'Manage admin accounts, access status, and roles.',
    '当前可见用户': 'Visible users',
    '当前还没有可见人员。': 'No users are visible yet.',
    '可绑定用户': 'Users available to add',
    '没有尚未绑定的启用用户。': 'There are no enabled users left to add.',
    '绑定': 'Add access',
    '解绑': 'Remove access',
    '绑定解绑用户': 'Manage book access',
    '相关信息': 'Details',
    '最后阅读': 'Last read',
    '编辑': 'Edit',
    '定位': 'Locate',
    '点击即可定位到原文': 'Open the original passage',
    '收起': 'Collapse',
    '内容维护': 'Content maintenance',
    '重新读取源文件并生成目录与统一正文。适用于目录错乱、解析失败或解析器升级后的书籍。':
        'Read the source file again and rebuild its table of contents and structured text. Use this after parsing errors or parser upgrades.',
    '系统会重新读取源文件，生成新的目录与结构化正文版本。原始书籍文件不会被修改。是否继续？':
        'The source file will be read again to create a new table of contents and structured-text version. The original file will not be changed. Continue?',
    '源文件缺失，无法重建。请先恢复原始书籍文件。':
        'The source file is missing. Restore it before rebuilding.',
    '资源扫描入库': 'Library ingestion',
    '本地目录由当前设备手动选择并按需上传；只有 WebDAV 支持服务端定时扫描。':
        'Local folders are selected and uploaded manually from this device. Only WebDAV supports scheduled server-side scans.',
    '仅 WebDAV 会由服务端按周期自动访问':
        'Only WebDAV can be scanned automatically by the server',
    '请通过“选择目录”按钮指定上传目录': 'Use Choose folder to select an upload folder',
    '离线使用中：可阅读、搜索并暂存批注，登录原账户后同步。':
        'Offline mode: read, search, and save annotations locally. Sign in to the original account to sync.',
    '批量删除图书': 'Delete selected books',
    '确认删除': 'Confirm deletion',
    '暂时还没有批注': 'No annotations yet',
    '这本书当前没有可查看的批注了。': 'This book has no visible annotations.',
    '这本书暂时还没有批注。': 'This book has no annotations yet.',
    '仅显示当前仍包含书籍的分组': 'Only groups that still contain books are shown',
    '用于确认扫描任务是否实际入库，以及最近处理了哪本书。':
        'Use this history to verify imports and see which book was processed most recently.',
    '无法读取所选文件，请重新选择':
        'The selected file could not be read. Choose another file.',
    '登录同步': 'Sign in to sync',
    '“未分组”是系统保留名称': '“Ungrouped” is reserved by the system',
    '保存服务地址失败': 'Could not save the server address',
    '本机没有可阅读的离线书籍。\n返回登录后，可将书籍下载到本地再离线使用。':
        'There are no offline books on this device.\nSign in to download books for offline reading.',
    '本软件内置使用 Adobe 思源宋体，依据 SIL Open Font License 1.1 使用。':
        'The bundled Adobe Source Han Serif font is used under the SIL Open Font License 1.1.',
    '本软件内置使用霞鹜文楷，依据 SIL Open Font License 1.1 使用。':
        'The bundled LXGW WenKai font is used under the SIL Open Font License 1.1.',
    '本软件内置使用小米 MiSans 字体，依据 MiSans 字体知识产权许可协议使用。':
        'The bundled MiSans font is used under the MiSans intellectual property license.',
    '必须保留至少一个启用的管理员': 'At least one administrator must remain enabled',
    '不会自动扫描。以后每次刷新都需要由当前设备重新选择目录，兼容浏览器、桌面和移动端权限。':
        'This source is not scanned automatically. Select the folder again from this device each time to respect browser, desktop, and mobile permissions.',
    '当前角色可以继续管理图书、批注与扫描任务，但不能新增或停用用户。':
        'This role can manage books, annotations, and scans, but cannot add or disable users.',
    '当前离线，删除操作已加入待同步队列': 'Offline: deletion queued for sync',
    '当前位置还在加载中': 'The current location is still loading',
    '当前位置已加入书签': 'Current location bookmarked',
    '当前移动端仅支持 TXT / EPUB 的统一正文阅读。':
        'The mobile reader currently supports structured text for TXT and EPUB only.',
    '当前账号 · 角色已锁定': 'Current account · Role locked',
    '当前状态': 'Current status',
    '导入成功，正在刷新管理后台中的书籍列表。': 'Import succeeded. Refreshing the book list.',
    '地址': 'Address',
    '第一次扫描完成后，这里会显示最近的入库结果。':
        'Recent import results will appear here after the first scan.',
    '点击编辑这条批注': 'Edit this annotation',
    '点击调用系统目录选择器，不能手动输入路径':
        'Use the system folder picker; the path cannot be entered manually',
    '方式': 'Method',
    '服务端会先比较摘要，只上传新增或发生变化的文件。':
        'The server compares file fingerprints and uploads only new or changed files.',
    '服务器解析图书超时，请稍后检查导入结果':
        'Book parsing timed out. Check the import result shortly.',
    '服务器正在解析图书': 'The server is processing the book',
    '该书尚未生成统一正文，请在桌面端继续阅读。':
        'Structured text is not available for this book. Continue reading on desktop.',
    '高亮片段': 'Highlighted passage',
    '关闭分组': 'Close group',
    '关闭书籍详情': 'Close book details',
    '管理员只能停用自己的账号': 'Administrators can disable only their own account',
    '还没有可管理的书籍': 'There are no books to manage yet',
    '还没有批注记录': 'No annotation records yet',
    '还没有扫描源': 'No library sources yet',
    '还没有书签记录': 'No bookmark records yet',
    '恢复': 'Restore',
    '角色编排会影响后台权限范围，因此当前账号无法修改。':
        'Role assignments affect admin access, so this account cannot change them.',
    '角色管理': 'Role management',
    '角色可见': 'Role visibility',
    '仅超级管理员可调整角色': 'Only super admins can change roles',
    '仅超级管理员可管理用户': 'Only super admins can manage users',
    '可用': 'Available',
    '客户端手动上传目录': 'Client-side folder upload',
    '离': 'OFF',
    '离线 PDF 文件不完整': 'The offline PDF is incomplete',
    '离线章节数据不完整': 'Offline chapter data is incomplete',
    '浏览器目录授权已失效，请重新选择目录': 'Folder access has expired. Select the folder again.',
    '没有可用的本地用户': 'No local users are available',
    '没有找到匹配书籍': 'No matching books',
    '没有找到匹配图书': 'No matching books',
    '每次由当前设备重新选择目录并手动扫描':
        'Select the folder again on this device for every manual scan',
    '内容模型': 'Content model',
    '匿名访问': 'Anonymous access',
    '批注总数': 'Total annotations',
    '请输入 WebDAV 地址': 'Enter a WebDAV address',
    '请输入大于 0 的分钟数': 'Enter a number of minutes greater than zero',
    '请输入名称': 'Enter a name',
    '全部书籍': 'All books',
    '全选当前结果': 'Select all results',
    '权限': 'Access',
    '删除后将从历史书签中移除这条记录。': 'This entry will be removed from bookmark history.',
    '删除后将同步移除这条高亮批注。':
        'This highlight will be removed from every synced device.',
    '上传完成，服务器正在解析图书': 'Upload complete. The server is processing the book.',
    '上传已完成，正在提取书名、封面和正文内容。':
        'Upload complete. Extracting the title, cover, and book content.',
    '设置新的登录密码。超级管理员账号不能在这里修改。':
        'Set a new sign-in password. Super admin passwords cannot be changed here.',
    '涉及书籍': 'Books',
    '使用已有名称会将两个分组合并': 'Using an existing name will merge the groups',
    '试试换个书名、作者或分组关键词。': 'Try another title, author, or group.',
    '试试其他关键词或分组名。': 'Try another keyword or group name.',
    '书': 'Book',
    '书籍': 'Books',
    '书籍未下载': 'Book not downloaded',
    '书名不能为空': 'Title cannot be empty',
    '输入书名、作者或简介关键词。': 'Search by title, author, or description.',
    '刷新后台后，这里会显示可管理的账号列表。':
        'Refresh Admin to load the accounts you can manage.',
    '思源宋体': 'Source Han Serif',
    '所选目录当前不可访问，请重新选择': 'The selected folder is unavailable. Select it again.',
    '所选图书': 'Selected books',
    '添加本地上传目录或 WebDAV。普通目录需要手动选择后刷新，避免多端文件权限失效。':
        'Add a local upload folder or WebDAV. Local folders must be selected manually to respect device permissions.',
    '停用自己的管理员账号': 'Disable your own administrator account',
    '图书详情': 'Book details',
    '图书已导入，正在更新书库': 'Book imported. Updating the library.',
    '图书已经加入书库。': 'The book was added to the library.',
    '图书总数': 'Total books',
    '未关联书籍': 'No linked book',
    '未命名扫描源': 'Untitled source',
    '未命名书籍': 'Untitled book',
    '未命名章节': 'Untitled chapter',
    '未能读取所选文件': 'The selected file could not be read',
    '未知扫描源': 'Unknown source',
    '未知用户': 'Unknown user',
    '未知作者': 'Unknown author',
    '文件超过服务器上传限制，请联系管理员调整上传配置':
        'The file exceeds the server upload limit. Ask an administrator to update the upload settings.',
    '文件上传超时，请确认服务器仍在运行后重试':
        'The upload timed out. Confirm the server is running and try again.',
    '无法确定离线操作所属的服务器和用户':
        'The server and user for this offline change could not be identified',
    '系统中至少需要保留一个启用的管理员账号':
        'At least one administrator account must remain enabled',
    '霞鹜文楷': 'LXGW WenKai',
    '先导入一本图书，这里会自动切到封面管理视图。':
        'Import a book first. This area will then switch to the cover management view.',
    '显示中': 'Visible',
    '新密码不能超过 128 位': 'New password cannot exceed 128 characters',
    '新密码至少 6 位': 'New password must be at least 6 characters',
    '选择需要手动扫描的图书目录': 'Choose a book folder to scan manually',
    '选择颜色 ': 'Choose color ',
    '已勾选': 'Selected',
    '已恢复一条批注': 'Annotation restored',
    '已恢复一条书签': 'Bookmark restored',
    '已清空图书分组': 'Book group cleared',
    '已隐藏': 'Hidden',
    '已隐藏一条批注': 'Annotation hidden',
    '已隐藏一条书签': 'Bookmark hidden',
    '隐藏': 'Hide',
    '用户产生高亮与批注后，这里会出现按书聚合的后台列表。':
        'Annotations and highlights will appear here grouped by book.',
    '用户创建书签后，这里会显示全局列表与当前状态。':
        'Bookmarks will appear here with their current status.',
    '暂无用户数据': 'No user data',
    '账号': 'Account',
    '正在更新书库': 'Updating library',
    '正在上传': 'Uploading',
    '正在上传并解析图书，请勿关闭窗口':
        'Uploading and processing the book. Keep this window open.',
    '正在向服务器传输文件。': 'Sending the file to the server.',
    '直线': 'Straight line',
    '最近一条批注': 'Latest annotation',
    'PDF 暂时仍通过桌面 Web 浏览器阅读。':
        'PDF reading is currently available through a desktop web browser.',
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'zh' || locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String tr(String source) => l10n.tr(source);
}
