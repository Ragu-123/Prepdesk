# BitChat Android in Prepdesk

Prepdesk embeds the [BitChat Android](https://github.com/permissionlesstech/bitchat-android) app at revision `998f1684` as the `android/bitchat` library. Both source trees are distributed under [GPLv3](../LICENSE). The upstream Activity, Compose screens, conversation management, private-message store, and networking ship inside the Prepdesk package.

The host launches BitChat in a separate Android process and task. The upstream quit and panic controls can shut down chat and clear its own state without killing Prepdesk or wiping the study database. Bluetooth and relay connectivity start after opening chat. Background operation and boot startup are disabled until enabled in BitChat settings. Prepdesk passes its current light palette into the chat UI and shares the bundled Noto Sans family. The explicit dark-theme setting remains available in BitChat.

The integration retains native nearby mesh, encrypted direct chats, Nostr rooms, media and voice controls, peer verification, conversation deletion, and BitChat settings. The Android manifest keeps the Prepdesk launcher and scopes BitChat's file provider and signature permission to the Prepdesk package. Existing study data stays in Prepdesk's database. Old Flutter chat records remain in backups but do not appear in the native conversation store.

The bundled Arti native libraries come from the pinned upstream checkout. Build instructions, pinned toolchain inputs, and library checksums are in [the upstream Arti build directory](https://github.com/permissionlesstech/bitchat-android/tree/998f1684/tools/arti-build).

Verify Bluetooth discovery and public and private delivery with two Prepdesk phones and with a phone running upstream BitChat. Check relay handoff, duplicate delivery, delete and undo, attachment sharing, permission denial, background opt-in, and leaving or quitting chat while Prepdesk remains open.
