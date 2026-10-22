# Chat interface (HTTP with JSON)

Revision 4 (2026-10-22). Language: ASD-STE100 (Simplified Technical English).

This document is the specification of the "chat" interface. A service that follows it can
be used from the conversation screen of chatui. This document is the only source of truth
for the interface. Each service and each client must adapt to it. If a service or a client
and this document do not agree, the service or the client is wrong.

Services that must follow this document:

| Service | Repository |
|---|---|
| `echo-chat` (echo service, the check of M4) | celaut-basics/echo-service |
| Claude remote service | copa-ai/claude-remote-service |

Client: `ChatClient` in `app/lib/celaut/chat_client.dart`.

The interface is small on purpose. HTTP and JSON are the only parts that the client and the
service share.

## 1. How to read this document

### 1.1 Requirement words

| Word | Meaning |
|---|---|
| must | The rule is a requirement. A service or a client that does not obey it does not follow this document |
| must not | The action is not permitted |
| can | The action is permitted. It is not a requirement |

Text in a table or in a list that does not use these words is a fact or an example.

### 1.2 Terms

| Term | Meaning |
|---|---|
| service | The program in the instance. It answers the requests of this document |
| client | The program that sends the requests. In chatui, the app |
| instance | One running copy of a service. One instance holds one conversation |
| message | One text of the conversation, with `seq`, `role`, `text` and, optional, `attachments` (section 5) |
| attachment | One file of a message. Section 5.1 describes it. Section 6.4 gives its bytes |
| `kind` | The class of a file: `image` or `audio` (section 5.1) |
| `accepts` | The list of kinds that the service accepts in a send (section 6.2) |
| `count` | The number of messages that the service holds. The `seq` of the next message is `count` |
| `expect` | The `count` that the client believes that the service has |
| send | One `POST /chat/messages` request |
| history | The list of all messages of the instance, in order of `seq` |

## 2. Decisions

| Topic | Date | Decision (Josemi) |
|---|---|---|
| History | 2026-10-14 | The service keeps the history. The client does not send it with each message |
| Session | 2026-10-14 | One session for each instance. The instance is the conversation. When the instance stops, the conversation ends |
| Synchronization | 2026-10-14 | Each message has a number. The client can ask the service for the history at any time |
| Answers | 2026-10-14 | One complete answer for each message. Streaming is not in this revision |
| Attachments | 2026-10-22 | A message can have image files and audio files (section 5.1). The client sends the files in the send, in base64 (section 6.1). The client reads a file with a separate request (section 6.4). The service lists the kinds that it accepts in `accepts` (section 6.2). A service with no `accepts` accepts text only |
| Discovery | 2026-10-14 | The service declares the interface in its `Service.Api` (section 3). There is no discovery endpoint |
| Version | 2026-10-14 | The tag has no version. The interface only grows with new optional fields (section 11) |

## 3. Declaration in the service interface

A service follows this interface if its `Service.Api` has one `Slot` with these values
(`nodo:protos/celaut.proto`, `Service.Api.Slot`):

| Field | Value |
|---|---|
| `transport.tags` | contains `tcp` |
| `protocol_stack` | from bottom to top: a `Protocol` with `tags` that contain `http`, and above it a `Protocol` with `tags` that contain `chat` |

The client reads the interface in the answer of `StartService` (`Instance.api`). It uses
the `port` of this slot for `ServiceTunnel`.

- A slot counts only if the instance has that port in `Instance.uri_slot`.
- If no slot counts, the client must not show the service as a chat service.
- If more than one slot counts, the client must use the first.
- The service must listen on the port of the slot.
- The service must not use the same port for other protocols.

The `prose` of the `chat` protocol can describe the service for the user. The client does
not parse it.

## 4. Transport

- The service must speak HTTP/1.1 on the port of the slot. The service must not require TLS.
  The tunnel of the node gives the secure channel.
- The service must support keep-alive connections. The client opens one connection for the
  whole conversation, because each connection costs `TUNNEL_OPEN_MU` (section 9).
- The service must close a connection only when the connection is idle, or when the client
  asks for it. The service must not close a connection to signal an error. It must send an
  error status (section 8).
