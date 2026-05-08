enum UserRole {
  superAdmin('SUPER_ADMIN', '超级管理员', '可管理用户、角色与全部后台能力'),
  librarian('LIBRARIAN', '馆员', '可管理图书、批注与扫描任务'),
  reader('READER', '读者', '仅使用阅读与同步功能');

  const UserRole(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;

  bool get canAccessAdmin => this == superAdmin || this == librarian;

  bool get canManageAdminUsers => this == superAdmin;

  static UserRole fromValue(String? value) {
    final normalized = value?.trim().toUpperCase();
    for (final role in values) {
      if (role.value == normalized) {
        return role;
      }
    }
    return reader;
  }
}
