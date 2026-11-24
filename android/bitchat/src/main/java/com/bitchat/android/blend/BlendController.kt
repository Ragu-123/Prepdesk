package com.bitchat.android.blend

import android.content.Context
import android.net.Uri
import com.bitchat.android.model.BitchatMessage
import com.bitchat.android.model.DeliveryStatus
import com.bitchat.android.service.MeshServiceHolder
import com.bitchat.android.service.MeshServicePreferences
import com.bitchat.android.services.AppStateStore
import com.bitchat.android.services.ContactDirectory
import com.bitchat.android.services.MessageRouter
import com.bitchat.android.ui.PrivateChatManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalTime
import java.util.Date
import java.util.UUID

internal class BlendController private constructor(private val app: Context) {
    private data class Pending(val id: String, val peer: String, val text: String) {
        fun json() = JSONObject().put("id", id).put("peer", peer).put("text", text)
    }

    private val store = BlendStore(app)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val saved = runCatching { store.read() }.also {
        if (it.isFailure) android.util.Log.w("Blend", "Study partnership storage is unavailable")
    }
    private val pending = linkedMapOf<String, Pending>()
    private val lastAttempt = mutableMapOf<String, Long>()
    private val received = linkedSetOf<String>()
    private val transfers = linkedMapOf<String, JSONObject>()
    val sharedSchedules = MutableStateFlow<Map<String, List<BlendItem>>>(emptyMap())
    val sessions = MutableStateFlow<List<BlendSession>>(emptyList())
    val delivery = MutableStateFlow<Map<String, String>>(emptyMap())
    val issue = MutableStateFlow<String?>(if (saved.isFailure) "Blend storage is unavailable." else null)
    var isBlocked: (String) -> Boolean = { false }

    init {
        val state = saved.getOrNull() ?: JSONObject()
        sessions.value = state.optJSONArray("sessions").objects().mapNotNull { runCatching { BlendSession.parse(it) }.getOrNull() }
        state.optJSONArray("outbox").objects().forEach {
            val entry = Pending(it.getString("id"), it.getString("peer"), it.getString("text"))
            pending[entry.id] = entry
        }
        state.optJSONArray("transfers").objects().forEach { transfers[it.getString("key")] = it }
        sharedSchedules.value = state.optJSONArray("schedules").objects().associate {
            it.getString("key") to BlendProtocol.items(it.optJSONArray("items"), BlendProtocol.MaxSnapshotItems)
        }
        received.addAll(state.optJSONArray("received").strings())
        scope.launch { AppStateStore.privateMessages.collect { processMessages(it) } }
        scope.launch {
            while (isActive) {
                if (AppStateStore.isChatActivityResumed || MeshServicePreferences.isBackgroundEnabled(false)) {
                    guarded {
                        scheduleUpdates()
                        retryPending()
                    }
                }
                delay(if (sessions.value.isEmpty() && pending.isEmpty()) 60_000L else 25_000L)
            }
        }
    }

    fun bind(manager: PrivateChatManager) {
        isBlocked = manager::isPeerBlocked
    }

    fun readDay(day: LocalDate): List<BlendItem> {
        val uri = Uri.parse("content://${app.packageName}.blend.study")
        val data = app.contentResolver.call(uri, "studyDay", day.toString(), null)?.getString("items")
            ?: throw IllegalStateException("Open Prepdesk to load your timetable.")
        val rows = JSONArray(data)
        require(rows.length() <= BlendProtocol.MaxSnapshotItems) { "This timetable exceeds 2,000 items." }
        return BlendProtocol.items(rows, limit = BlendProtocol.MaxSnapshotItems)
    }