- The client must send a `Content-Length` header on each request that has a body.
- The service must read a body that has a `Content-Length` header. The service can also
  read a chunked body.
- The service must send a `Content-Length` header on each answer that has a body.
- The client sends `Content-Type: application/json` on each request that has a body. The
  service must read the body as JSON in UTF-8 and must not require the `charset` parameter.
- The service must set `Content-Type: application/json` on each answer that has a body.
  The service must use UTF-8.
- The client and the service must ignore JSON fields that they do not know. They must
  ignore HTTP headers that they do not know.
- The service must ignore query parameters that it does not know.
- The service must reply with status 404 and `{"error": "not_found"}` to a path that this
  document does not define.
- For the path `/chat/messages`, the service must reply with status 405 and
  `{"error": "method_not_allowed"}` to a method that is not GET or POST. The `Allow`
  header of this answer is `GET, POST`.
- For a path of section 6.4, the service must reply with status 405 and
  `{"error": "method_not_allowed"}` to a method that is not GET. The `Allow` header of
  this answer is `GET`. A HEAD request is a method that is not GET.

## 5. Messages

A message has these fields:

| Field | Type | Meaning |
|---|---|---|
| `seq` | integer, 0 or more | The position of the message in the conversation. The first message has `seq` 0. User messages and assistant messages share the same count |
| `role` | string | `user` or `assistant` |
| `text` | string | The text, in UTF-8. It is empty only if the message has an attachment |
| `attachments` | list, optional | The files of the message (section 5.1). If the message has no file, the field is absent or the list is empty |

Rules:

- The service must keep `count`. The next message gets `seq` equal to `count`.
- The history has no gaps. A message has `seq` equal to its index in the history.
- The service must not change or delete a message that it holds.
- The roles alternate. A user message has an even `seq`. The assistant message that answers
  it has the next `seq`.
- `text` of a user message must be the text that the client sent, without a change. The
  service must not remove, add or change a character, including space characters.
- The service must keep and return a message in the same order and with the same `seq`
  each time.
- A `seq` is a JSON integer. The service must not write it as a float (`4.0`) or a string.

### 5.1 Attachments

An attachment is a description of one file. The description has these fields:

| Field | Type | Meaning |
|---|---|---|
| `kind` | string | `image` or `audio`. It is the part of `mime` before the `/`. No other value is valid |
| `mime` | string | The media type, for example `image/jpeg`. The service compares it in lower case and without parameters. The service keeps the lower case form, without parameters, and gives it in `Content-Type` (section 6.4) |
| `name` | string, optional | The name of the file, for the user to read. The service must not use it as a path |
| `size` | integer | The number of bytes of the file after the base64 decoding |

The data of the file is not in a message. The client reads it with section 6.4.

An attachment has an index in its message. The first attachment has index 0. The
`attachments` list of a message must not change after the service adds the message.
The service must not change the bytes of a file.

Media types that a service must accept, if it says that it accepts the kind (section 6.2):

| Kind | Media types |
|---|---|
| `image` | `image/jpeg`, `image/png` |
| `audio` | `audio/mpeg`, `audio/wav` |

A service can accept more media types. A service can give an attachment in an assistant
message, for example an image that it makes.

## 6. Requests

### 6.1 Send a message

```
POST /chat/messages
Content-Type: application/json

{"expect": 4, "text": "Hello"}
```

| Field | Type | Rule |
|---|---|---|
| `expect` | integer, 0 or more | Required. The `count` that the client believes that the service has |
| `text` | string | Required. The text of the message. It must not be empty, unless the request has `attachments` |
| `attachments` | list, optional | The files of the message. A request has 1 to 4 files. See below |

An item of `attachments` has `mime` (string, required), `name` (string, optional) and
`data` (string, required: the bytes of the file, in base64 as RFC 4648 section 4, with no
line break). The rules for the client to send `attachments` are in section 9. Example:

```
{"expect": 4, "text": "What is this?",
 "attachments": [{"mime": "image/jpeg", "name": "tree.jpg", "data": "/9j/4AAQ..."}]}
```

The service must check the request in this order and stop at the first failure:

