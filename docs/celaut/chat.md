# Chat interface (HTTP with JSON)

Revision 3 (2026-10-22). Language: ASD-STE100 (Simplified Technical English).

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
| message | One text of the conversation, with `seq`, `role` and `text` (section 5) |
| `count` | The number of messages that the service holds. The `seq` of the next message is `count` |
| `expect` | The `count` that the client believes that the service has |
| send | One `POST /chat/messages` request |
| history | The list of all messages of the instance, in order of `seq` |

## 2. Decisions

| Topic | Decision (Josemi, 2026-10-14) |
|---|---|
| History | The service keeps the history. The client does not send it with each message |
| Session | One session for each instance. The instance is the conversation. When the instance stops, the conversation ends |
| Synchronization | Each message has a number. The client can ask the service for the history at any time |
| Answers | One complete answer for each message. Streaming is not in this revision |
| Attachments | A message can have image files and audio files. The client sends them in the body of the send, as base64. The service gives them back with a separate request. A service says which kinds it accepts in the answer to the read of the history (section 6.2). A service that says nothing accepts text only |
| Discovery | The service declares the interface in its `Service.Api` (section 3). There is no discovery endpoint |
| Version | The tag has no version. The interface only grows with new optional fields (section 11) |

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
- The service must answer a request that has a body with a `Content-Length` header. The
  service can also accept chunked bodies.
- The client sends `Content-Type: application/json` on each request that has a body. The
  service must read the body as JSON in UTF-8 and must not require the `charset` parameter.
- The service must set `Content-Type: application/json` on each answer that has a body.
  The service must use UTF-8.
- The client and the service must ignore JSON fields that they do not know. They must
  ignore HTTP headers that they do not know.
- The service must ignore query parameters that it does not know.
- The service must reply with status 404 and `{"error": "not_found"}` to a path that this
  document does not define. For the path `/chat/messages`, the service must reply with
  status 405 and `{"error": "method_not_allowed"}` to a method that is not GET or POST. For a path of section 6.4, the same reply is for a method that is not GET. The
  405 answer must have an `Allow: GET, POST` header.

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
| `kind` | string | `image` or `audio`. The service sets it from `mime` |
| `mime` | string | The media type, for example `image/jpeg` |
| `name` | string, optional | The name of the file, for the user to read. The service must not use it as a path |
| `size` | integer | The size of the file in bytes, before the base64 coding |

The data of the file is not in a message. The client reads it with section 6.4.

An attachment has an index in its message. The first attachment has index 0. The
`attachments` list of a message must not change after the service adds the message.

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
line break). The client must send `attachments` only if the service says that it accepts
the kind (section 6.2). Example:

```
{"expect": 4, "text": "What is this?",
 "attachments": [{"mime": "image/jpeg", "name": "tree.jpg", "data": "/9j/4AAQ..."}]}
```

The service must check the request in this order and stop at the first failure:

| Step | Check | Failure |
|---|---|---|
| 1 | The body is valid JSON, an object, with `expect` and `text` of the correct types. `expect` is an integer of 0 or more (not a float, not a string, not a boolean). `text` is a string, and it is not empty unless `attachments` has an item. `attachments`, if present, is a list of 1 to 4 items. Each item has a `mime` string and a `data` string that is valid base64 | 400 `bad_request` |
| 2 | The size of the body, of `text` and of each file is in the limit of the service (section 7) | 400 `bad_request` |
| 2a | Each `mime` is a type that the service accepts | 415 `unsupported_media` |
| 3 | The service has no other send in progress | 503 `busy` |
| 4 | `expect` is equal to `count` | 409 `out_of_sync` |
| 5 | The history has room for two more messages | 413 `history_full` |

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

`messages` has the two messages that this send added, in order. The user message has `attachments` with the description of each file (section 5.1), without `data`. `count` is the `count`
after the send.

If the service fails to make the answer, it must change nothing. It must not change
`count` and must not keep the user message. It must reply with status 500 and
`{"error": "service_error"}`. The `message` field is optional.

If the checks 3 to 5 fail, the service must change nothing.

### 6.2 Read the history

```
GET /chat/messages?from=4
```

| Parameter | Type | Rule |
|---|---|---|
| `from` | integer, 0 or more | Optional. The first `seq` that the client wants. Default: 0 |

`from` is valid only if it is a string of one or more ASCII digits (`0` to `9`). The value
has no sign, no space, no decimal point and no other character. The service must
reply with status 400 and `bad_request` to a value that is not valid. This includes
digits that are not ASCII, such as `²`. The service must not close the connection.

If `from` is more than `count`, the service must reply with status 400 and `bad_request`.
If `from` is equal to `count`, the service replies with status 200 and an empty list.

The service replies with status 200:

