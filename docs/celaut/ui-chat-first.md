# Chat-first UI (2026-10-21)

Josemi asked for a home screen like Telegram or WhatsApp: each conversation is an instance
of a service that follows the chat convention ([chat.md](chat.md)), and the rest of the app
(wallet, compute, nodes, services, settings) is in a secondary menu. This note describes the
screens of that UI. It follows [ui.md](ui.md) and [chat.md](chat.md); section 4 lists what it
changes in them, for Josemi to confirm.

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

**Choice: a left drawer, as Telegram had it, with ⋮ on the conversation.** A bottom bar
holds three to five places of the same rank. Josemi asked for a *secondary* menu, and the
app has nine such places: a bottom bar would put the wallet and the nodes at the rank of the
conversations, and would still need a menu for the rest. A drawer keeps one main screen
(the conversations) and lists every other place in one column, with the wallet on top, as
the account of Telegram. The conversation screen follows both apps: name and status in the
bar, a tap on it opens the info page, and ⋮ has the actions.

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

| Place | What it holds | Code |
|---|---|---|
| Home: conversations | The instances with a chat slot, newest first, then the ones that stopped in this run. ☰ opens the drawer; the pencil button opens "New conversation" | `ChatsScreen`, `InstanceList` (`app/lib/ui/celaut/chats_screen.dart`, `instance_list.dart`) |
| New conversation | The skills of the catalog (a skill opens its ranked services), the service files of the user, the import of a file | `RunServiceScreen` with the title "New conversation" |
| Conversation | Bubbles; the bar has the name of the service and "state · node · cost so far"; ⋮ has Info and Stop | `ChatScreen` |
| Instance info | State, node address, peer id of the node, service id, chat slot, start time, cost so far (or the refund at the stop), Stop | `InstanceInfoScreen` |
| Drawer: head | The Celaut mark and the ERG of the wallet. A tap opens the wallet | `ChatsDrawer` |
| Drawer: Wallet | The page of the wallet: balance, Send, Receive, activity, the tools and the settings of the wallet. With no wallet: create or restore | `DashboardScreen` (wallet page) |
| Drawer: Deposit to a node | The deposit screen | `DepositScreen` |
| Drawer: Compute and credit | The compute view of [ui.md](ui.md), section 2: the running instances with Stop, "Run a service", and the card of state (nodes, credit on the nodes, ERG of the wallet) | `ComputeHomeScreen` |
| Drawer: Nodes | The node list with its availability; add a node by address or QR code ("connect to a new peer") | `KnownNodesScreen` |
| Drawer: Services | The same picker as "New conversation": the catalog, the service files and the import. The transfer of a service that a node does not have stays in the sheet of a failed launch | `RunServiceScreen` |
| Drawer: Other instances | The instances without a chat slot. A row opens the info page | `OtherInstancesScreen` |
| Drawer: Network and Tor | The network route ([network.md](network.md)) | `NetworkScreen` |
| Drawer: Settings | The settings of the app, with Developer (node connect, Celaut service, nodes, deposit, the switch of the home screen) | `SettingsScreen` |
| Drawer: About | The version and the update check | `AboutPage` |

A row of the list has the initial of the service, its name, the cost so far, the last
message that the app saw in this run (or a note that it saw none), and "state · node". The
name is the name of the skill or the service file at the start; the database keeps it with
the instance (`InstanceRecord.name`). An instance of an earlier version has no name: the row
shows the short service id.

The states of a row:

| State | When |
|---|---|
| Checking | The app asks the node (`celautInstanceStatus`) |
| Starting | The instance started in this run, and its service did not answer yet |
| Running | The node reports the instance |
| Not answering | The node does not answer, or does not report the instance. The info page says why |
| Stopped | The instance stopped in this run. The row stays until the user removes it or the app closes |

The list asks the nodes when it opens, when the user comes back to it, and on a pull. It does
not ask them in the background.

## 3. Flows

- **New conversation.** Pencil → "New conversation" → a skill → its services, best first →
  Run → "Run <name>?" with the node and the start cost → the PIN or fingerprint if the wallet
  is locked → the launch → back to the list and into the conversation, which says that the
  service starts (`ChatClient.syncWhenStarted`). Back from the conversation is the list.
  "Services" in the drawer and "Run a service" on the compute page end the same way. A
  service without a chat slot starts, and a message says that it is in "Other instances".
- **Open a conversation again.** A tap on a row opens the local port of the chat slot and
  reads the history from 0 ([chat.md](chat.md), section 5). This works after the lock of the
  app closed the screen, and after a restart of the app.
- **Leave.** Back goes to the list at once. The instance runs on, the node keeps charging,
  and the row shows its cost.
- **Stop.** From ⋮ in the conversation, from its info page, from a long press in the list,
  or from the compute page. The app asks "Stop <name>?", then needs the wallet open. The row
  stays as "Stopped" with the last message.
- **Remove from the list.** A long press on a stopped row removes it. A long press on a row
  that is not answering offers it with a warning: the app forgets the token of the instance
  (`celaut_forget_instance`), so it cannot stop it later, and the node keeps charging if it
  still runs it. A running row offers Stop, not Remove.

The last message of each conversation and the stopped rows are in memory only
(`ConversationNotes`, `app/lib/celaut/conversations.dart`). The app writes no message to the
Celaut database.

The setting "Chats home" (Settings, Developer; key `celaut_compute_home_v1`) chooses the
first screen: the conversations (on, the default) or the wallets list (off). The compute
view is the page "Compute and credit" of the drawer, not a first screen.

## 4. Changed decisions (for Josemi to confirm)

| Where | Before | In this UI |
|---|---|---|
| [chat.md](chat.md), section 1 and 5: leaving the screen (decision of 2026-10-14) | The app asks "Stop the instance" or "Leave it running" | Back goes to the list without a question. The instance runs on and stays in the list. Stop is in ⋮, the info page and the long press |
| [ui.md](ui.md), section 2: the home screen (decision of 2026-10-16) | The compute view: running instances, "Run a service", the card of state | The list of conversations. The compute view is unchanged and is a page of the drawer |
| [ui.md](ui.md), section 2: "Run a service" | A button of the home screen | The pencil button ("New conversation") and "Services" in the drawer; the compute page keeps its button. The confirmation is the same |
| The Celaut database | An instance has no name | An instance keeps the name of its skill or service file (`InstanceRecord.name`, optional) |
| Instances | An instance leaves the database only at a stop | The user can also remove an instance that is not answering, after a warning (`celaut_forget_instance`) |

## 5. Open questions

1. A drawer, or a bottom bar as Telegram (from February 2026) and WhatsApp have, for
   example Chats, Wallet, Nodes, Settings?
2. Should the list check the nodes every minute while it is open, as the Nodes screen does,
   or only on open, on return and on a pull (as built)?
3. Remove from the list for an instance that is not answering: keep it, or never forget a
   token without a stop?