| Step | Check | Failure |
|---|---|---|
| 1 | The body is valid JSON and an object. `expect` is an integer of 0 or more (not a float, not a string, not a boolean). `text` is a string. `text` is not empty, unless `attachments` has an item. `attachments`, if present, is a list of 1 to 4 items. Each item has a `mime` string and a `data` string of valid base64 | 400 `bad_request` |
| 2 | The size of the body, of `text` and of each file is in the limit of the service (section 7) | 400 `bad_request` |
| 3 | Each `mime` is a type that the service accepts (see below) | 415 `unsupported_media` |
| 4 | The service has no other send in progress | 503 `busy` |
| 5 | `expect` is equal to `count` | 409 `out_of_sync` |
| 6 | The history has room for two more messages | 413 `history_full` |

A body above the limit of the service gets status 400 `bad_request`. It does not get status
413, because 413 is `history_full`. The check of the size (step 2) is before the check of
the type (step 3). A file of a type that the service does not accept, and above the limit
of size, gets 400.

For step 3, the service reads `mime` in lower case and without parameters. A `mime`
is accepted if its kind is in `accepts` (section 6.2) and the service supports the type.
A send with attachments to a service that has no `accepts` gets 415 `unsupported_media`.
A `mime` of a kind that is not in `accepts` gets 415 too.

If all checks pass, the service must do these steps:

1. Make the answer for `text`.
2. Add the user message with `seq` equal to `expect`, and the assistant message with the
   next `seq`. The service must add the two messages at the same time. A reader never
   sees one of them without the other.
3. Reply with status 200:

```
{"count": 6,
 "messages": [{"seq": 4, "role": "user", "text": "Hello"},
              {"seq": 5, "role": "assistant", "text": "Hello"}]}
```

`messages` has the two messages that this send added, in order. The user message has
`attachments` with the description of each file (section 5.1), without `data`. `count` is
the `count` after the send.

If the service fails to make the answer, the service must change nothing. The service must
not change `count`. The service must not keep the user message. The service must reply with
status 500 and `{"error": "service_error"}`. The `message` field is optional.

If a check of the table fails, the service must change nothing.

### 6.2 Read the history

```
GET /chat/messages?from=4
```

| Parameter | Type | Rule |
|---|---|---|
| `from` | integer, 0 or more | Optional. The first `seq` that the client wants. Default: 0 |

`from` is valid only if it is a string of one or more ASCII digits (`0` to `9`). The value
has no sign, no space, no decimal point and no other character. The service must
reply with status 400 and `bad_request` to a value that is not valid. Digits that are
not ASCII, such as `²`, are not valid. The service must not close the connection.

If `from` is more than `count`, the service must reply with status 400 and `bad_request`.
If `from` is equal to `count`, the service replies with status 200 and an empty list.

The service replies with status 200:

```
{"count": 6, "accepts": ["image", "audio"], "messages": [{"seq": 4, ...}, {"seq": 5, ...}]}
```

`accepts` is optional. It is the only optional field of the answer, with `attachments` in
a message. It is the list of the kinds of attachment that the service accepts in a send:
`image`, `audio`, or both. If `accepts` is absent or empty, the service accepts text only.
The service must put the same `accepts` in each answer, for the whole life of the
instance. A message in `messages` can have `attachments` (section 5.1).

`count` is the total number of messages of the history. It is not the number of messages in
the answer.

`messages` has the messages with `seq` equal to or more than `from`, in order. If the
history is empty, `count` is 0 and `messages` is an empty list. The answer has `accepts`
if the service accepts attachments.

The body of the answer must be 1 MiB (1 048 576 bytes) or less. If the messages from `from`
are more than that, the service must give fewer messages. The service must give the messages
in order, from `from`, with no gap. The service must give at least one message if `from` is
less than `count`. The client reads the rest with a new read from its own count (section 9).

The service must answer this request also when a send is in progress. The reply holds only
the messages that the service has added. It does not hold the message of the send in
progress (section 6.1, step 2). The service must not answer this request with 503.

The client uses this request:

- to start the screen again when the instance runs;
- to repair a lost answer (section 6.3);
- to wait for a service that starts (section 9).

### 6.3 Lost connection

A client that loses the connection after a send does not know if the service got the
message.

