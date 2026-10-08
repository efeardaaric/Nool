/// Recognize only public video object URLs belonging to this Supabase project.
class StorageMediaReference {
  const StorageMediaReference(this.bucket, this.path);
  final String bucket;
  final String path;

  static StorageMediaReference? parse(String raw,
      {required String projectUrl}) {
    final uri = Uri.tryParse(raw);
    final project = Uri.tryParse(projectUrl);
    if (uri == null ||
        project == null ||
        uri.scheme != project.scheme ||
        uri.host != project.host ||
        uri.port != project.port) {
      return null;
    }
    final parts = uri.pathSegments;
    if (parts.length < 6 ||
        parts.take(4).join('/') != 'storage/v1/object/public') {
      return null;
    }
    final bucket = parts[4];
    if (!const {'campus-drops', 'videos', 'group-drops'}.contains(bucket)) {
      return null;
    }
    final path = parts.skip(5).toList();
    if (path.any((part) =>
        part.isEmpty || part == '.' || part == '..' || part.contains('/'))) {
      return null;
    }
    return StorageMediaReference(bucket, path.join('/'));
  }
}