```
{"count": 6, "accepts": ["image", "audio"], "messages": [{"seq": 4, ...}, {"seq": 5, ...}]}
```

`accepts` is optional. It is the list of the kinds of attachment that the service accepts
in a send: `image`, `audio`, or both. If `accepts` is absent or empty, the service accepts
text only, and the client must not send attachments. The service must put the same
`accepts` in each answer, for the whole life of the instance. A message in `messages` can
have `attachments` (section 5.1).

`messages` has the messages with `seq` equal to or more than `from`, in order. If the
history is empty, the reply is `{"count": 0, "messages": []}`.

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
messages after that time. The client then reads them at the next read of the history. The
client waits 30 seconds for each request (`TunnelHttp`). A service that makes an answer in
more time than this has to use the rules of section 7.

### 6.4 Read an attachment

```
GET /chat/messages/4/attachments/0
```

The first number is `seq`. The second number is the index of the attachment in its
message. Each number is valid only if it is a string of one or more ASCII digits.

The service replies with status 200. The body is the bytes of the file, without a change.
`Content-Type` is the `mime` of the attachment. `Content-Length` is `size`.

- If a number is not valid, the service replies with status 400 `bad_request`.
- If the message or the attachment does not exist, the service replies with status 404
  `not_found`.
- The service must answer this request also when a send is in progress.

The client can keep the bytes in memory. It must not write them to the Celaut database.

## 7. Limits

| Limit | Value |
|---|---|
| Time to answer a send | The service must answer a send in less than 30 seconds, or use the rule below. If it needs more time, the client sees a lost connection (section 6.3) and the user must send the message again after the answer is in the history |
| Size of `text` | The service must accept `text` of 16 384 bytes (UTF-8) or less. The service can accept more. It must reply with status 400 to a `text` that is above its own limit |
| Size of a request body | The service must accept a body of 32 768 bytes or less, and, if it accepts attachments, a body of 24 MiB (25 165 824 bytes) or less. It can accept more |
| Size of a file | A service that accepts attachments must accept a file of 4 MiB (4 194 304 bytes) or less. It can accept more. It must reply with status 400 to a file above its own limit |
| Number of files | A service that accepts attachments must accept 4 files in one send |
| Size of the history | The service decides. When the history has no room for two more messages, the service replies with status 413 `history_full` |

A service that cannot make an answer in 30 seconds must reply with status 503 `busy` to
the next send until the answer is in the history. This is the rule of step 3 of
section 6.1.

## 8. Errors

| Status | `error` | Meaning |
|---|---|---|
| 400 | `bad_request` | The body is not valid JSON, a field is missing or has the wrong type, `text` is empty (and there is no attachment) or too long, a file is too big or is not valid base64, there are more than 4 files, `expect` is less than 0, or `from` is not valid or is more than `count` |
| 404 | `not_found` | The path is not defined in this document, or the message or the attachment of section 6.4 does not exist |
| 405 | `method_not_allowed` | The method is not GET or POST for `/chat/messages`, or not GET for a path of section 6.4 |
| 409 | `out_of_sync` | `expect` is not equal to `count`. The body has `count` |
| 413 | `history_full` | The service cannot keep more messages. The client tells the user to start a new instance |
| 415 | `unsupported_media` | A `mime` of a file is not accepted. The service changed nothing |
| 500 | `service_error` | The service failed to make the answer. The service changed nothing |
| 503 | `busy` | The service makes an answer for a message already. The client tries again later |

An error body is `{"error": "<name>", "message": "<text for the user>"}`. `message` is
optional. If `message` is present, it is text that the client can show to the user. The
409 body also has `count`, for example `{"error": "out_of_sync", "count": 6}`.

A service must not use a status that is not in this table for a request that this
document defines. A client treats a status that is not in this table as an error that it
does not know (`ChatErrorKind.other`).

A service must keep only one send in progress. It must never change `count` for a send that
failed.

## 9. Client rules

These rules cover the protocol only. The screens, the cost, the stop of an instance and the
storage of the app are not part of this document ([ui-chat-first.md](ui-chat-first.md)).

- The client must send one request at a time. A new send waits for the end of the send
  before it.
- The client must not send a message that has an empty `text` and no attachment.
- The client must send `attachments` only if the last read of the history had the kind in `accepts` (section 6.2).
- The client must read the history from 0 when it opens a conversation that it does not
  have.
- A service can need some seconds to listen after the start of its instance. Until then, a
  request fails to connect. The client can read the history again until the service
  answers. It must not send a message before a read of the history works.
- A client that gets a `seq` that is not the next one (a gap) must treat the answer as an
  error. A client skips a message that it has already.
- The client must use HTTP keep-alive and open one connection for the whole conversation.
  Each connection through the tunnel is one `ServiceTunnel` stream, and the node charges
  for each stream (`TUNNEL_OPEN_MU`).