1. The client must not send the message again at once.
2. The client must read the history (section 6.2) from its own `count`.
3. If the message is in the history, the send worked. The client uses the history as
   the answer.
4. If the message is not in the history, the send did not happen. The client tells the
   user. The user decides to send the message again. The client must not send it again
   by itself.

If a send takes more time than the client waits for, the service can still add the two
messages after that time. The client then reads them at the next read of the history.

The client waits 30 seconds for a request that has no files. The client waits 120 seconds
for a send that has files (`TunnelHttp`). A service that makes an answer in more time than
30 seconds must use the rules of section 7.

### 6.4 Read an attachment

```
GET /chat/messages/4/attachments/0
```

The first number is `seq`. The second number is the index of the attachment in its
message. Each number is valid only if it is a string of one or more ASCII digits. A number
with leading zeros, such as `007`, is valid. A number above 2^63-1 is valid.

The service replies with status 200. The body is the bytes of the file. The service must not
change the bytes. `Content-Type` is the `mime` of the attachment. `Content-Length` is `size`.

- If a number is not valid, the service replies with status 400 `bad_request`.
- If the message or the attachment does not exist, the service replies with status 404
  `not_found`. A number above 2^63-1 gives 404.
- The message of a send in progress is not in the history. An attachment of this message
  gives 404.
- The 400, 404 and 405 answers have the JSON error body of section 8.
- The service must answer this request also when a send is in progress.

The client can keep the bytes in memory. It must not write them to the Celaut database.

## 7. Limits

| Limit | Value |
|---|---|
| Time to answer a send | The service must make the answer in 30 seconds or less. The service counts the time from the end of the request body. If the service needs more time, the client sees a lost connection (section 6.3). The client then reads the history. If the two messages are in the history, the send worked. The client does not send the message again |
| Size of `text` | The service must accept `text` of 16 384 bytes (UTF-8) or less. The service can accept more. The service must reply with status 400 to a `text` above its own limit |
| Size of a request body, text only | The service must accept a body of 128 KiB (131 072 bytes) or less. The service can accept more |
| Size of a request body, with attachments | A service that accepts attachments must accept a body of 24 MiB (25 165 824 bytes) or less. The service can accept more |
| Body above the limit | The service must reply with status 400 `bad_request`. The service must not reply with status 413 |
| Size of a file | A service that accepts attachments must accept a file of 4 MiB (4 194 304 bytes) or less. The service can accept more. The service must reply with status 400 to a file above its own limit |
| Number of files | A service that accepts attachments must accept 4 files in one send |
| Size of the history | The service decides. When the history has no room for two more messages, the service replies with status 413 `history_full` |
| Size of the answer to a read | The body of the answer to a read of the history must be 1 MiB (1 048 576 bytes) or less (section 6.2) |

The limit of 128 KiB is more than 6 x 16 384 + 1 024 bytes (99 328 bytes). In JSON, one
control character of `text` can use 6 bytes (`\u0000`). A `text` of 16 384 bytes then fits in
the limit.

The limit of 24 MiB comes from this sum. One file of 4 MiB is 5 592 408 bytes in base64
(4 x 1 398 102). Four files are 22 369 632 bytes. The other 2 796 192 bytes are for `text`
(up to 98 304 bytes in JSON), the names and the JSON syntax.

A service that does not make an answer in 30 seconds must reply with status 503 `busy` to
the next send until the answer is in the history. This is the rule of step 4 of
section 6.1.

## 8. Errors

| Status | `error` | Meaning |
|---|---|---|
| 400 | `bad_request` | A request is not valid. The list below gives the cases |
| 404 | `not_found` | The path is not defined in this document, or the message or the attachment of section 6.4 does not exist |
| 405 | `method_not_allowed` | The method is not GET or POST for `/chat/messages`, or not GET for a path of section 6.4 |
| 409 | `out_of_sync` | `expect` is not equal to `count`. The body has `count` |
| 413 | `history_full` | The service does not keep more messages. The client tells the user to start a new instance |
| 415 | `unsupported_media` | A `mime` of a file is not accepted, or the service accepts text only. The service changed nothing |
| 500 | `service_error` | The service failed to make the answer. The service changed nothing |
| 503 | `busy` | The service makes the answer for a message already. The client tries again later |

