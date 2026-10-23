# Chat-first UI (2026-10-21)

Josemi asked for a home screen like Telegram or WhatsApp: each conversation is an instance
of a service that follows the chat convention ([chat.md](chat.md)), and the rest of the app
(wallet, compute, nodes, services, settings) is one level down. This note describes the
screens of that UI. It follows [ui.md](ui.md) and [chat.md](chat.md); section 4 has the
decisions of Josemi on this UI, section 5 what it changes in the older notes, and section 7
the messages and the files of a conversation.

## 1. Research: how the two messengers organise the app

Both apps were checked on Android in October 2026.

| Part | Telegram | WhatsApp |
|---|---|---|
| Home | The chat list, with folder tabs on top | The chat list, with filter chips (All, Unread, Groups) |
| Other places | Before the update of February 2026: a left drawer with the account on top (photo, name, number), then Contacts, Calls, Saved Messages, Settings. From that update: a bottom bar with Chats, Contacts, Settings, Profile | A bottom bar with Chats, Updates, Communities, Calls. ⋮ on the chat list has Settings, Linked devices, Starred |
| New chat | A pencil button. It opens the contacts, with New group and New channel on top | A button at the bottom right. It opens "Select contact", with New group and New contact on top |
| Chat bar | The photo, the name and a status line ("online", "last seen"). A tap opens the info page of the contact, with its actions. ⋮ has Mute, Search, Clear history, Delete | The same: name and status; a tap opens "Contact info"; ⋮ has View contact, Search, Mute, More |
| Long press on a chat | A selection mode, with Pin, Mute, Archive, Delete in the bar | The same, with Pin, Delete, Mute, Archive |
| Archived chats | A row on top of the list | A row on top of the list |
| Unread | A count on the right of the row | The same |
| Empty list | A picture, one sentence, and the new-chat button | The same |

**Choice: a bottom bar, as WhatsApp and Telegram (from February 2026) have it, with ⋮ on the
conversation (decision of Josemi, 2026-10-21: "better a bottom bar").** The bar has four
tabs: Chats, Wallet, Compute, Settings. Each tab holds the places of its kind as rows, so
every other place of the app is one tap under a tab. The conversation screen follows both
apps: name and status in the bar, a tap on it opens the info page, and ⋮ has the actions.

Not taken from the messengers:

- **Unread counts.** A service answers only to a message of the user, while the
  conversation is open (one answer for each message, no streaming, [chat.md](chat.md)). There
  is nothing unread.
- **Archived chats.** An instance costs money while it runs, so it is not hidden: the user
  stops it. The instances without a chat slot have their own page ("Other instances"), which
  is the nearest thing.
- **Selection mode on a long press.** One instance at a time is enough: a long press opens a
  sheet with the actions of that row.

## 2. Screen map

The home screen is a bottom bar with four tabs (`HomeTabs`,
`app/lib/ui/celaut/home_tabs.dart`). Each tab keeps its state while another one shows.
Back on another tab goes to Chats. The conversation, the info page of an instance, the page
of the wallet and the pages under a tab open over the bar.

| Tab | What it holds | Code |
|---|---|---|
| Chats | The instances with a chat slot: the running ones, newest first, then the stopped ones (hidden by default, see below). The pencil button opens "New conversation"; only this tab has it | `ChatsScreen`, `InstanceList` (`chats_screen.dart`, `instance_list.dart`) |
| Wallet | The overview of the wallet: balance, Send, Receive, More, the wallet row (it opens the page of the wallet), then "Deposit to a node". With no wallet: create or restore | `WalletsOverviewScreen`, `DepositScreen` |
| Compute | The compute view of [ui.md](ui.md), section 2: the running instances with Stop, "Run a service", the card of state (nodes, credit on the nodes, ERG of the wallet). Under it: Nodes, Services, Other instances | `ComputeHomeScreen` |
| Settings | The settings of the app in three sections (2026-10-23): Ergo (the wallet, the Ergo network, the address book, the remote previews), Compute (nodes, deposit, automatic top-up, Tor, environment variables, node check, Celaut service) and General (security, display, the switch of the home screen, About) | `SettingsScreen` |

