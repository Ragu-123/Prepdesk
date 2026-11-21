package com.bitchat.android.blend

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bitchat.android.nostr.NostrRelayManager
import com.bitchat.android.core.ui.component.sheet.BitchatBottomSheet
import com.bitchat.android.core.ui.component.sheet.BitchatSheetTitle
import com.bitchat.android.core.ui.component.sheet.BitchatSheetTopBar
import com.bitchat.android.services.AppStateStore
import com.bitchat.android.services.ContactDirectory
import com.bitchat.android.ui.ChatViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.time.LocalDate
import java.time.LocalTime
import java.util.Date
import java.util.UUID

internal data class BlendOpen(
    val peer: String? = null, val shareSchedule: Boolean = false, val frame: BlendFrame? = null,
    val start: Boolean = false, val watchOnly: Boolean = false, val settings: Boolean = false,
    val sessionId: String? = null, val progressOnly: Boolean = false
)

internal val LocalBlendNavigation = staticCompositionLocalOf<(BlendOpen) -> Unit> { {} }
private enum class PageAction { NONE, SHARE, SETUP, SETTINGS, CHECK_IN, TASK, PROGRESS }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BlendPanel(
    entry: BlendOpen,
    controller: BlendController,
    viewModel: ChatViewModel,
    onExit: () -> Unit
) {
    val context = LocalContext.current
    val sessions by controller.sessions.collectAsStateWithLifecycle()
    val chats by AppStateStore.privateMessages.collectAsStateWithLifecycle()
    val nearby by AppStateStore.peers.collectAsStateWithLifecycle()
    val verified by viewModel.verifiedFingerprints.collectAsStateWithLifecycle()
    val relay by NostrRelayManager.shared.isConnected.collectAsStateWithLifecycle()
    val issue by controller.issue.collectAsStateWithLifecycle()
    var peer by remember(entry) { mutableStateOf(entry.peer) }
    val eligible = sessions.asReversed().filter {
        !it.stopped && entry.peer != null &&
            ContactDirectory.canonicalConversationId(it.peer) == ContactDirectory.canonicalConversationId(entry.peer) &&
            (!entry.watchOnly || it.role == BlendRole.SPECTATOR || it.peerRole == BlendRole.PARTICIPATE)
    }
    val existing = eligible.firstOrNull {
        it.active && (!entry.watchOnly || it.peerRole == BlendRole.PARTICIPATE)
    } ?: eligible.firstOrNull().takeUnless { entry.progressOnly }
    var opened by remember(entry) {
        mutableStateOf(entry.sessionId ?: entry.frame?.blend ?: existing?.id.takeIf { entry.start || entry.progressOnly })
    }
    var action by remember(entry) { mutableStateOf(if (entry.shareSchedule) PageAction.SHARE else PageAction.NONE) }
    var taskToEdit by remember { mutableStateOf<BlendItem?>(null) }
    var showConnection by remember { mutableStateOf(false) }
    var stop by remember { mutableStateOf(false) }
    val selected = sessions.firstOrNull { it.id == opened }
    val people = (nearby + chats.keys + sessions.map { it.peer }).map(ContactDirectory::canonicalConversationId).distinct()
    val name: (String) -> String = { ContactDirectory.resolve(it).displayName ?: viewModel.resolvePeerDisplayNameForFingerprint(it) }
    val peerVerified: (String) -> Boolean = { viewModel.isPeerVerified(it, verified) ||
        ContactDirectory.resolve(it).noisePublicKey?.let { key -> viewModel.isNoisePublicKeyVerified(key, verified) } == true }
    LaunchedEffect(entry) {
        val target = entry.peer
        if (entry.start && opened == null && target != null && peerVerified(target)) action = PageAction.SETUP
    }
    val exit: () -> Unit = {
        if (opened != null && entry.frame == null && entry.peer == null) {
            opened = null
            peer = null
        }
        else if (peer != null && entry.peer == null) peer = null
        else onExit()
    }
    BitchatBottomSheet(onDismissRequest = onExit) {
        BitchatSheetTopBar(
            onClose = onExit,
            title = { BitchatSheetTitle(when {
                entry.settings -> "Blend settings"
                entry.progressOnly -> "Shared progress"
                selected != null -> selected.mode.label
                entry.frame?.event == BlendEvent.SCHEDULE -> "Shared schedule"
                else -> "Blend"
            }) },
            navigationIcon = if (entry.peer == null && (selected != null || peer != null)) {
                { IconButton(onClick = exit) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } }
            } else null
        )
        Column(
            Modifier.fillMaxWidth().fillMaxHeight(0.9f).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (issue != null) Text(issue.orEmpty(), color = MaterialTheme.colorScheme.error)

            val frame = entry.frame
            val person = peer
            when {
                frame?.event == BlendEvent.SCHEDULE -> {
                    Text("Shared by ${person?.let(name) ?: "your partner"}", style = MaterialTheme.typography.titleMedium)
                    StudyGroups(BlendProtocol.items(frame.data.optJSONArray("items")))
                }
                frame?.event == BlendEvent.CHECK_IN -> Text(frame.data.optString("label").take(120))
                entry.progressOnly && selected == null -> {
                    Text("No shared progress yet", style = MaterialTheme.typography.titleMedium)
                    Text("Progress appears here after your partner accepts a request and shares an update.")
                    if (person != null) Button(onClick = {
                        if (peerVerified(person)) action = PageAction.SETUP else {
                            onExit()
                            viewModel.showVerificationSheet()
                        }
                    }) { Text(if (peerVerified(person)) "Request to watch" else "Verify partner by QR") }
                }
                selected != null -> {
                    val partner = name(selected.peer)
                    Text(partner, style = MaterialTheme.typography.titleLarge)
                    Text(if (selected.stopped) "Blend ended" else if (selected.active) selected.role.label else "Invitation pending")
                    if (!selected.active && !selected.stopped && !selected.owner) {
                        Text("${partner} wants to ${selected.peerRole.label.lowercase()}. Choose what you share before accepting.")
                        selected.requestedUpdates?.let { Text("Requested updates · ${it.label}") }
                        Button(onClick = {
                            if (peerVerified(selected.peer)) action = PageAction.SETUP else {
                                onExit()
                                viewModel.showVerificationSheet()
                            }
                        }) { Text(if (peerVerified(selected.peer)) "Review invitation" else "Verify partner by QR") }
                    } else if (!selected.active && !selected.stopped && selected.owner) {
                        Text("Your partner needs an updated PrepChat to accept this invitation.")
                    }
                    if (selected.active) {
                        if (!entry.progressOnly && selected.role == BlendRole.PARTICIPATE) {
                            var myItems by remember(selected) { mutableStateOf<List<BlendItem>?>(null) }
                            LaunchedEffect(selected) {
                                myItems = withContext(Dispatchers.IO) {
                                    runCatching { controller.progressItems(selected) }.getOrNull()
                                }
                            }
                            myItems?.let { items ->
                                OutlinedCard(Modifier.fillMaxWidth()) {
                                    Column(Modifier.padding(16.dp)) {
                                        Text("Your progress", style = MaterialTheme.typography.titleMedium)
                                        Text("${items.count { it.done }} done · ${items.count { !it.done }} left today")
                                    }
                                }
                            }
                        }
                        if (selected.peerRole == BlendRole.PARTICIPATE) {
                            ProgressCard(partner, selected.theirs, selected.receivedAt)
                            StudyGroups(selected.theirs)
                        }
                        if (!selected.stopped && selected.peerRole == BlendRole.PARTICIPATE) {
                            var updateRequested by remember(selected.id, selected.receivedAt) { mutableStateOf(false) }
                            OutlinedButton(onClick = {
                                controller.request(selected)
                                updateRequested = true
                            }) { Text(if (updateRequested) "Request again" else "Request update") }
                            if (updateRequested) Text("Waiting for shared progress.", style = MaterialTheme.typography.bodySmall)
                        }
                        if (!entry.progressOnly && !selected.stopped && selected.role == BlendRole.PARTICIPATE) {
                            if (selected.requested) Text("$partner requested an update.")
                            Button(onClick = { action = PageAction.PROGRESS }) { Text("Preview my update") }
                            TextButton(onClick = { action = PageAction.SETTINGS }) { Text("Sharing settings") }
                        }
                        if (!entry.progressOnly && !selected.stopped && selected.mode == BlendMode.CHECKLIST) {
                            Text("Shared checklist", style = MaterialTheme.typography.titleMedium)
                            selected.tasks.forEach { item ->
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    if (selected.role == BlendRole.PARTICIPATE) {
                                        Checkbox(item.id in selected.mineDone, { controller.toggleTask(selected, item.id) })
                                    }
                                    Text(item.title, Modifier.weight(1f))
                                    if (selected.owner) TextButton(onClick = {
                                        taskToEdit = item
                                        action = PageAction.TASK
                                    }) { Text("Edit") }
                                }
                            }
                            if (selected.owner) TextButton(onClick = {
                                taskToEdit = null
                                action = PageAction.TASK
                            }) { Text("Add task") }
                        }
                    }
                    if (!entry.progressOnly && !selected.stopped) TextButton(onClick = { stop = true }) { Text("End Blend") }
                }
                person != null && action != PageAction.SHARE -> {
                    Text(name(person), style = MaterialTheme.typography.headlineSmall)
                    Text(if (peerVerified(person)) "Verified study partner" else "Verify this contact before starting a Blend.")
                    Button(onClick = {
                        if (peerVerified(person)) action = PageAction.SETUP else {
                            onExit()
                            viewModel.showVerificationSheet()
                        }
                    }) { Text(if (peerVerified(person)) "Start a Blend" else "Verify by QR") }
                    OutlinedButton(onClick = { action = PageAction.SHARE }) { Text("Share schedule") }
                    TextButton(onClick = { action = PageAction.CHECK_IN }) { Text("Send check-in") }
                    TextButton(onClick = {
                        viewModel.showPrivateChatSheet(person)
                        onExit()
                    }) { Text("Open private chat") }
                    sessions.filter { it.peer == person }.reversed().forEach { session ->
                        SessionCard(session, name(person)) { opened = session.id }
                    }
                }
                peer == null && action == PageAction.SHARE -> {
                    Text("Choose a recipient", style = MaterialTheme.typography.titleLarge)
                    if (people.isEmpty()) Text("Start a private conversation to add a study partner.")
                    people.sortedBy { !peerVerified(it) }.forEach { personId ->
                        OutlinedCard(onClick = { peer = personId }, modifier = Modifier.fillMaxWidth()) {
                            ListItem(
                                headlineContent = { Text(name(personId)) },
                                supportingContent = { Text(if (peerVerified(personId)) "Verified" else "Private contact") },
                                leadingContent = { Icon(Icons.Outlined.ChatBubbleOutline, null) }
                            )
                        }
                    }
                }
                else -> {
                    if (entry.settings) Text("Sharing and participation", style = MaterialTheme.typography.titleMedium)
                    if (sessions.none { !it.stopped }) {
                        Text("No Blends yet", style = MaterialTheme.typography.titleMedium)
                        Text("Start a Blend from a private conversation.")
                    }
                    sessions.filterNot { it.stopped }.reversed().forEach { session ->
                        SessionCard(session, name(session.peer)) {
                            peer = session.peer
                            opened = session.id
                            if (entry.settings && session.active && session.role == BlendRole.PARTICIPATE)
                                action = PageAction.SETTINGS
                        }
                    }
                }
            }
            if (person != null || selected != null) {
                HorizontalDivider()
                TextButton(onClick = { showConnection = !showConnection }) { Text("Connection and delivery") }
                if (showConnection) {
                    val target = selected?.peer ?: person
                    val connected = target != null && nearby.any {
                        ContactDirectory.canonicalConversationId(it) == ContactDirectory.canonicalConversationId(target)
                    }
                    Text(when {
                        connected -> "Partner nearby"
                        relay && target != null && ContactDirectory.resolve(target).isMutualFavorite ->
                            "Private relays available for this partner"
                        relay -> "Star each other in chat to enable delivery through private relays."
                        else -> "Waiting for a private connection"
                    })
                    TextButton(onClick = {
                        controller.retry()
                        target?.let(viewModel::retryPrivateText)
                    }) { Text("Retry pending sends") }
                    val bluetoothEnabled = runCatching {
                        context.getSystemService(BluetoothManager::class.java)?.adapter?.isEnabled
                    }.getOrNull()
                    if (bluetoothEnabled == false) TextButton(onClick = {
                        runCatching { context.startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)) }
                            .onFailure { controller.issue.value = "Open Android Bluetooth settings to enable Bluetooth." }
                    }) { Text("Turn on Bluetooth") }
                }
            }
        }
    }

    when (action) {
        PageAction.SETUP, PageAction.SETTINGS -> if (peer != null) {
            val editing = action == PageAction.SETTINGS
            BlendSetup(selected, editing, entry.watchOnly || entry.progressOnly,
                onDismiss = { action = PageAction.NONE }) { mode, role, updates, time, categories ->
                when {
                    editing && selected != null -> controller.updateSettings(selected, updates, time, categories)
                    selected != null -> controller.accept(selected, role, updates, time, categories)
                    else -> controller.invite(checkNotNull(peer), mode, role, updates, time, categories)
                }
                action = PageAction.NONE
            }
        }
        PageAction.SHARE -> peer?.let { person ->
            ScheduleShare(controller, name(person), onDismiss = { action = PageAction.NONE }) {
                controller.shareSchedule(person, it)
                action = PageAction.NONE
            }
        }
        PageAction.CHECK_IN -> peer?.let { person ->
            TextEntryDialog("Study check-in", "How’s studying going?", "", { action = PageAction.NONE }) {
                controller.checkIn(person, it)
                action = PageAction.NONE
            }
        }
        PageAction.TASK -> if (selected != null) {
            TextEntryDialog(if (taskToEdit == null) "Add task" else "Edit task", "Task title", taskToEdit?.title.orEmpty(),
                onDismiss = { action = PageAction.NONE }, onRemove = taskToEdit?.let { task ->
                    { controller.updateTasks(selected, selected.tasks.filterNot { it.id == task.id }); action = PageAction.NONE }
                }) { title ->
                val item = taskToEdit?.copy(title = title) ?: BlendItem(
                    UUID.randomUUID().toString(), title, "Schedule", LocalDate.now().toString(), false)
                controller.updateTasks(selected, if (taskToEdit == null) selected.tasks + item else
                    selected.tasks.map { if (it.id == item.id) item else it })
                action = PageAction.NONE
            }
        }
        PageAction.PROGRESS -> if (selected != null) {
            var preview by remember(selected) { mutableStateOf<Result<List<BlendItem>>?>(null) }
            LaunchedEffect(selected) {
                preview = withContext(Dispatchers.IO) { runCatching { controller.progressItems(selected) } }
            }
            BlendDialog("Send today’s progress", { action = PageAction.NONE }, "Send update", preview?.isSuccess == true, {
                preview?.getOrNull()?.let { controller.sendProgress(selected, it) }
                action = PageAction.NONE
            }) {
                preview?.fold({ StudyGroups(it) }, { Text(it.message ?: "Couldn’t load today’s study items.") })
                    ?: LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        }
        PageAction.NONE -> Unit
    }
    if (stop && selected != null) {
        BlendDialog("End this Blend?", { stop = false }, "End Blend", true, {
            controller.stop(selected)
            stop = false
        }) { Text("Future updates will stop. Your partner may still have updates they previously received.") }
    }
}

