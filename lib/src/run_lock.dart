import 'dart:io';

/// Takes an exclusive lock on [path], or returns null when another process
/// holds it. The OS drops the lock when the process dies, so it never goes
/// stale.
RandomAccessFile? tryRunLock(String path) {
  final RandomAccessFile file = File(path).openSync(mode: FileMode.append);
  try {
    file.lockSync();
    return file;
  } on FileSystemException {
    file.closeSync();
    return null;
  }
}