    fun invite(peer: String, mode: BlendMode, role: BlendRole, updates: BlendUpdateMode, at: String?, categories: Set<String>) = action {
        require(sessions.value.none {
            !it.stopped && it.mode == mode && it.role == role && canonical(it.peer) == canonical(peer)
        }) { "You already have a Blend with this role and plan." }
        val id = id()
        val preference = updates.takeIf { role == BlendRole.SPECTATOR }
        val session = BlendSession(id, canonical(peer), mode, true, role = role,
            automaticAt = at.takeIf { role == BlendRole.PARTICIPATE && updates == BlendUpdateMode.DAILY },
            autoReply = role == BlendRole.PARTICIPATE && updates != BlendUpdateMode.MANUAL,
            requestedUpdates = preference, categories = categories)
        queue(session.peer, BlendFrame(BlendEvent.INVITE, id,
            JSONObject().put("mode", mode.name).put("role", role.name).put("updates", preference?.name)))
        put(session)
    }

    fun accept(session: BlendSession, role: BlendRole, updates: BlendUpdateMode, at: String?, categories: Set<String>) = action {
        val current = current(session.id)
        require(!current.owner && !current.active && !current.stopped)
        require(role != BlendRole.SPECTATOR || current.peerRole != BlendRole.SPECTATOR) {
            "At least one partner needs to participate."
        }
        queue(current.peer, BlendFrame(BlendEvent.ACCEPT, current.id, JSONObject().put("role", role.name)))
        put(current.copy(active = true, role = role,
            automaticAt = at.takeIf { role == BlendRole.PARTICIPATE && updates == BlendUpdateMode.DAILY },
            autoReply = role == BlendRole.PARTICIPATE && updates != BlendUpdateMode.MANUAL, categories = categories,
            requested = role == BlendRole.PARTICIPATE && current.peerRole == BlendRole.SPECTATOR))
    }

    fun updateSettings(session: BlendSession, updates: BlendUpdateMode, at: String?, categories: Set<String>) = action {
        val current = current(session.id)
        require(current.active && !current.stopped && current.role == BlendRole.PARTICIPATE)
        val dailyAt = at.takeIf { updates == BlendUpdateMode.DAILY }
        if (current.updateMode != updates || current.automaticAt != dailyAt || current.categories != categories) {
            pending.values.removeAll {
                val frame = BlendProtocol.decode(it.text)
                if (it.peer != current.peer || frame == null || frame.blend != current.id ||
                    frame.event != BlendEvent.PROGRESS) false
                else {
                    delivery.value = delivery.value + (it.id to "Canceled after sharing settings changed")
                    lastAttempt.remove(it.id)
                    true
                }
            }
        }
        put(current.copy(automaticAt = dailyAt, autoReply = updates != BlendUpdateMode.MANUAL, categories = categories))
    }

    fun shareSchedule(peer: String, items: List<BlendItem>) = action {
        require(items.isNotEmpty())
        val transfer = id()
        queueSnapshot(canonical(peer), BlendFrame(BlendEvent.SCHEDULE, transfer,
            JSONObject().put("items", BlendProtocol.pack(items))), items, transfer)
        saveSchedule(canonical(peer), transfer, items)
    }

    fun checkIn(peer: String, label: String) = action {
        require(label.trim().length in 1..120)
        queue(canonical(peer), BlendFrame(BlendEvent.CHECK_IN, id(), JSONObject().put("label", label.trim())))
    }

    fun request(session: BlendSession) = action {
        val current = current(session.id)
        require(current.active && !current.stopped && current.peerRole == BlendRole.PARTICIPATE)
        queue(current.peer, BlendFrame(BlendEvent.REQUEST, current.id))
    }

    fun stop(session: BlendSession) = action {
        val current = current(session.id)
        require(!current.stopped)
        pending.values.removeAll { it.peer == current.peer && BlendProtocol.decode(it.text)?.blend == current.id }
        queue(current.peer, BlendFrame(BlendEvent.STOP, current.id))
        put(current.copy(stopped = true, requested = false))
    }