A 400 answer is for one of these cases:

- The body is not valid JSON, or is not an object.
- A field is missing or has the wrong type.
- `expect` is less than 0.
- `text` is empty and there is no attachment.
- `text` is above the limit of the service.
- The body is above the limit of the service.
- `attachments` is an empty list, or has more than 4 items.
- A file is above the limit of the service.
- The `data` of a file is not valid base64.
- `from` is not valid, or is more than `count`.
- A number of a path of section 6.4 is not valid.

An error body is `{"error": "<name>", "message": "<text for the user>"}`. `message` is
optional. If `message` is present, it is text that the client can show to the user. The
409 body also has `count`, for example `{"error": "out_of_sync", "count": 6}`.

A service must not use a status that is not in this table for a request that this
document defines. A client treats a status that is not in this table as an error that it
does not know (`ChatErrorKind.other`).

A service must keep only one send in progress. The service must never change `count` for a
send that failed.

## 9. Client rules

These rules cover the protocol only. The screens, the cost, the stop of an instance and the
storage of the app are not part of this document ([ui-chat-first.md](ui-chat-first.md)).

- The client must send one request at a time. A new send waits for the end of the send
  before it.
- The client must not send a message that has an empty `text` and no attachment.
- The client must send `attachments` only if the last read of the history had the kind in
  `accepts` (section 6.2).
- The client must not send more than 4 files in one send. The client must not send a file
  above 4 MiB. The client does not know if the service accepts more.
- The client must send only the media types of the table in section 5.1.
- The client must read the bytes of a file only with the request of section 6.4.
- If the answer to a send is 415, the client must not send the same files again. The
  client tells the user.
- If the answer to a send is 400, the client must not send the same send again by itself.
  The client tells the user.
- The client must read the history from 0 when it opens a conversation that it does not
  have.
- If a read of the history has fewer messages than `count` minus `from`, the client must read
  again from its own count. The client stops when its count is equal to `count`.
- A service can need some seconds to listen after the start of its instance. Until then, a
  request fails to connect. The client can read the history again until the service
  answers. It must not send a message before a read of the history works.
- A client that gets a `seq` that is not the next one (a gap) must treat the answer as an
  error. A client skips a message that it has already.
- The client must use HTTP keep-alive and open one connection for the whole conversation.
  Each connection through the tunnel is one `ServiceTunnel` stream, and the node charges
  for each stream (`TUNNEL_OPEN_MU`).
- The client must send `Content-Length` on each request that has a body (section 4).
- The client must follow section 6.3 after a lost connection.

## 10. Conformance

A service follows revision 4 if it obeys each "must" and "must not" of sections 3 to 8. A
client follows revision 4 if it obeys each "must" and "must not" of sections 6.3 and 9.

### 10.1 Tests

Run these tests on a new instance. `$B` is the base URL of the tunnel, for example
`http://127.0.0.1:PORT`. `N` is the `count` of the service at the time of the test. Each
test gives the expected result. A service that accepts attachments sends `accepts` in each
answer to a read of the history. A service that accepts text only does not send it.

