# BitChat Android integration

Prepdesk v1.0.23 uses public Nostr relay rooms inside the app. The integrated screen starts with chat off and shows connected relays, the active room, and message send failures. Public rooms share text with anyone who joins the same room and receives its events. Nearby offline chat and private messages require the native transport work below.

The Android reference is the local `bitchat-android` checkout at `998f1684`. Its README describes a public-domain release and its LICENSE file contains GPLv3. Confirm the applicable terms for each imported component before vendoring it.

1. Put the Android transport behind a small Flutter channel for starting and stopping the radio, peers, incoming messages, sending, and status events. Check upstream dependency versions and Android SDK requirements against Prepdesk's GitHub release build.
2. Port the interoperable BLE framing, fragmentation, peer discovery, and forwarding behavior. Preserve upstream message IDs across forwards and persist each logical message once, including when a send returns over a second transport.
3. Wire the native transport into the current room and conversation screens. Request Bluetooth access when the user enables Nearby chat. Stop scanning, advertising, and connections when chat is switched off.
4. Add direct conversations only after both endpoints can establish and verify the upstream encrypted session. Keep the selected transport and delivery state visible in each conversation.
5. Check two Prepdesk phones and a phone running the upstream Android app. Cover offline discovery and delivery, fragmentation, relay reconnects, messages arriving over both transports, switching chat off mid-send, and Android permission denial. Run the APK and Play bundle through GitHub Actions after these checks.