| Place | Where | What it holds | Code |
|---|---|---|---|
| New conversation | Chats, pencil button | The skills of the catalog (a skill opens its ranked services), the service files of the user, the import of a file | `RunServiceScreen` with the title "New conversation" |
| Conversation | Chats, a row | Bubbles, with images and files (section 7); the bar has the name of the service and "state · node · cost so far"; ⋮ has Info and Stop | `ChatScreen` |
| Instance info | The bar of a conversation, ⋮, a long press, a tap on a stopped row | State, node address, peer id of the node, service id, chat slot, start time, cost so far (or the refund at the stop). Stop, or Delete for a stopped instance | `InstanceInfoScreen` |
| Page of the wallet | Wallet, the wallet row | Balance, Send, Receive, activity, the tools and the settings of the wallet | `DashboardScreen` (wallet page) |
| Deposit to a node | Wallet | The deposit screen | `DepositScreen` |
| Nodes | Compute | The node list with its availability; add a node by address or QR code ("connect to a new peer") | `KnownNodesScreen` |
| Services | Compute | The same picker as "New conversation": the catalog, the service files and the import. The transfer of a service that a node does not have stays in the sheet of a failed launch | `RunServiceScreen` |
| Other instances | Compute | The instances without a chat slot. A row opens the info page | `OtherInstancesScreen` |
| Network and Tor | Settings | The network route ([network.md](network.md)) | `NetworkScreen` |
| About | Settings | The version and the update check | `AboutPage` |

A row of the list has the robot of the instance, its name, the cost so far, the last
message that the app saw in this run (or a note that it saw none), and "state · node". The
name is the name of the skill or the service file at the start; the database keeps it with
the instance (`InstanceRecord.name`). An instance of an earlier version has no name: the row
shows the short service id.

A filter hides the stopped instances, on Chats and on Other instances (Josemi, 2026-10-23).
It is on by default. Under the rows, "Show N stopped instances" shows them, and "Hide stopped
instances" hides them again; the app keeps the choice (`celaut_hide_stopped_v1`). A shown
stopped instance has Delete, as before. A stopped instance stays in the database while it is
hidden.

The robot (Josemi, 2026-10-23) stands for the instance as a photo stands for a contact: a
service has no picture of its own, so every instance gets one. It comes from the instance id
(FNV-1a of the id picks the head, the eyes, the mouth, the antenna and one of eight hues), so
it stays the same after a restart. The app draws it with paths (`robot_avatar.dart`): no
image file, no network, no licence of a third party.

The user can rename an instance (Josemi, 2026-10-23): Rename on the long press of a row, or
the pencil on its info page, running or stopped. The new name is local: the app keeps it in
the Celaut database (`InstanceRecord.alias`, `celaut_rename_instance`, at most 60
characters) and never sends it to the node. The list, the conversation and the info page
show it before the name of the start. An empty name removes it.

The states of a row:

| State | When |
|---|---|
| Checking | The app asks the node (`celautInstanceStatus`) |
| Starting | The instance started in this run, and its service did not answer yet |
| Running | The node reports the instance |
| Not answering | The node does not answer, or does not report the instance. The info page says why |
| Stopped | The instance stopped. The row stays, after a restart too, until the user deletes it |

The list asks the nodes for its running instances when it opens, when the user comes back
to it (from a page or from another tab), and on a pull. It does not poll. A stopped instance
is not asked for.

## 3. Flows

- **New conversation.** Pencil → "New conversation" → a skill → its services, best first →
  Run → "Run <name>?" with the node and the start cost → the PIN or fingerprint if the wallet
  is locked → the launch → back to the list and into the conversation, which says that the
  service starts (`ChatClient.syncWhenStarted`). Back from the conversation is the list.
  "Services" and "Run a service" in the Compute tab end the same way, on the Chats tab. A
  service without a chat slot starts, and a message says that it is in Compute, under
  "Other instances".
- **Open a conversation again.** A tap on a row opens the local port of the chat slot and
  reads the history from 0 ([chat.md](chat.md), section 6.2). This works after the lock of the
  app closed the screen, and after a restart of the app. The screen shows at once, with the
  name of the instance and a spinner, while the port opens: a far node, or Tor, can take
  seconds. If the port does not open, the screen closes and the list says why.