| # | Request | Expected result |
|---|---|---|
| 1 | `GET /chat/messages` | 200, `count` 0, `messages` is an empty list. `accepts` is as in test 19 |
| 2 | `GET /chat/messages?from=0` | 200, same body as test 1 |
| 3 | `GET /chat/messages?from=1` | 400 `bad_request` |
| 4 | `GET /chat/messages?from=²` | 400 `bad_request`, and the connection stays open |
| 5 | `GET /chat/messages?from=-1`, `?from=1.0`, `?from=` , `?from=a` | 400 `bad_request` for each |
| 6 | `POST` with body `{"expect":0,"text":"one"}` | 200, `count` 2, two messages: `seq` 0 `user` "one", `seq` 1 `assistant` |
| 7 | `POST` with body `{"expect":0,"text":"again"}` | 409 `out_of_sync`, `count` 2. A `GET` after it still has `count` 2 |
| 8 | `POST` with body `{"expect":2,"text":"two"}` | 200, `count` 4, `seq` 2 and 3 |
| 9 | `GET /chat/messages?from=2` | 200, `count` 4, two messages with `seq` 2 and 3 |
| 10 | `GET /chat/messages?from=4` | 200, `count` 4, `"messages":[]`. `accepts` is as in test 19 |
| 11 | `POST` with body `not json` | 400 `bad_request` |
| 12 | `POST` with bodies `{}`, `{"expect":4}`, `{"text":"x"}`, `{"expect":"4","text":"x"}`, `{"expect":4.0,"text":"x"}`, `{"expect":-1,"text":"x"}`, `{"expect":4,"text":""}`, `{"expect":4,"text":5}` | 400 `bad_request` for each. `count` stays 4 |
| 13 | `POST` with body `{"expect":4,"text":"  x  é ✓"}` | 200. The `text` of the user message is `  x  é ✓`, without a change |
| 14 | `POST` with `text` of 16 384 bytes. Use a second request with a `text` of 16 384 newline characters | 200 for each |
| 15 | `PUT /chat/messages`, then `GET /chat/other` | 405 with `Allow: GET, POST`, then 404 |
| 16 | `POST` with an unknown field, for example `{"expect":N,"text":"x","extra":1}` | 200. The service ignores `extra` |
| 17 | Five requests on one keep-alive connection | All five get an answer on the same connection |
| 18 | While a send takes time (a slow service): `GET /chat/messages`, and a second `POST` | The `GET` gets 200, without the message in progress. The `POST` gets 503 `busy` |
| 19 | `GET /chat/messages` on a service that accepts attachments | `accepts` is a list that has `image`, `audio` or both. A service that accepts text only has no `accepts` or an empty list |
| 20 | `POST` with `{"expect":N,"text":"","attachments":[{"mime":"image/png","data":"<a valid PNG in base64>"}]}` (only if `accepts` has `image`) | 200. The user message has `attachments` `[{"kind":"image","mime":"image/png","size":<bytes>}]` and no `data`. `size` is the number of bytes of the PNG |
| 21 | `GET /chat/messages/<seq>/attachments/0` for the message of test 20 | 200. The body is the same bytes. `Content-Type: image/png`. `Content-Length` is `size` |
| 22a | `GET /chat/messages/<seq>/attachments/1` | 404 `not_found`, with a JSON error body |
| 22b | `GET /chat/messages/9999/attachments/0` | 404 `not_found`, with a JSON error body |
| 22c | `GET /chat/messages/x/attachments/0` | 400 `bad_request`, with a JSON error body |
| 23 | `POST` with an attachment of `"mime":"application/pdf"` | 415 `unsupported_media`. `count` does not change |
| 24a | `POST` with `"data":"not base64!"` | 400 `bad_request`. `count` does not change |
| 24b | `POST` with 5 files | 400 `bad_request`. `count` does not change |
| 24c | `POST` with `"text":""` and no `attachments` | 400 `bad_request`. `count` does not change |
| 24d | `POST` with a file of 4 MiB + 1 byte (only if the limit of the service is 4 MiB) | 400 `bad_request`. `count` does not change |
| 25a | `POST` with one file of exactly 4 MiB (only if `accepts` has the kind) | 200 |
| 25b | `POST` with 4 files of 4 MiB each, `expect` equal to `N` (only if `accepts` has the kind). The body is about 22.4 MB | 200 |
| 26a | `POST` with an attachment of `"mime":"image/png"` to a service that has no `accepts` | 415 `unsupported_media`. `count` does not change |
| 26b | `POST` with an attachment of a kind that is not in `accepts`, for example `"mime":"audio/mpeg"` to a service with `"accepts":["image"]` | 415 `unsupported_media`. `count` does not change |
| 27 | `POST` with body `{"expect":true,"text":"x"}` | 400 `bad_request`. `count` does not change |
| 28 | `POST` with `"attachments":[]` | 400 `bad_request`. `count` does not change |
| 29 | `POST` with `text` of 16 385 bytes (only if the limit of the service is 16 384 bytes) | 400 `bad_request`. `count` does not change |
| 30 | `GET /chat/messages` at the start, after a send, and after the last test | `accepts` is the same in each answer |
| 31 | `POST` with `"mime":"IMAGE/PNG"` and a valid PNG (only if `accepts` has `image`) | 200. The attachment has `"kind":"image"` and `"mime":"image/png"` |
| 32 | `POST` and `HEAD` for `/chat/messages/<seq>/attachments/0`, then `HEAD /chat/messages` | 405 with `Allow: GET`, 405 with `Allow: GET`, then 405 with `Allow: GET, POST` |
| 33 | `GET /chat/messages/00<seq>/attachments/00` for the message of test 20, then `GET /chat/messages/99999999999999999999/attachments/0` | 200 with the same bytes, then 404 `not_found` |
| 34 | While a send with an attachment takes time: `GET /chat/messages/<seq of the send>/attachments/0` | 404 `not_found` |
| 35 | Send messages until the history is full (optional) | 413 `history_full`. `count` does not change |
| 36 | `POST` while the service fails to make the answer (optional) | 500 `service_error`. `count` does not change. A `GET` does not show the user message |