@Composable
private fun SessionCard(session: BlendSession, name: String, onClick: () -> Unit) {
    OutlinedCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        ListItem(
            headlineContent = { Text(name) },
            supportingContent = {
                val status = when {
                    session.stopped -> "Ended"
                    !session.active -> "Invitation pending"
                    session.peerRole == BlendRole.SPECTATOR -> "Partner is watching"
                    session.receivedAt == 0L -> "Waiting for progress"
                    else -> "${session.theirs.count { it.done }} done · ${session.theirs.count { !it.done }} left"
                }
                Text("${session.mode.label} · $status")
            },
            leadingContent = { Icon(Icons.Outlined.CalendarToday, null) }
        )
    }
}

@Composable
private fun ProgressCard(name: String, items: List<BlendItem>, receivedAt: Long) {
    val done = items.count { it.done }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(if (receivedAt == 0L) "Waiting for $name’s first update" else "$done done  ·  ${items.size - done} left",
                style = MaterialTheme.typography.titleMedium)
            if (receivedAt != 0L) {
                LinearProgressIndicator(progress = { if (items.isEmpty()) 0f else done.toFloat() / items.size },
                    modifier = Modifier.fillMaxWidth())
                Text("Updated ${DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(receivedAt))}")
            }
        }
    }
}