    fun updateTasks(session: BlendSession, tasks: List<BlendItem>) = action {
        val current = current(session.id)
        require(current.owner && current.active && !current.stopped && current.mode == BlendMode.CHECKLIST)
        require(tasks.size <= BlendProtocol.MaxItems)
        val revision = current.localRevision + 1
        queue(current.peer, BlendFrame(BlendEvent.PLAN, current.id, JSONObject()
            .put("items", BlendProtocol.pack(tasks)).put("revision", revision)))
        put(current.copy(tasks = tasks, localRevision = revision))
    }

    fun toggleTask(session: BlendSession, id: String) = action {
        val current = current(session.id)
        require(current.active && !current.stopped && current.role == BlendRole.PARTICIPATE && current.tasks.any { it.id == id })
        put(current.copy(mineDone = if (id in current.mineDone) current.mineDone - id else current.mineDone + id))
    }

    fun progressItems(session: BlendSession): List<BlendItem> = if (session.mode == BlendMode.CHECKLIST) {
        session.tasks.map { it.copy(done = it.id in session.mineDone) }
    } else {
        readDay(LocalDate.now()).filter { it.category in session.categories }
    }

    fun sendProgress(session: BlendSession, approvedItems: List<BlendItem>) = action {
        sendSnapshot(current(session.id), approvedItems)
    }

    private fun sendSnapshot(session: BlendSession, approvedItems: List<BlendItem>? = null) {
        require(session.active && !session.stopped && session.role == BlendRole.PARTICIPATE)
        val items = approvedItems?.filter {
            session.mode == BlendMode.CHECKLIST || it.category in session.categories
        } ?: progressItems(session)
        val revision = session.localRevision + 1
        queueSnapshot(session.peer, BlendFrame(BlendEvent.PROGRESS, session.id, JSONObject()
            .put("items", BlendProtocol.pack(items)).put("revision", revision)), items, id())
        put(session.copy(requested = false, localRevision = revision))
    }

    private fun scheduleUpdates() {
        val day = LocalDate.now().toString()
        val now = LocalTime.now()
        val due = sessions.value.filter {
            it.active && !it.stopped && it.role == BlendRole.PARTICIPATE &&
                (it.requested && it.autoReply ||
                    it.automaticAt != null && it.scheduledDay != day && now >= LocalTime.parse(it.automaticAt))
        }
        for (session in due) guarded {
            sendSnapshot(session)
            if (session.automaticAt != null && now >= LocalTime.parse(session.automaticAt)) {
                put(current(session.id).copy(scheduledDay = day))
            }
            persist()
        }
    }

    private fun processMessages(chats: Map<String, List<BitchatMessage>>) = guarded {
        var dirty = false
        val incoming = mutableListOf<Triple<String, String, BlendFrame>>()
        for ((peer, messages) in chats) for (message in messages) {
            val entry = pending[message.id]
            if (entry != null && (message.deliveryStatus is DeliveryStatus.Delivered || message.deliveryStatus is DeliveryStatus.Read)) {
                if (BlendProtocol.decode(entry.text)?.data?.has("parts") == true) continue
                pending.remove(message.id)
                lastAttempt.remove(message.id)
                delivery.value = delivery.value + (message.id to "Delivered")
                dirty = true
            }
            if (!message.isPrivate || message.id in received || message.senderPeerID == null ||
                canonical(message.senderPeerID) != canonical(peer)) continue
            val frame = BlendProtocol.decode(message.content) ?: continue
            incoming += Triple(canonical(peer), message.id, frame)
        }
        // Relays can replay an update before its invitation or acceptance.
        for ((peer, messageId, frame) in incoming.sortedBy { (_, _, frame) ->
            when (frame.event) {
                BlendEvent.INVITE -> 0
                BlendEvent.ACCEPT -> 1
                BlendEvent.STOP -> 2
                else -> 3
            }
        }) {
            val known = sessions.value.firstOrNull { it.id == frame.blend }
            if (frame.event in setOf(BlendEvent.ACCEPT, BlendEvent.STOP, BlendEvent.PLAN, BlendEvent.PROGRESS, BlendEvent.REQUEST)
                && known == null) continue
            if (known != null && !known.active && !known.stopped &&
                frame.event in setOf(BlendEvent.PLAN, BlendEvent.PROGRESS, BlendEvent.REQUEST)) continue
            dirty = true
            received += messageId
            if (frame.data.has("parts")) receivePart(peer, frame) else receive(peer, frame)
        }
        if (dirty) persist()
    }

