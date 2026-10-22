import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'chat_client.dart';

/// The media type of each file extension that the chat can send, by kind
/// (`docs/celaut/chat.md`, section 5.1).
const _mimeByExtension = {
  'image': {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
  },
  'audio': {
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
  },
};

/// The media type of the file called [name], or null if its extension is not one that the
/// chat sends.
String? attachmentMime(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  final extension = name.substring(dot + 1).toLowerCase();
  for (final kind in _mimeByExtension.values) {
    final mime = kind[extension];
    if (mime != null) return mime;
  }
  return null;
}

/// Let the user pick files of [kinds] (`image`, `audio`), as the service accepts them
/// ([ChatClient.accepts]). It returns the files that were read; a cancel gives an empty
/// list.
Future<List<OutgoingAttachment>> pickAttachments(Set<String> kinds) async {
  final extensions = [
    for (final kind in kinds) ...?_mimeByExtension[kind]?.keys,
  ];
  if (extensions.isEmpty) return const [];
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: extensions,
    allowMultiple: true,
    withData: true,
  );
  if (result == null) return const [];
  return [
    for (final file in result.files)
      if (file.bytes != null && attachmentMime(file.name) != null)
        OutgoingAttachment(
          mime: attachmentMime(file.name)!,
          bytes: Uint8List.fromList(file.bytes!),
          name: file.name,
        ),
  ];
}
