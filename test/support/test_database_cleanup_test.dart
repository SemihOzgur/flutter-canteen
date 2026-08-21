library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  test(
    'deleteDirectoryWithRetry geçici Windows lock hatasında yeniden dener',
    () {
      var attempts = 0;

      deleteDirectoryWithRetry(
        Directory.systemTemp,
        maxAttempts: 3,
        retryDelay: Duration.zero,
        windowsFileLockRetryEnabled: true,
        deleteAction: () {
          attempts += 1;
          if (attempts < 3) {
            throw PathAccessException(
              'C:\\temp\\canteen_db_test',
              OSError('The process cannot access the file', 32),
              'Deletion failed',
            );
          }
        },
      );

      expect(attempts, 3);
    },
  );
}