Tests 18 and 34 apply to a service that takes time to answer. A service that answers at once
can skip them. The rule of step 4 is then not tested.

Test 35 is optional. A service with a large history limit does not fill the history in a test.
Test 36 is optional. A service can fail on request only if it has a way to make it fail, for
example a test mode.

## 11. Changes to the interface

The tag is `chat` and it has no version. This document has a revision number. The
revision number is for the people who write services and clients. It is not on the wire.

A change must not break a service or a client that follows this document.

- A new field is optional. A client or service that does not know it ignores it.
- A new status or a new `error` name is not permitted for a request that this document
  defines, unless the document gives a rule that an old client can follow.
- A change to a "must" is a new revision. The revision history (section 13) lists it.

Streaming is a future change. It will add an optional way to read a partial answer, and a
service without it stays valid.

## 12. Reference services

### 12.1 Echo service

The echo service is the check of M4. It follows this document. The `text` of each answer is
the `text` of the message that it answers. It keeps the messages in a list in memory. It
answers at once, so it does not need the rules for long answers (sections 6.3 and 7).

### 12.2 Claude remote service

The Claude remote service sends each user message to a language model. An answer can take
more than 30 seconds. The service must follow section 7: it must reply with status 503
`busy` to a send while an answer is in progress, and it must add the two messages only when
the answer is ready. The service must keep the whole history, in the order of `seq`, and
must not change a message after it adds it.

## 13. Revision history

| Revision | Date | Change |
|---|---|---|
| 1 | 2026-10-14 | The convention of M4: messages, send, history, errors, client behavior |
| 2 | 2026-10-22 | The text is a specification in ASD-STE100, with requirement words. The tests 1 to 18 are new. New rules for the service: transport (section 4), the order of the checks (section 6.1), the strict value of `from`, the status 404, 405 and 500, the limits (section 7), and the conformance tests (section 10). The service must add the two messages of a send at the same time. The rules for the app (leave the screen, stop, cost, storage) leave this document |
| 3 | 2026-10-22 | Attachments: `attachments` in a message and in a send. `accepts` in the read of the history. The read of an attachment (section 6.4). The status 415. The limits for files. The tests 19 to 26. A service that does not know them stays valid for text only |
| 4 | 2026-10-22 | Clarifications. The meaning of revision 3 does not change for a service that follows it, with three exceptions. First, the body limit for text only is 128 KiB (it was 32 768 bytes). Second, a send with attachments to a text-only service gets 415 only (it was 400 or 415). Third, the answer to a read of the history must be 1 MiB or less.<br>The checks of section 6.1 have the numbers 1 to 6. A body above the limit gets 400, not 413. The `Allow` header is `GET` for the paths of section 6.4. HEAD gets 405. Section 4 has rules for `Content-Length` of requests and of answers.<br>Section 5.1 defines `kind`, `mime` and `size`. Section 6.3 gives the two waits of the client: 30 seconds, and 120 seconds for a send with files. The 30 seconds of the service start at the end of the request body. Section 6.4 gives the open cases. Section 9 has new rules for the client on files, 415, 400 and the read in parts.<br>The tests 22, 24, 25 and 26 are split in numbered rows. The tests 27 to 36 are new. The tests 1, 2 and 10 accept `accepts` |
