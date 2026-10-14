# Chat convention (HTTP with JSON)

This note defines the "chat" convention for M4. A service that follows it can be used
from the conversation screen of chatui. The first service is an echo service. A later
LLM service follows the same rules (`docs/celaut-plan.md`, section 7, decision 3).

The convention is small on purpose. HTTP and JSON are the only parts that the client
and the service must share.

## 1. Decisions

| Topic | Decision (Josemi, 2026-10-14) |
|---|---|
| History | The service keeps the history. The client does not send it with each message |
| Session | One session for each instance. The instance is the conversation. When the instance stops, the conversation ends |
| Synchronization | Each message has a number. The client can ask the service for the history at any time |
| Answers | One complete answer for each message. Streaming is not in version 1 |
| Discovery | The service declares the convention in its interface (section 2). There is no discovery endpoint |
| Version | The tag has no version. The convention only grows with new optional fields (section 6) |
| Storage in the app | The history is only in memory. The app writes no message to the Celaut database |
| Leaving the screen | The app asks the user to stop the instance or to leave it running (section 5) |

## 2. Declaration in the service interface

A service follows the convention if its `Service.Api` has one `Slot` with these values
(`nodo:protos/celaut.proto`, `Service.Api.Slot`):

| Field | Value |
|---|---|
| `transport.tags` | contains `tcp` |
| `protocol_stack` | contains one `Protocol` with `tags` that contain `http`, above one with `tags` that contain `chat` |

The client reads the interface before it starts the service. It uses the `port` of this
slot for `ServiceTunnel`. If there is no such slot, the client does not show the service
as a chat service. If a service has more than one such slot, the client uses the first.

The `prose` of the `chat` protocol can describe the service for the user. The client
does not parse it.

## 3. Messages

A message has these fields:

| Field | Type | Meaning |
|---|---|---|
| `seq` | integer | The position of the message in the conversation. The first message has `seq` 0. User and assistant messages share the same count |
| `role` | string | `user` or `assistant` |
| `text` | string | The text, in UTF-8 |

The service holds `count`: the number of messages in the conversation. The next message
gets `seq` equal to `count`.

All bodies are JSON with `Content-Type: application/json`. A client and a service ignore
fields that they do not know.

## 4. Requests

### 4.1 Send a message

```
POST /chat/messages
{"expect": 4, "text": "Hello"}
```

`expect` is the `count` that the client believes the service has.

If `expect` is equal to the `count` of the service, the service:

1. adds the user message with `seq` equal to `expect`;
2. makes the answer, and adds it with the next `seq`;
3. replies with status 200:

```
{"count": 6,
 "messages": [{"seq": 4, "role": "user", "text": "Hello"},
              {"seq": 5, "role": "assistant", "text": "Hello"}]}
```

If `expect` is not equal to `count`, the service changes nothing. It replies with status
409 and `{"error": "out_of_sync", "count": 6}`. The client then reads the history from
its own `count` (section 4.2) and sends the message again if it is still not in it.

A client that loses the connection after a send does not know if the service got the
message. It must not send the message again at once. It reads the history first
(section 4.2). If the message is there, the send worked.

### 4.2 Read the history

```
GET /chat/messages?from=4
```

The service replies with status 200 and `{"count": 6, "messages": [...]}`. `messages`
has the messages with `seq` of 4 or more, in order. Without `from`, the service replies
with all the messages. If `from` is more than `count`, the service replies with status
400.

The client uses this request to start the screen again when the instance is still
running, and to repair a lost answer.

### 4.3 Errors

| Status | `error` | Meaning |
|---|---|---|
| 400 | `bad_request` | The body is not valid JSON, `text` is missing, or `from` is not valid |
| 409 | `out_of_sync` | `expect` is not equal to `count`. The body has `count` |
| 413 | `history_full` | The service cannot keep more messages. The client tells the user to start a new instance |
| 503 | `busy` | The service makes an answer for a message already. The client tries again later |

An error body is `{"error": "<name>", "message": "<text for the user>"}`. `message` is
optional.

A service can keep only one send in progress. It never changes `count` for a send that
failed.

## 5. Client behavior

- The client keeps the history in memory only. It writes no message to the Celaut
  database. The app keeps the instance and its token as before (`docs/celaut/ui.md`).
- When the user opens a running instance, the client reads the history from 0.
- When the user leaves the screen, the client asks: "Stop the instance" or "Leave it
  running". "Stop" calls `StopService` and the node refunds the balance of the instance.
  The conversation is lost. "Leave it running" keeps the instance, and the node continues
  to charge for it. The cost so far stays on the instance list.
- The screen shows the cost so far while the user talks to the service (the charge of
  the start less the balance that the instance still has).
- Each TCP connection through the local port is one `ServiceTunnel` stream and costs
  `TUNNEL_OPEN_MU`. The client uses HTTP keep-alive and opens one connection for the
  whole conversation.
- Start and stop need an open full wallet (`docs/celaut/ui.md`, section 3).

## 6. Changes to the convention

The tag is `chat` and it has no version. A change must not break a service or a client
that follows this note. A new field is optional, and a client or service that does not
know it ignores it.

Streaming is a future change. It will add an optional way to read a partial answer, and a
service without it stays valid.

## 7. Echo service

The echo service is the check of M4. It follows this note, and the `text` of each
answer is the `text` of the message that it answers. It keeps the messages in a list in
memory.

Check, on a node that we run:

1. Start the echo service from the app.
2. Send "one" and "two". The screen shows four messages.
3. Stop the connection of the app (flight mode) in the middle of a send, and start it
   again. The screen reads the history and shows each message once.
4. Leave the screen and choose "Leave it running". Open the instance again. The screen
   shows the four messages.
5. Stop the instance. The node gives the refund.
