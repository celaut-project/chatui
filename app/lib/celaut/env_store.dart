import 'dart:convert';

import '../bridge/api/celaut.dart';
import '../bridge/api/celaut_env.dart';

/// Why a name or a value of the container is refused. The rules are the ones of the node
/// and of `celaut_client::env`: the screen checks them before it calls Rust, so that each
/// reason has its own text.
enum EnvProblem { nameEmpty, nameBad, nameReserved, valueEmpty, valueLong, valueNul }

const envReservedName = '__nodo_instance_name';
const envMaxNameBytes = 256;
const envMaxValueBytes = 8 * 1024;
const envMaxVariables = 256;

final _nameShape = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// The problem with [name], or null if the node can use it.
EnvProblem? envNameProblem(String name) {
  if (name.isEmpty) return EnvProblem.nameEmpty;
  if (name.length > envMaxNameBytes || !_nameShape.hasMatch(name)) return EnvProblem.nameBad;
  if (name == envReservedName) return EnvProblem.nameReserved;
  return null;
}

/// The problem with [value], or null if the node can use it.
EnvProblem? envValueProblem(String value) {
  if (value.isEmpty) return EnvProblem.valueEmpty;
  if (utf8.encode(value).length > envMaxValueBytes) return EnvProblem.valueLong;
  if (value.contains('\u0000')) return EnvProblem.valueNul;
  return null;
}

/// The container of environment variables of the app (`docs/celaut/env-variables.md`).
/// The calls are injected so that tests need no Rust.
class EnvStore {
  EnvStore({
    List<EnvNameView> Function()? names,
    String? Function(String name)? get,
    void Function(String name, String value)? set,
    void Function(String name)? delete,
  })  : _names = names ?? celautEnvNames,
        _get = get ?? ((name) => celautEnvGet(name: name)),
        _set = set ?? ((name, value) => celautEnvSet(name: name, value: value)),
        _delete = delete ?? ((name) => celautEnvDelete(name: name));

  final List<EnvNameView> Function() _names;
  final String? Function(String) _get;
  final void Function(String, String) _set;
  final void Function(String) _delete;

  /// The variables, by name. The values are not read.
  List<EnvNameView> names() => _names();

  /// The value of a variable, or null if it does not exist. For the eye and the edit.
  String? value(String name) => _get(name);

  /// Add a variable or replace its value. Throws [CelautError] if Rust refuses it.
  void set(String name, String value) => _set(name, value);

  void delete(String name) => _delete(name);
}