    private fun receive(peer: String, frame: BlendFrame) {
        if (isBlocked(peer)) return
        if (frame.event == BlendEvent.TRANSFER_ACK) {
            val transfer = frame.data.optString("transfer")
            pending.values.removeAll {
                val sent = BlendProtocol.decode(it.text)
                val matches = canonical(it.peer) == peer && sent != null && sent.blend == frame.blend &&
                    sent.data.has("parts") && sent.data.optString("transfer") == transfer
                if (matches) {
                    lastAttempt.remove(it.id)
                    delivery.value = delivery.value + (it.id to "Delivered")
                }
                matches
            }
            return
        }
        val session = sessions.value.firstOrNull { it.id == frame.blend }
        if (frame.event == BlendEvent.INVITE && session == null) {
            val mode = runCatching { BlendMode.valueOf(frame.data.getString("mode")) }.getOrNull() ?: return
            val role = remoteRole(frame) ?: return
            put(BlendSession(frame.blend, peer, mode, false, peerRole = role,
                requestedUpdates = BlendUpdateMode.parse(frame.data.optString("updates")).takeIf { role == BlendRole.SPECTATOR }))
            return
        }
        if (session == null || canonical(session.peer) != peer || session.stopped) return
        when (frame.event) {
            BlendEvent.ACCEPT -> if (session.owner && !session.active) {
                val role = remoteRole(frame) ?: return
                if (role != BlendRole.SPECTATOR || session.role != BlendRole.SPECTATOR)
                    put(session.copy(active = true, peerRole = role,
                        requested = session.role == BlendRole.PARTICIPATE && role == BlendRole.SPECTATOR))
            }
            BlendEvent.PLAN -> if (session.active && !session.owner && session.mode == BlendMode.CHECKLIST) {
                val revision = frame.data.optLong("revision")
                if (revision > session.remotePlanRevision) put(session.copy(
                    tasks = BlendProtocol.items(frame.data.optJSONArray("items")), remotePlanRevision = revision))
            }
            BlendEvent.PROGRESS -> if (session.active && session.peerRole == BlendRole.PARTICIPATE) {
                val revision = frame.data.optLong("revision")
                if (revision > session.remoteRevision) put(session.copy(
                    theirs = BlendProtocol.items(frame.data.optJSONArray("items"), BlendProtocol.MaxSnapshotItems),
                    receivedAt = System.currentTimeMillis(), remoteRevision = revision))
            }
            BlendEvent.REQUEST -> if (session.active && session.role == BlendRole.PARTICIPATE) {
                put(session.copy(requested = true))
                if (session.autoReply) scope.launch {
                    action {
                        val latest = current(session.id)
                        if (latest.autoReply && latest.requested && latest.active && !latest.stopped) sendSnapshot(latest)
                    }
                }
            }
            BlendEvent.STOP -> {
                pending.values.removeAll { it.peer == peer && BlendProtocol.decode(it.text)?.blend == session.id }
                put(session.copy(stopped = true, requested = false))
            }
            else -> Unit
        }
    }

    private fun scheduleKey(peer: String, blend: String) = "$peer:$blend"

    private fun saveSchedule(peer: String, blend: String, items: List<BlendItem>) {
        sharedSchedules.value = (sharedSchedules.value + (scheduleKey(peer, blend) to items))
            .entries.toList().takeLast(20).associate { it.toPair() }
    }

