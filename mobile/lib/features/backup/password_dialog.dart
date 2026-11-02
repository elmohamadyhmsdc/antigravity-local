import 'package:flutter/material.dart';

import '../../ui/sheets/password_sheet.dart';

export '../../ui/sheets/password_sheet.dart';

Future<String?> backupPassword(
  BuildContext context, {
  required bool creating,
}) => PasswordSheet.show(context, creating: creating);
