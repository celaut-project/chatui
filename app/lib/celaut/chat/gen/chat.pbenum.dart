// This is a generated file - do not edit.
//
// Generated from chat.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class MessageStatus extends $pb.ProtobufEnum {
  static const MessageStatus MESSAGE_STATUS_UNSPECIFIED =
      MessageStatus._(0, _omitEnumNames ? '' : 'MESSAGE_STATUS_UNSPECIFIED');
  static const MessageStatus MESSAGE_STATUS_PENDING =
      MessageStatus._(1, _omitEnumNames ? '' : 'MESSAGE_STATUS_PENDING');
  static const MessageStatus MESSAGE_STATUS_IN_PROGRESS =
      MessageStatus._(2, _omitEnumNames ? '' : 'MESSAGE_STATUS_IN_PROGRESS');
  static const MessageStatus MESSAGE_STATUS_COMPLETED =
      MessageStatus._(3, _omitEnumNames ? '' : 'MESSAGE_STATUS_COMPLETED');
  static const MessageStatus MESSAGE_STATUS_FAILED =
      MessageStatus._(4, _omitEnumNames ? '' : 'MESSAGE_STATUS_FAILED');
  static const MessageStatus MESSAGE_STATUS_CANCELLED =
      MessageStatus._(5, _omitEnumNames ? '' : 'MESSAGE_STATUS_CANCELLED');

  static const $core.List<MessageStatus> values = <MessageStatus>[
    MESSAGE_STATUS_UNSPECIFIED,
    MESSAGE_STATUS_PENDING,
    MESSAGE_STATUS_IN_PROGRESS,
    MESSAGE_STATUS_COMPLETED,
    MESSAGE_STATUS_FAILED,
    MESSAGE_STATUS_CANCELLED,
  ];

  static final $core.List<MessageStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static MessageStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const MessageStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
