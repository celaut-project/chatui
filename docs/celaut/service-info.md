# What a service says about itself (2026-10-22)

The app shows the details of a service and checks, before it starts one, that its interface
is the chat convention of Chatui ([chat.md](chat.md)). Both need the `Service` message of the
service (`celaut.proto`), and most of that message is the filesystem of the container:
hundreds of megabytes (`claude-code.bee` has 536 MB), which the app never uses.

## 1. Reading the Service as a stream

`celaut-client/src/service_info.rs` does not decode the Service as one message. It walks the
protobuf fields of the Service part of the Buffers (`GetService` of a node, or a `.bee` file
through `package::read`), and:

- skips the bytes of `Container.filesystem` without keeping them (the size is kept);
- decodes only the small parts, each as its own message: `prose`, `Container.architecture`,
  `init`, `resources`, `config_declaration`, `node_protocol_stack`, the environment
  variables, `Service.api`, each `network` and each `possible_environment_workload`;
- keeps the memory at one Buffer (up to 1 MiB) and the parts that it kept, whatever the size of
  the service. A part larger than 256 KiB is skipped and counted, never taken for absent: a
  workload that large (it carries a whole service) is counted in `workloads_skipped`, and any
  other part in `parts_skipped`. If the skipped part is the interface, the chat check is
  "unknown", not "unsupported" (`api_skipped`). A list of more than 256 items is refused.
- bounds a node that misbehaves: each Buffer counts at least 16 bytes against the limit, so a
  stream of empty Buffers reaches it, and the reader gives up if no Buffer comes in 30 seconds.

The fields come in the order of their numbers, so the interface and the networks (3 and 4) are
after the container (2), which holds the filesystem. The reader must read the whole Service
part, but it never keeps the filesystem. A file of 536 MB takes about 1.5 seconds.

From a node, the node sends the whole service. The app stops after 128 MiB and gives what came
before the filesystem (the prose and the architecture) with `truncated` set. What is after it
is then **unknown, not empty**: the screen shows no "no variables" or "no port" for a service
that was cut, and the chat check is "unknown", not "unsupported". A service that the user
loaded as a file is always read in full from the library.

## 2. What the app shows

`ServiceInfoScreen` (`app/lib/ui/celaut/service_info_screen.dart`), with a banner on top:

| Banner | When |
|---|---|
| Follows the chat convention (with the port) | a port has `tcp`, then `http`, and `chat` above it |
| Chatui does not support its interface | the interface is known and no port follows the convention, or there is no interface |
| The interface could not be read | the service was too large to read from a node, or its interface was too large to decode |

Then, in cards: **About** (prose, architecture, the executable that the node starts, the
configuration file, the size of the filesystem), **Resources** (at the start and at most: cores,
memory, disk, the speed of one core), **Interface** (each port with its stack from bottom to top,
`tcp → http → chat`, a mark on the chat port, the prices per call), **Networks** (the domains that
the service declares to connect to: the names, the prose, the parameters, the protocols of the
peers, and `*` as every address), **Environment variables**, and **Other** (the protocols that it
expects from the node, and the instances that it can start).

It opens from the confirmation of a launch ("Service details"), from the info page of an
instance, and from the alert below.

## 3. The check before a launch

After the quotes (a quote is free) and before the first start, `RunServiceSection` reads the
service once and:

1. If the interface is **not** the chat convention, an alert says that Chatui does not support
   it and that, if run, the service shows in Compute and there is no conversation. The user runs
   it anyway, or cancels. Details opens the screen above with the info that was read, so the
   service is not read twice.
2. Then the environment variables ([env-variables.md](env-variables.md)), from the same read.

If the app cannot read the service (an error, one too large to read from a node, or an interface
too large to decode), it does not say "unsupported": it says that it cannot tell, and the user
runs it anyway or cancels.

The convention is one function for the service and for the instance: `api_chat_ports(api)` in
`session.rs` (a slot with `tcp`, `http` and `chat` above it). `chat_slots(instance)` adds that
the instance has the port, because `ServiceTunnel` accepts only the ports of an instance.

## 4. Code

| Where | What |
|---|---|
| `rust/crates/celaut-client/src/service_info.rs` | The stream reader, `ServiceInfo`, `read_service_info`, `read_service_info_of_file` |
| `rust/crates/celaut-client/src/session.rs` | `api_chat_ports`, `chat_slots` |
| `rust/crates/wallet-ffi/src/api/celaut_service_info.rs` | `celaut_service_info` and the views for the screen |
| `app/lib/ui/celaut/service_info_screen.dart` | The details and the banner |
| `app/lib/ui/celaut/run_service_section.dart` | The check and the alert before a launch |

## 5. Checks

- `service_info.rs`: every part is read after a filesystem of 300 000 bytes in chunks of 1 byte
  to 1 MiB, with a block marker in the middle; a filesystem of 40 MiB does not grow the buffer;
  the limit gives what came first and says so; a workload with a whole service is counted and not
  read; a cut service, a false length, a group wire type and a prose that is not UTF-8 are
  errors, not panics; an interface of more than 256 KiB is counted and is not "unsupported"; a
  stream of empty Buffers reaches the limit and a silent node ends the read after 30 seconds
  (these two came from the review of the first version). `CELAUT_TEST_BEE=<file> cargo test -p celaut-client --lib real_package --
  --ignored --nocapture` reads a real package: `claude-code.bee` gives the architecture
  `linux/arm64`, 535 923 139 bytes of filesystem, one port with the chat convention (8080), one
  network and no variable, in 1.5 seconds.
- `celaut_service_info.rs`: the view has every part and the chat port; a known interface without
  the convention is unsupported and a cut one is unknown; the cores with a missing or zero period.
- `app/test`: `celaut_service_info_test.dart` (the details, the three banners, the empty and the
  cut service, the loader and its retry, info that is not read again, the info page of an
  instance) and `celaut_run_section_test.dart` (the alert: cancel, run anyway then the
  variables, details without a second read, a cut service is not "unsupported", a supported
  interface has no alert).
- Not checked: a service on a real node with a large filesystem through `GetService`, and a phone.

## 6. Open items

- A service of more than 128 MiB that is on a node and not in the library is described only by
  its prose and its architecture. The user can load the file.
- The check looks at the interface that the service declares. A service whose chat slot is
  declared and does not answer is not found here: the conversation shows that.
