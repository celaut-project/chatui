import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A group of conversations: an id that does not change and the name that the user gave.
@immutable
class ChatGroup {
  const ChatGroup(this.id, this.name);

  final String id;
  final String name;
}

/// The groups of conversations of the chat list: which groups there are, which group
/// each conversation (instance) is in, which groups are collapsed, and whether the list
/// shows the groups or one flat list. Only this phone knows them: the node gets nothing.
///
/// A conversation is in one group at most. Stored as one JSON text in
/// SharedPreferences, like the other display preferences ([ChatPrefs]). A failed read or
/// write keeps the value in memory only.
class ChatGroups extends ChangeNotifier {
  static const _key = 'chat_groups_v1';

  /// The longest name of a group.
  static const maxNameChars = 40;

  final List<ChatGroup> _groups = [];
  final Map<String, String> _of = {};
  final Set<String> _collapsed = {};
  bool _grouped = false;

  /// The list shows the groups, collapsible. Off (the default): one flat list.
  bool get grouped => _grouped;

  /// The groups, in the order that the user made them.
  List<ChatGroup> get groups => List.unmodifiable(_groups);

  ChatGroup? group(String id) {
    for (final g in _groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// The group of the conversation, or null if it is in none.
  ChatGroup? groupOf(String instanceId) {
    final id = _of[instanceId];
    return id == null ? null : group(id);
  }

  bool isCollapsed(String groupId) => _collapsed.contains(groupId);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final text = p.getString(_key);
      if (text != null) _decode(text);
    } catch (_) {
      // Keep what is in memory.
    }
    notifyListeners();
  }

  void _decode(String text) {
    final data = jsonDecode(text);
    if (data is! Map) return;
    _groups.clear();
    _of.clear();
    _collapsed.clear();
    _grouped = data['grouped'] == true;
    final groups = data['groups'];
    if (groups is List) {
      for (final g in groups) {
        if (g is! Map) continue;
        final id = g['id'], name = g['name'];
        if (id is String && name is String && group(id) == null) _groups.add(ChatGroup(id, name));
      }
    }
    final of = data['of'];
    if (of is Map) {
      for (final e in of.entries) {
        final k = e.key, v = e.value;
        if (k is String && v is String && group(v) != null) _of[k] = v;
      }
    }
    final collapsed = data['collapsed'];
    if (collapsed is List) {
      for (final c in collapsed) {
        if (c is String && group(c) != null) _collapsed.add(c);
      }
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key,
        jsonEncode({
          'grouped': _grouped,
          'groups': [
            for (final g in _groups) {'id': g.id, 'name': g.name},
          ],
          'of': _of,
          'collapsed': _collapsed.toList(),
        }),
      );
    } catch (_) {
      // Memory-only for this run.
    }
  }

  Future<void> _changed() async {
    notifyListeners();
    await _save();
  }

  /// A name as the user typed it: one line, trimmed, not too long.
  static String cleanName(String name) {
    final one = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= maxNameChars ? one : one.substring(0, maxNameChars).trimRight();
  }

  Future<void> setGrouped(bool v) async {
    if (_grouped == v) return;
    _grouped = v;
    await _changed();
  }

  /// Make a group named [name], after the others. Null for a blank name.
  Future<ChatGroup?> create(String name) async {
    final clean = cleanName(name);
    if (clean.isEmpty) return null;
    var n = DateTime.now().microsecondsSinceEpoch;
    while (group('g$n') != null) {
      n++;
    }
    final g = ChatGroup('g$n', clean);
    _groups.add(g);
    await _changed();
    return g;
  }

  /// Give the group a new name. A blank name changes nothing.
  Future<void> rename(String groupId, String name) async {
    final clean = cleanName(name);
    final at = _groups.indexWhere((g) => g.id == groupId);
    if (clean.isEmpty || at < 0 || _groups[at].name == clean) return;
    _groups[at] = ChatGroup(groupId, clean);
    await _changed();
  }

  /// Delete the group. Its conversations stay: they are in no group.
  Future<void> delete(String groupId) async {
    final at = _groups.indexWhere((g) => g.id == groupId);
    if (at < 0) return;
    _groups.removeAt(at);
    _of.removeWhere((_, g) => g == groupId);
    _collapsed.remove(groupId);
    await _changed();
  }

  /// Put the conversation in the group [groupId], or in none (null).
  Future<void> move(String instanceId, String? groupId) async {
    if (groupId != null && group(groupId) == null) return;
    if (_of[instanceId] == groupId) return;
    if (groupId == null) {
      _of.remove(instanceId);
    } else {
      _of[instanceId] = groupId;
    }
    await _changed();
  }

  Future<void> setCollapsed(String groupId, bool collapsed) async {
    if (group(groupId) == null) return;
    if (!(collapsed ? _collapsed.add(groupId) : _collapsed.remove(groupId))) return;
    await _changed();
  }

  /// Forget the group of a deleted instance.
  Future<void> forget(String instanceId) async {
    if (_of.remove(instanceId) != null) await _changed();
  }
}

final ChatGroups chatGroups = ChatGroups();
