package com.bitchat.android.model

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class PrivateMessagePacketTest {
    @Test
    fun shortTextKeepsOriginalWireFormat() {
        val bytes = PrivateMessagePacket("id", "Hi").encode()
        assertArrayEquals(byteArrayOf(0, 2, 105, 100, 1, 2, 72, 105), bytes)
        assertEquals(PrivateMessagePacket("id", "Hi"), PrivateMessagePacket.decode(checkNotNull(bytes)))
    }

    @Test
    fun studyFrameSurvivesMultipleFieldsAndUtf8Splits() {
        val original = PrivateMessagePacket("same-id", "Shared schedule.\nprepdesk-blend/1 " + "漢字".repeat(230))
        val bytes = original.encode()
        assertNotNull(bytes)
        assertEquals(original, PrivateMessagePacket.decode(checkNotNull(bytes)))
    }

    @Test
    fun rejectsOversizeOrTruncatedPackets() {
        assertNull(PrivateMessagePacket("id", "x".repeat(256)).encode())
        assertNull(PrivateMessagePacket("id", "\nprepdesk-blend/1 " + "x".repeat(3_501)).encode())
        val frame = checkNotNull(PrivateMessagePacket("id", "\nprepdesk-blend/1 " + "x".repeat(400)).encode())
        assertNull(PrivateMessagePacket.decode(frame.copyOf(frame.size - 1)))
    }
}
