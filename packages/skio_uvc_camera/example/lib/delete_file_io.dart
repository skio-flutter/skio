import 'dart:io';

/// Deletes the file at [path] if it exists.
Future<void> deleteCapturedFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