@Composable
private fun StudyGroups(items: List<BlendItem>) {
    if (items.isEmpty()) Text("No study items in this update.")
    BlendProtocol.categories.forEach { category ->
        val rows = items.filter { it.category == category }
        if (rows.isNotEmpty()) {
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Text(category, style = MaterialTheme.typography.titleSmall)
            rows.sortedWith(compareBy<BlendItem> { it.day }.thenBy { it.done }).forEach { item ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(item.title, style = MaterialTheme.typography.bodyMedium)
                        Text(item.day, style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text(if (item.done) "Done" else "Left", style = MaterialTheme.typography.labelMedium,
                        color = if (item.done) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BlendSetup(
    session: BlendSession?, editing: Boolean, watchOnly: Boolean, onDismiss: () -> Unit,
    onSave: (BlendMode, BlendRole, BlendUpdateMode, String?, Set<String>) -> Unit
) {
    val context = LocalContext.current
    var mode by remember { mutableStateOf(session?.mode ?: BlendMode.TIMETABLE) }
    var role by remember {
        mutableStateOf(when {
            editing -> session?.role ?: BlendRole.PARTICIPATE
            watchOnly && session?.peerRole != BlendRole.SPECTATOR -> BlendRole.SPECTATOR
            else -> BlendRole.PARTICIPATE
        })
    }
    var updates by remember {
        mutableStateOf(when {
            editing -> session?.updateMode ?: BlendUpdateMode.MANUAL
            session?.requestedUpdates != null -> session.requestedUpdates
            watchOnly -> BlendUpdateMode.ON_REQUEST
            else -> BlendUpdateMode.MANUAL
        })
    }
    var time by remember { mutableStateOf(LocalTime.parse(session?.automaticAt ?: "19:00")) }
    var categories by remember { mutableStateOf(session?.categories ?: BlendProtocol.categories.toSet()) }
    val valid = !(role == BlendRole.SPECTATOR && session?.peerRole == BlendRole.SPECTATOR && session != null) &&
        (role == BlendRole.SPECTATOR || mode == BlendMode.CHECKLIST || categories.isNotEmpty())
    BlendDialog(if (editing) "Sharing settings" else if (session == null) "Request a Blend" else "Accept Blend",
        onDismiss, if (editing) "Save" else if (session == null) "Send request" else "Accept", valid, {
            onSave(mode, role, updates, if (updates == BlendUpdateMode.DAILY && role == BlendRole.PARTICIPATE) time.toString() else null, categories)
        }) {
        if (session == null) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            BlendMode.entries.forEach { option -> FilterChip(mode == option, { mode = option }, { Text(option.label) }) }
        }
        if (!editing) {
            Text("Your role", style = MaterialTheme.typography.titleSmall)
            BlendRole.entries.forEach { option ->
                val allowed = option != BlendRole.SPECTATOR || session?.peerRole != BlendRole.SPECTATOR
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(role == option, { role = option }, enabled = allowed)
                    Column {
                        Text(option.label)
                        Text(if (option == BlendRole.SPECTATOR) "View the partner’s study day without sharing yours."
                            else "Share the study items and progress you approve.",
                            style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
        Text(if (role == BlendRole.SPECTATOR) "Request updates" else "Send updates",
            style = MaterialTheme.typography.titleSmall)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            BlendUpdateMode.entries.forEach { option ->
                FilterChip(updates == option, { updates = option }, { Text(option.label) })
            }
        }
        if (role == BlendRole.PARTICIPATE) {
            if (mode == BlendMode.TIMETABLE) {
                Text("Share titles, dates, and completion for")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    BlendProtocol.categories.forEach { category ->
                        FilterChip(category in categories, {
                            categories = if (category in categories) categories - category else categories + category
                        }, { Text(category) })
                    }
                }
            }
            if (updates != BlendUpdateMode.MANUAL) {
                Text(if (updates == BlendUpdateMode.DAILY) "Send daily and when your partner requests an update."
                    else "Automatically reply when your partner requests an update.")
                Text("For updates while you’re away, enable Keep PrepChat listening.",
                    style = MaterialTheme.typography.bodySmall)
                if (updates == BlendUpdateMode.DAILY) TextButton(onClick = {
                    TimePickerDialog(context, { _, hour, minute -> time = LocalTime.of(hour, minute) },
                        time.hour, time.minute, android.text.format.DateFormat.is24HourFormat(context)).show()
                }) { Text("Daily update at $time") }
            } else Text("Review each update before it leaves your device.")
        } else Text("Your partner chooses what to share and accepts before any progress appears.")
    }
}

@Composable
private fun ScheduleShare(controller: BlendController, recipient: String, onDismiss: () -> Unit, onSend: (List<BlendItem>) -> Unit) {
    val context = LocalContext.current
    var day by remember { mutableStateOf(LocalDate.now()) }
    var selected by remember { mutableStateOf<Map<String, BlendItem>>(emptyMap()) }
    var rows by remember { mutableStateOf<Result<List<BlendItem>>?>(null) }
    var preview by remember { mutableStateOf(false) }
    LaunchedEffect(day) {
        rows = null
        rows = withContext(Dispatchers.IO) { runCatching { controller.readDay(day) } }
    }
    BlendDialog(if (preview) "Preview for $recipient" else "Share schedule",
        onDismiss, if (preview) "Send schedule" else "Preview", selected.isNotEmpty(), {
            if (preview) onSend(selected.values.toList()) else preview = true
        }) {
        if (preview) {
            StudyGroups(selected.values.toList())
            TextButton(onClick = { preview = false }) { Text("Change selection") }
        } else {
            TextButton(onClick = {
                DatePickerDialog(context, { _, y, m, d -> day = LocalDate.of(y, m + 1, d) },
                    day.year, day.monthValue - 1, day.dayOfMonth).show()
            }) { Text("Day  $day") }
            Text("${selected.size} selected", style = MaterialTheme.typography.bodySmall)
            val items = rows?.getOrNull()
            if (items == null) {
                if (rows == null) LinearProgressIndicator(Modifier.fillMaxWidth())
                else Text(rows?.exceptionOrNull()?.message ?: "Couldn’t load study items.")
            } else if (items.isEmpty()) Text("No study items for this day.")
            else items.forEach { item ->
                val key = "${item.day}/${item.id}"
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(key in selected, {
                        selected = if (it) selected + (key to item) else selected - key
                    }, enabled = key in selected || selected.size < BlendProtocol.MaxItems)
                    Column {
                        Text(item.title)
                        Text(item.category, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}

@Composable
private fun TextEntryDialog(
    title: String, label: String, initial: String, onDismiss: () -> Unit,
    onRemove: (() -> Unit)? = null, onSave: (String) -> Unit
) {
    var value by remember(initial) { mutableStateOf(initial) }
    BlendDialog(title, onDismiss, if (title == "Study check-in") "Send" else "Save", value.trim().isNotEmpty(),
        { onSave(value.trim()) }) {
        OutlinedTextField(value, { value = it.take(100) }, label = { Text(label) }, modifier = Modifier.fillMaxWidth())
        onRemove?.let { TextButton(onClick = it) { Text("Remove task") } }
    }
}

@Composable
private fun BlendDialog(
    title: String, onDismiss: () -> Unit, action: String, enabled: Boolean, onConfirm: () -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss, title = { Text(title) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
        },
        confirmButton = { TextButton(onClick = onConfirm, enabled = enabled) { Text(action) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}
