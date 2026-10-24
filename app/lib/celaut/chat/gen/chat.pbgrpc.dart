// This is a generated file - do not edit.
//
// Generated from chat.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'chat.pb.dart' as $0;

export 'chat.pb.dart';

@$pb.GrpcServiceName('ChatService')
class ChatServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  ChatServiceClient(super.channel, {super.options, super.interceptors});

  /// Envía un mensaje a la conversación principal o a una rama.
  $grpc.ResponseFuture<$0.Message> sendMessage(
    $0.SendMessageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$sendMessage, request, options: options);
  }

  /// Recupera mensajes de forma incremental.
  /// after_sequence = 0 permite comenzar desde el inicio.
  $grpc.ResponseStream<$0.Message> getMessages(
    $0.GetMessagesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$getMessages, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Canal bidireccional para mensajes y eventos en tiempo real.
  $grpc.ResponseStream<$0.ServerEvent> connect(
    $async.Stream<$0.ClientEvent> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$connect, request, options: options);
  }

  /// Crea una rama desde un mensaje existente.
  $grpc.ResponseFuture<$0.Conversation> forkConversation(
    $0.ForkConversationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$forkConversation, request, options: options);
  }

  /// Consulta los metadatos de una conversación.
  $grpc.ResponseFuture<$0.Conversation> getConversation(
    $0.GetConversationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getConversation, request, options: options);
  }

  /// Fija o desfija un mensaje.
  $grpc.ResponseFuture<$0.Message> setMessagePinned(
    $0.SetMessagePinnedRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setMessagePinned, request, options: options);
  }

  /// Revisión 6.
  /// Consulta lo que el servicio acepta y sus límites.
  /// Es la primera llamada del cliente: también sirve para saber
  /// si el servicio ya escucha. Su resultado no cambia durante la
  /// vida de la instancia.
  $grpc.ResponseFuture<$0.Capabilities> getCapabilities(
    $0.GetCapabilitiesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getCapabilities, request, options: options);
  }

  // method descriptors

  static final _$sendMessage =
      $grpc.ClientMethod<$0.SendMessageRequest, $0.Message>(
          '/ChatService/SendMessage',
          ($0.SendMessageRequest value) => value.writeToBuffer(),
          $0.Message.fromBuffer);
  static final _$getMessages =
      $grpc.ClientMethod<$0.GetMessagesRequest, $0.Message>(
          '/ChatService/GetMessages',
          ($0.GetMessagesRequest value) => value.writeToBuffer(),
          $0.Message.fromBuffer);
  static final _$connect = $grpc.ClientMethod<$0.ClientEvent, $0.ServerEvent>(
      '/ChatService/Connect',
      ($0.ClientEvent value) => value.writeToBuffer(),
      $0.ServerEvent.fromBuffer);
  static final _$forkConversation =
      $grpc.ClientMethod<$0.ForkConversationRequest, $0.Conversation>(
          '/ChatService/ForkConversation',
          ($0.ForkConversationRequest value) => value.writeToBuffer(),
          $0.Conversation.fromBuffer);
  static final _$getConversation =
      $grpc.ClientMethod<$0.GetConversationRequest, $0.Conversation>(
          '/ChatService/GetConversation',
          ($0.GetConversationRequest value) => value.writeToBuffer(),
          $0.Conversation.fromBuffer);
  static final _$setMessagePinned =
      $grpc.ClientMethod<$0.SetMessagePinnedRequest, $0.Message>(
          '/ChatService/SetMessagePinned',
          ($0.SetMessagePinnedRequest value) => value.writeToBuffer(),
          $0.Message.fromBuffer);
  static final _$getCapabilities =
      $grpc.ClientMethod<$0.GetCapabilitiesRequest, $0.Capabilities>(
          '/ChatService/GetCapabilities',
          ($0.GetCapabilitiesRequest value) => value.writeToBuffer(),
          $0.Capabilities.fromBuffer);
}

@$pb.GrpcServiceName('ChatService')
abstract class ChatServiceBase extends $grpc.Service {
  $core.String get $name => 'ChatService';

  ChatServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.SendMessageRequest, $0.Message>(
        'SendMessage',
        sendMessage_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SendMessageRequest.fromBuffer(value),
        ($0.Message value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetMessagesRequest, $0.Message>(
        'GetMessages',
        getMessages_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.GetMessagesRequest.fromBuffer(value),
        ($0.Message value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ClientEvent, $0.ServerEvent>(
        'Connect',
        connect,
        true,
        true,
        ($core.List<$core.int> value) => $0.ClientEvent.fromBuffer(value),
        ($0.ServerEvent value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ForkConversationRequest, $0.Conversation>(
        'ForkConversation',
        forkConversation_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ForkConversationRequest.fromBuffer(value),
        ($0.Conversation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetConversationRequest, $0.Conversation>(
        'GetConversation',
        getConversation_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetConversationRequest.fromBuffer(value),
        ($0.Conversation value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetMessagePinnedRequest, $0.Message>(
        'SetMessagePinned',
        setMessagePinned_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetMessagePinnedRequest.fromBuffer(value),
        ($0.Message value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetCapabilitiesRequest, $0.Capabilities>(
        'GetCapabilities',
        getCapabilities_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetCapabilitiesRequest.fromBuffer(value),
        ($0.Capabilities value) => value.writeToBuffer()));
  }

  $async.Future<$0.Message> sendMessage_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SendMessageRequest> $request) async {
    return sendMessage($call, await $request);
  }

  $async.Future<$0.Message> sendMessage(
      $grpc.ServiceCall call, $0.SendMessageRequest request);

  $async.Stream<$0.Message> getMessages_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetMessagesRequest> $request) async* {
    yield* getMessages($call, await $request);
  }

  $async.Stream<$0.Message> getMessages(
      $grpc.ServiceCall call, $0.GetMessagesRequest request);

  $async.Stream<$0.ServerEvent> connect(
      $grpc.ServiceCall call, $async.Stream<$0.ClientEvent> request);

  $async.Future<$0.Conversation> forkConversation_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ForkConversationRequest> $request) async {
    return forkConversation($call, await $request);
  }

  $async.Future<$0.Conversation> forkConversation(
      $grpc.ServiceCall call, $0.ForkConversationRequest request);

  $async.Future<$0.Conversation> getConversation_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetConversationRequest> $request) async {
    return getConversation($call, await $request);
  }

  $async.Future<$0.Conversation> getConversation(
      $grpc.ServiceCall call, $0.GetConversationRequest request);

  $async.Future<$0.Message> setMessagePinned_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SetMessagePinnedRequest> $request) async {
    return setMessagePinned($call, await $request);
  }

  $async.Future<$0.Message> setMessagePinned(
      $grpc.ServiceCall call, $0.SetMessagePinnedRequest request);

  $async.Future<$0.Capabilities> getCapabilities_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetCapabilitiesRequest> $request) async {
    return getCapabilities($call, await $request);
  }

  $async.Future<$0.Capabilities> getCapabilities(
      $grpc.ServiceCall call, $0.GetCapabilitiesRequest request);
}

@$pb.GrpcServiceName('FileService')
class FileServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  FileServiceClient(super.channel, {super.options, super.interceptors});

  /// Consulta la disponibilidad de archivos identificados por hash.
  ///
  /// Se envía un hash por mensaje y se recibe una respuesta
  /// por cada consulta, en el mismo orden.
  ///
  /// El primer hash debe incluir type.
  /// Los siguientes pueden omitirlo para reutilizar el último
  /// type explícito del mismo stream cliente-servidor.
  $grpc.ResponseStream<$0.QueryFilesResponse> queryFiles(
    $async.Stream<$0.QueryFilesRequest> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$queryFiles, request, options: options);
  }

  /// Sube un archivo mediante streaming.
  ///
  /// El primer mensaje contiene los metadatos del archivo.
  /// Los mensajes siguientes contienen bloques de bytes.
  $grpc.ResponseFuture<$0.UploadFileResponse> uploadFile(
    $async.Stream<$0.UploadFileRequest> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$uploadFile, request, options: options).single;
  }

  /// Descarga un archivo identificado por su hash.
  $grpc.ResponseStream<$0.DownloadFileResponse> downloadFile(
    $0.DownloadFileRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$downloadFile, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$queryFiles =
      $grpc.ClientMethod<$0.QueryFilesRequest, $0.QueryFilesResponse>(
          '/FileService/QueryFiles',
          ($0.QueryFilesRequest value) => value.writeToBuffer(),
          $0.QueryFilesResponse.fromBuffer);
  static final _$uploadFile =
      $grpc.ClientMethod<$0.UploadFileRequest, $0.UploadFileResponse>(
          '/FileService/UploadFile',
          ($0.UploadFileRequest value) => value.writeToBuffer(),
          $0.UploadFileResponse.fromBuffer);
  static final _$downloadFile =
      $grpc.ClientMethod<$0.DownloadFileRequest, $0.DownloadFileResponse>(
          '/FileService/DownloadFile',
          ($0.DownloadFileRequest value) => value.writeToBuffer(),
          $0.DownloadFileResponse.fromBuffer);
}

@$pb.GrpcServiceName('FileService')
abstract class FileServiceBase extends $grpc.Service {
  $core.String get $name => 'FileService';

  FileServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.QueryFilesRequest, $0.QueryFilesResponse>(
        'QueryFiles',
        queryFiles,
        true,
        true,
        ($core.List<$core.int> value) => $0.QueryFilesRequest.fromBuffer(value),
        ($0.QueryFilesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UploadFileRequest, $0.UploadFileResponse>(
        'UploadFile',
        uploadFile,
        true,
        false,
        ($core.List<$core.int> value) => $0.UploadFileRequest.fromBuffer(value),
        ($0.UploadFileResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.DownloadFileRequest, $0.DownloadFileResponse>(
            'DownloadFile',
            downloadFile_Pre,
            false,
            true,
            ($core.List<$core.int> value) =>
                $0.DownloadFileRequest.fromBuffer(value),
            ($0.DownloadFileResponse value) => value.writeToBuffer()));
  }

  $async.Stream<$0.QueryFilesResponse> queryFiles(
      $grpc.ServiceCall call, $async.Stream<$0.QueryFilesRequest> request);

  $async.Future<$0.UploadFileResponse> uploadFile(
      $grpc.ServiceCall call, $async.Stream<$0.UploadFileRequest> request);

  $async.Stream<$0.DownloadFileResponse> downloadFile_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DownloadFileRequest> $request) async* {
    yield* downloadFile($call, await $request);
  }

  $async.Stream<$0.DownloadFileResponse> downloadFile(
      $grpc.ServiceCall call, $0.DownloadFileRequest request);
}
