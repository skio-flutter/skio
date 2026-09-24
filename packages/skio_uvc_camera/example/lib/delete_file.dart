// Deletes a captured file. On the web captures live in memory, so there is
// nothing on disk to remove.
export 'delete_file_web.dart' if (dart.library.io) 'delete_file_io.dart';