- The client must follow section 6.3 after a lost connection.

## 10. Conformance

A service follows revision 3 if it obeys each "must" and "must not" of sections 3 to 8.

### 10.1 Tests

Run these tests on a new instance. `$B` is the base URL of the tunnel, for example
`http://127.0.0.1:PORT`. Each test gives the expected result.

| # | Request | Expected result |
|---|---|---|
| 1 | `GET /chat/messages` | 200, `{"count":0,"messages":[]}` |
| 2 | `GET /chat/messages?from=0` | 200, same body as test 1 |
| 3 | `GET /chat/messages?from=1` | 400 `bad_request` |
| 4 | `GET /chat/messages?from=²` | 400 `bad_request`, and the connection stays open |
| 5 | `GET /chat/messages?from=-1`, `?from=1.0`, `?from=` , `?from=a` | 400 `bad_request` for each |
| 6 | `POST` with body `{"expect":0,"text":"one"}` | 200, `count` 2, two messages: `seq` 0 `user` "one", `seq` 1 `assistant` |
| 7 | `POST` with body `{"expect":0,"text":"again"}` | 409 `out_of_sync`, `count` 2. A `GET` after it still has `count` 2 |
| 8 | `POST` with body `{"expect":2,"text":"two"}` | 200, `count` 4, `seq` 2 and 3 |
| 9 | `GET /chat/messages?from=2` | 200, `count` 4, two messages with `seq` 2 and 3 |
| 10 | `GET /chat/messages?from=4` | 200, `count` 4, `"messages":[]` |
| 11 | `POST` with body `not json` | 400 `bad_request` |
| 12 | `POST` with bodies `{}`, `{"expect":4}`, `{"text":"x"}`, `{"expect":"4","text":"x"}`, `{"expect":4.0,"text":"x"}`, `{"expect":-1,"text":"x"}`, `{"expect":4,"text":""}`, `{"expect":4,"text":5}` | 400 `bad_request` for each. `count` stays 4 |
| 13 | `POST` with body `{"expect":4,"text":"  x  é ✓"}` | 200. The `text` of the user message is `  x  é ✓`, without a change |
| 14 | `POST` with `text` of 16 384 bytes | 200 |
| 15 | `PUT /chat/messages`, then `GET /chat/other` | 405 with `Allow: GET, POST`, then 404 |
| 16 | `POST` with an unknown field, for example `{"expect":N,"text":"x","extra":1}` | 200. The service ignores `extra` |
| 17 | Five requests on one keep-alive connection | All five get an answer on the same connection |
| 18 | While a send takes time (a slow service): `GET /chat/messages`, and a second `POST` | The `GET` gets 200, without the message in progress. The `POST` gets 503 `busy` |
| 19 | `GET /chat/messages` on a service that accepts attachments | `accepts` is a list that has `image`, `audio` or both. A service that accepts text only has no `accepts` or an empty list |
| 20 | `POST` with `{"expect":N,"text":"","attachments":[{"mime":"image/png","data":"<a valid PNG in base64>"}]}` (only if `accepts` has `image`) | 200. The user message has `attachments` `[{"kind":"image","mime":"image/png","size":<bytes>}]` and no `data` |
| 21 | `GET /chat/messages/<seq>/attachments/0` for the message of test 20 | 200. The body is the same bytes. `Content-Type: image/png`. `Content-Length` is `size` |
| 22 | `GET /chat/messages/<seq>/attachments/1`, `/chat/messages/9999/attachments/0`, `/chat/messages/x/attachments/0` | 404, 404, 400 |
| 23 | `POST` with an attachment of `"mime":"application/pdf"` | 415 `unsupported_media`. `count` does not change |
| 24 | `POST` with `"data":"not base64!"`, with 5 files, with `"text":""` and no `attachments`, and with a file of 4 MiB + 1 byte, in four requests | 400 `bad_request` for each. `count` does not change |
| 25 | `POST` with 4 files of 4 MiB each (only if `accepts` has the kind) | 200 |
| 26 | `POST` with an attachment to a service that accepts text only | 400 `bad_request` or 415 `unsupported_media`. `count` does not change |

Test 18 applies to a service that takes time to answer. The echo service can skip it.

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
| 3 | 2026-10-22 | Attachments: `attachments` in a message and in a send, `accepts` in the read of the history, the read of an attachment (section 6.4), the status 415, the limits for files, and the tests 19 to 26. A service that does not know them stays valid for text only |
| 2 | 2026-10-22 | The text is a specification in ASD-STE100, with requirement words. New rules for the service: transport (section 4), the order of the checks (section 6.1), the strict value of `from`, the status 404, 405 and 500, the limits (section 7), and the conformance tests (section 10). The service must add the two messages of a send at the same time. The rules for the app (leave the screen, stop, cost, storage) leave this document |