    private fun receivePart(peer: String, frame: BlendFrame) {
        if (isBlocked(peer)) return
        val session = sessions.value.firstOrNull { it.id == frame.blend }
        val revision = frame.data.optLong("revision")
        when (frame.event) {
            BlendEvent.PROGRESS -> if (session == null || canonical(session.peer) != peer ||
                !session.active || session.stopped || session.peerRole != BlendRole.PARTICIPATE ||
                revision <= session.remoteRevision) return
            BlendEvent.SCHEDULE -> Unit
            else -> return
        }
        val transfer = frame.data.optString("transfer")
        val count = frame.data.optInt("parts")
        val index = frame.data.optInt("part", -1)
        if (transfer.length != 36 || transfer.any { !it.isLetterOrDigit() && it != '-' } ||
            count !in 1..BlendProtocol.MaxParts || index !in 0 until count) return
        val array = frame.data.optJSONArray("items") ?: return
        val items = BlendProtocol.items(array)
        if (items.isEmpty() || items.size != array.length()) return
        val now = System.currentTimeMillis()
        transfers.values.removeAll { now - it.optLong("created") > 7 * 24 * 60 * 60 * 1000L }
        val key = "$peer:${frame.event}:${frame.blend}:$transfer"
        val assembly = transfers[key] ?: JSONObject().put("key", key).put("created", now)
            .put("revision", revision).put("count", count).put("chunks", JSONObject()).also {
                if (transfers.size >= 12) transfers.remove(transfers.keys.first())
                transfers[key] = it
            }
        if (assembly.optInt("count") != count || assembly.optLong("revision") != revision) return
        val chunks = assembly.getJSONObject("chunks")
        if (!chunks.has(index.toString())) chunks.put(index.toString(), array)
        if (chunks.length() != count) return
        val complete = (0 until count).flatMap { BlendProtocol.items(chunks.optJSONArray(it.toString())) }
        transfers.remove(key)
        if (complete.size > BlendProtocol.MaxSnapshotItems ||
            complete.distinctBy { it.day to it.id }.size != complete.size) return
        queue(peer, BlendFrame(BlendEvent.TRANSFER_ACK, frame.blend, JSONObject().put("transfer", transfer)))
        if (frame.event == BlendEvent.SCHEDULE) saveSchedule(peer, frame.blend, complete)
        else receive(peer, frame.copy(data = JSONObject().put("revision", revision)
            .put("items", BlendProtocol.pack(complete))))
    }

    private fun queueSnapshot(peer: String, frame: BlendFrame, items: List<BlendItem>, transfer: String) {
        val parts = BlendProtocol.parts(frame, items, transfer)
        if (parts.first().data.has("parts").not()) {
            queue(peer, frame)
            return
        }
        require(!isBlocked(peer)) { "This contact is blocked." }
        val entries = parts.map { Pending(id(), peer, BlendProtocol.encode(it)) }
        val superseded = pending.values.filter {
            val prior = BlendProtocol.decode(it.text)
            frame.event == BlendEvent.PROGRESS && canonical(it.peer) == canonical(peer) &&
                prior != null && prior.event == frame.event && prior.blend == frame.blend
        }
        require(pending.size - superseded.size + entries.size <= 2_048) { "Retry pending updates first." }
        superseded.forEach {
            pending.remove(it.id)
            lastAttempt.remove(it.id)
            delivery.value = delivery.value + (it.id to "Replaced by a newer update")
        }
        entries.forEach { pending[it.id] = it }
        delivery.value = delivery.value + (entries.first().id to "Waiting for a connection")
    }

    private fun remoteRole(frame: BlendFrame) = runCatching {
        BlendRole.valueOf(frame.data.getString("role"))
    }.getOrNull()

    private fun queue(peer: String, frame: BlendFrame) {
        require(!isBlocked(peer)) { "This contact is blocked." }
        require(pending.size < 2_100) { "Finish or retry your pending updates first." }
        val entry = Pending(id(), peer, BlendProtocol.encode(frame))
        if (frame.event == BlendEvent.PROGRESS || frame.event == BlendEvent.REQUEST) {
            pending.values.removeAll {
                val prior = BlendProtocol.decode(it.text)
                it.peer == peer && prior != null && prior.blend == frame.blend && prior.event == frame.event
            }
        }
        pending[entry.id] = entry
        delivery.value = delivery.value + (entry.id to "Waiting for a connection")
    }