- **Leave.** Back goes to the list at once. The instance runs on, the node keeps charging,
  and the row shows its cost.
- **Stop.** From ⋮ in the conversation, from its info page, from a long press in the list,
  or from the Compute tab. The app asks "Stop <name>?", then needs the wallet open. If the
  node does not answer, the app says why and the row stays as it was. After the stop the
  database keeps the instance as stopped, with the refund (`InstanceRecord.stopped_at`,
  `refund_mu`), and the row shows "Stopped" with the last message.
- **Delete.** A long press on a stopped row, or its info page, offers Delete. The app asks
  "Delete <name>?", then takes the instance out of the database (`celaut_forget_instance`).
  This is the only way an instance leaves the list. A row that is running, starting or not
  answering has no Delete, and `celaut_forget_instance` refuses an instance that was not
  stopped.

The last message of each conversation and the starting instances are in memory only
(`ConversationNotes`, `app/lib/celaut/conversations.dart`). The app writes no message to the
Celaut database.

The setting "Chats home" (Settings, General; key `celaut_compute_home_v1`) chooses the
first screen: the tabs, on Chats (on, the default), or the wallets list (off). The compute
view is the Compute tab, not a first screen.

## 4. Decisions of Josemi (2026-10-21)

| Question | Decision |
|---|---|
| A drawer or a bottom bar | A bottom bar: Chats, Wallet, Compute, Settings (section 2). Every place of the first build of this UI is under a tab |
| When the list checks the nodes | Only when it opens, when the user comes back to it, and on a pull. No polling |
| Forget an instance whose node does not answer | No. The app keeps every instance and its token until the user deletes it, and only a stopped instance can be deleted (section 3) |

## 5. Changed decisions (for Josemi to confirm)

| Where | Before | In this UI |
|---|---|---|
| The conversation screen: leaving it (decision of 2026-10-14, first written in `chat.md` revision 1; since revision 2 of `chat.md` the rules for the app are in this file and not there) | The app asks "Stop the instance" or "Leave it running" | Back goes to the list without a question. The instance runs on and stays in the list. Stop is in ⋮, the info page and the long press |
| [ui.md](ui.md), section 2: the home screen (decision of 2026-10-16) | The compute view: running instances, "Run a service", the card of state | The Chats tab. The compute view is unchanged and is the Compute tab |
| [ui.md](ui.md), section 2: "Run a service" | A button of the home screen | The pencil button ("New conversation") and "Services" in the Compute tab; the Compute tab keeps its button. The confirmation is the same |
| The Celaut database | An instance has no name, and leaves the database at its stop | An instance keeps the name of its skill or service file (`InstanceRecord.name`), and stays after its stop, as stopped, until the user deletes it |

## 6. Open questions

1. An instance that its node no longer knows (for example after a restart of the node)
   cannot be stopped, so it cannot be deleted either. Should Stop mark such an instance
   stopped when the node answers that the token is unknown?

## 7. Messages and files

The screen is `ChatScreen`. The protocol is in [chat.md](chat.md). The picker is in
`app/lib/celaut/attachment_picker.dart` (`file_picker`, the system document picker).

| Part | What the user sees |
|---|---|
| Attach button | It shows only if the service announced `accepts` in the history read. Before the picker opens, the app reads the history again to check `accepts` |
| Picker | It offers only JPEG, PNG, MP3 and WAV. At most 4 files, of 4 MiB each |
| Chips | A picked file shows as a chip above the field |
| Image in a bubble | The image shows inside the bubble |
| Audio in a bubble | The bubble shows the name of the file. A tap hands the file to the share sheet of the system. The app has no player |
| Files in memory | The app keeps the files in memory only. It writes no file to the storage and no message to the Celaut database |
| List of conversations | A message with only a file shows a preview, "Photo" or "Audio" |

Flows:

- **Send.** The message shows at once as a paler bubble with "Sending…". The field is free
  for the next message.
- **Wait for the answer.** Three pulsing dots show that the service answers. After 5
  seconds, a counter shows "Still working… N s".
- **A send fails.** The text and the files come back to the field. The app never sends a
  message again by itself.
- **A slow service.** If the service takes more than 30 seconds, the app waits. It reads
  the history every 5 seconds, for up to 3 minutes. After that, it says that the service
  does not answer.
