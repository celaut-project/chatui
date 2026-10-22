import 'package:file_picker/file_picker.dart';

import 'chat_client.dart';

/// The media types that every service must accept (`docs/celaut/chat.md`, section 5.1),
/// by kind and file extension. The picker offers only these: any other type would be sent
/// in full and then refused.
const _mimeByExtension = {
  'image': {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
  },
  'audio': {
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
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

/// The files that the user picked and the chat keeps, and how many it left out, by reason.
class PickedAttachments {
  const PickedAttachments(
    this.files, {
    this.duplicates = 0,
    this.invalid = 0,
    this.tooMany = 0,
  });

  final List<OutgoingAttachment> files;

  /// Files that are already in the message (same name and size).
  final int duplicates;

  /// Files that are empty, above [ChatClient.maxAttachmentBytes], or could not be read.
  final int invalid;

  /// Files over the limit of [ChatClient.maxAttachments] for one message.
  final int tooMany;

  int get skipped => duplicates + invalid + tooMany;
}

/// Choose, from the [picked] files, the ones that fit in a message that already has
/// [existing] files. [unreadable] files are counted as invalid.
PickedAttachments selectAttachments(
  List<OutgoingAttachment> picked,
  List<OutgoingAttachment> existing, {
  int unreadable = 0,
}) {
  final files = <OutgoingAttachment>[];
  var duplicates = 0;
  var invalid = unreadable;
  var tooMany = 0;
  bool same(OutgoingAttachment a, OutgoingAttachment b) =>
      a.name == b.name && a.bytes.length == b.bytes.length;
  for (final file in picked) {
    if (file.bytes.isEmpty || file.bytes.length > ChatClient.maxAttachmentBytes) {
      invalid++;
    } else if (existing.any((e) => same(e, file)) || files.any((f) => same(f, file))) {
      duplicates++;
    } else if (existing.length + files.length >= ChatClient.maxAttachments) {
      tooMany++;
    } else {
      files.add(file);
    }
  }
  return PickedAttachments(files, duplicates: duplicates, invalid: invalid, tooMany: tooMany);
}

/// Let the user pick files of [kinds] (`image`, `audio`), as the service accepts them
/// ([ChatClient.accepts]), for a message that has [existing] files. A cancel gives an
/// empty result.
Future<PickedAttachments> pickAttachments(
  Set<String> kinds,
  List<OutgoingAttachment> existing,
) async {
  final extensions = [
    for (final kind in kinds) ...?_mimeByExtension[kind]?.keys,
  ];
  if (extensions.isEmpty) return const PickedAttachments([]);
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: extensions,
    allowMultiple: true,
    withData: true,
  );
  if (result == null) return const PickedAttachments([]);
  final picked = [
    for (final file in result.files)
      if (file.bytes != null && attachmentMime(file.name) != null)
        OutgoingAttachment(mime: attachmentMime(file.name)!, bytes: file.bytes!, name: file.name),
  ];
  final unreadable = result.files.length - picked.length;
  try {
    // The picker copies each file to the cache of the app: the bytes are in memory now.
    await FilePicker.platform.clearTemporaryFiles();
  } on Object {
    // The copies stay until the system cleans the cache.
  }
  return selectAttachments(picked, existing, unreadable: unreadable);
}