    private suspend fun retryPending() {
        if (pending.isEmpty() ||
            (!AppStateStore.isChatActivityResumed && !MeshServicePreferences.isBackgroundEnabled(false))) return
        val mesh = MeshServiceHolder.getUnifiedOrCreate(app)
        val router = MessageRouter.getInstance(app, mesh)
        for (entry in pending.values.toList()) {
            if (entry.id !in pending || isBlocked(entry.peer)) continue
            val now = System.currentTimeMillis()
            if (now - (lastAttempt[entry.id] ?: 0) < 60_000L) continue
            val previousAttempt = lastAttempt.put(entry.id, now)
            val existing = AppStateStore.privateMessages.value[canonical(entry.peer)].orEmpty().any { it.id == entry.id }
            if (!existing && !AppStateStore.addPrivateMessageDurably(entry.peer, BitchatMessage(
                    id = entry.id, content = entry.text, sender = AppStateStore.nickname.value,
                    timestamp = Date(), isPrivate = true, senderPeerID = mesh.myPeerID,
                    deliveryStatus = DeliveryStatus.Sending
                ), forceRead = true)) continue
            val name = ContactDirectory.resolve(entry.peer).displayName.orEmpty()
            val multipart = BlendProtocol.decode(entry.text)?.data?.has("parts") == true
            val route = router.sendPrivate(entry.text, entry.peer, name, entry.id, queueInMemory = false,
                preferRelay = multipart && (previousAttempt == null || delivery.value[entry.id] != "Sent to private relay"))
            delivery.value = delivery.value + (entry.id to when (route) {
                MessageRouter.RouteResult.MESH -> "Sent nearby"
                MessageRouter.RouteResult.NOSTR -> "Sent to private relay"
                else -> "Waiting for a connection"
            })
        }
    }

    fun retry() = action { lastAttempt.clear() }

    fun panicClear(): Boolean {
        pending.clear()
        lastAttempt.clear()
        received.clear()
        transfers.clear()
        sharedSchedules.value = emptyMap()
        sessions.value = emptyList()
        delivery.value = emptyMap()
        return runCatching { store.clear() }.isSuccess
    }

    private fun action(work: suspend () -> Unit) {
        scope.launch {
            guarded {
                check(saved.isSuccess) { "Blend storage is unavailable." }
                work()
                persist()
                issue.value = null
                retryPending()
            }
        }
    }

    private inline fun guarded(work: () -> Unit) {
        if (saved.isFailure) return
        try {
            work()
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            issue.value = error.message ?: "Couldn't update Blend. Try again."
        }
    }

    private fun persist() = store.write(JSONObject()
        .put("sessions", JSONArray(sessions.value.map { it.json() }))
        .put("transfers", JSONArray(transfers.values.toList()))
        .put("schedules", JSONArray(sharedSchedules.value.map { (key, items) ->
            JSONObject().put("key", key).put("items", BlendProtocol.pack(items))
        }))
        .put("outbox", JSONArray(pending.values.map { it.json() }))
        .put("received", JSONArray(received.toList().takeLast(6_000))))

    private fun put(session: BlendSession) {
        sessions.value = sessions.value.filterNot { it.id == session.id } + session
    }

    private fun current(id: String) = sessions.value.first { it.id == id }
    private fun canonical(peer: String) = ContactDirectory.canonicalConversationId(peer)
    private fun id() = UUID.randomUUID().toString().uppercase()
    private fun JSONArray?.objects() = if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }

    companion object {
        @Volatile private var instance: BlendController? = null
        fun get(context: Context): BlendController = instance ?: synchronized(this) {
            instance ?: BlendController(context.applicationContext).also { instance = it }
        }
    }
}
