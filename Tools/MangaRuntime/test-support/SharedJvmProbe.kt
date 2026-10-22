// App-owned regression code, compiled into test-only DEX by rebuild-manga-probe.py.
package app.animecompanion.probe

import kotlin.coroutines.*
import kotlinx.coroutines.*

object SharedJvmProbe {
    @JvmStatic fun main(args: Array<String>) {
        check(fieldContracts())
        check(timeUnitContracts())
        check(preciseTimeContracts())
        println("Owned field/time contracts pass on the reference JVM")
    }
    @JvmStatic fun nestedChildCompletion(): String = runBlocking {
        scheduledLog = ""
        val outer = async { launch { delay(2); scheduledLog = "nested done" }; "outer" }
        val value = outer.await()
        check(scheduledLog == "nested done")
        value
    }
    @JvmStatic fun nestedChildFailure(): String = try {
        runBlocking {
            val outer = async { launch { yield(); error("owned nested failure") }; "early" }
            outer.await()
            "missing failure"
        }
    } catch (error: IllegalStateException) { error.message!! }
    @JvmStatic fun nonCompletingTask() = runBlocking { suspendCoroutine<Unit> { } }
    @JvmStatic fun completableResults(): String = runBlocking {
        val deferred = CompletableDeferred<String>()
        launch { yield(); deferred.complete("owned completion") }
        awaitAll(deferred).single()
    }
    open class FieldBase {
        @JvmField var publicInt = 7
        private var hidden = 17
    }
    class FieldChild : FieldBase() {
        private var hidden = 23
        @JvmField var text: String? = "owned"
        @JvmField var decimal = 1.5f
        companion object {
            @JvmField var counter = 40L
            const val IMMUTABLE = 9
        }
    }
    @JvmStatic fun fieldContracts(): Boolean {
        val child = FieldChild()
        val public = FieldChild::class.java.getField("publicInt")
        check(public.declaringClass == FieldBase::class.java) { "field owner" }
        check(public.get(child) == 7 && public.getLong(child) == 7L) { "field widening read" }
        public.set(child, 42.toByte())
        check(child.publicInt == 42) { "field widening write" }
        try { public.setLong(child, 2L); return false } catch (_: IllegalArgumentException) {}
        try { public.getBoolean(child); return false } catch (_: IllegalArgumentException) {}
        try { public.getInt("wrong receiver"); return false } catch (_: IllegalArgumentException) {}
        try { public.getInt(null); return false } catch (_: NullPointerException) {}
        try { FieldChild::class.java.getDeclaredField("publicInt"); return false } catch (_: NoSuchFieldException) {}
        val base = FieldBase::class.java.getDeclaredField("hidden")
        val own = FieldChild::class.java.getDeclaredField("hidden")
        try { own.getInt(child); return false } catch (_: IllegalAccessException) {}
        own.isAccessible = true
        base.isAccessible = true
        check(own.getInt(child) == 23 && base.getInt(child) == 17) { "hidden field slots" }
        own.setInt(child, 29)
        check(base.getInt(child) == 17 && own.getInt(child) == 29) { "hidden field write" }
        own.isAccessible = false
        try { own.getInt(child); return false } catch (_: IllegalAccessException) {}
        val counter = FieldChild::class.java.getDeclaredField("counter")
        counter.setInt(null, 42)
        check(counter.get(null) == 42L && FieldChild.counter == 42L) { "static field" }
        val immutable = FieldChild::class.java.getDeclaredField("IMMUTABLE")
        immutable.isAccessible = true
        try { immutable.setInt(null, 10); return false } catch (_: IllegalAccessException) {}
        val text = FieldChild::class.java.getField("text")
        try { text.set(child, 4); return false } catch (_: IllegalArgumentException) {}
        try { text.setInt(child, 4); return false } catch (_: IllegalArgumentException) {}
        text.set(child, null)
        check(child.text == null) { "reference field" }
        val decimal = FieldChild::class.java.getField("decimal")
        decimal.setInt(child, 3)
        check(decimal.getDouble(child) == 3.0) { "floating field" }
        return true
    }
    @JvmStatic fun timeUnitContracts(): Boolean {
        val unit = java.util.concurrent.TimeUnit.SECONDS
        check(java.util.concurrent.TimeUnit.values().size == 7)
        check(java.util.concurrent.TimeUnit.valueOf("SECONDS") === unit)
        check(unit.toMillis(3) == 3_000L)
        check(unit.convert(-1_999, java.util.concurrent.TimeUnit.MILLISECONDS) == -1L)
        check(java.util.concurrent.TimeUnit.DAYS.toNanos(Long.MAX_VALUE) == Long.MAX_VALUE)
        check(java.util.concurrent.TimeUnit.DAYS.toNanos(Long.MIN_VALUE) == Long.MIN_VALUE)
        check(unit.convert(java.time.Duration.ofNanos(-1)) == 0L)
        check(java.util.concurrent.TimeUnit.NANOSECONDS.convert(java.time.Duration.ofSeconds(Long.MAX_VALUE)) == Long.MAX_VALUE)
        return true
    }
    @JvmStatic fun preciseTimeContracts(): Boolean {
        val before = java.time.Instant.parse("1969-12-31T23:59:59.999999999Z")
        val epoch = java.time.Instant.ofEpochSecond(0)
        check(before.toString() == "1969-12-31T23:59:59.999999999Z")
        check(before.plusNanos(1) == epoch)
        check(before != epoch && before.compareTo(epoch) < 0)
        check(before.hashCode() == java.time.Instant.ofEpochSecond(-1, 999_999_999).hashCode())
        check(epoch.minusNanos(1) == before)
        check(epoch.plusMillis(1).minusNanos(1).nano == 999_999)
        check(epoch.minusSeconds(1).plusNanos(999_999_999) == before)
        check(java.time.Instant.ofEpochSecond(1, 123_456_000).toString() == "1970-01-01T00:00:01.123456Z")
        val negative = java.time.Duration.ofNanos(-1)
        check(negative.toString() == "PT-0.000000001S")
        check(negative == java.time.Duration.ofSeconds(-1, 999_999_999))
        check(negative.hashCode() == java.time.Duration.ofSeconds(-1, 999_999_999).hashCode())
        check(negative.compareTo(java.time.Duration.ZERO) < 0)
        check(java.time.Duration.ofSeconds(-3662, 999_999_999).toString() == "PT-1H-1M-1.000000001S")
        return true
    }
    private var scheduled: Deferred<String>? = null
    private var scheduledLog = ""

    @JvmStatic fun prepareScheduled() {
        scheduledLog = ""
        scheduled = CoroutineScope(SupervisorJob()).async {
            scheduledLog += "start;"
            val first = async { delay(20); scheduledLog += "first;"; "one" }
            val second = async { yield(); scheduledLog += "second;"; "two" }
            val values = DeferredBag(listOf(first, second)).awaitAll()
            scheduledLog += "end;"
            values.joinToString("|")
        }
        check(!scheduled!!.isCompleted)
        check(scheduledLog == "start;")
    }
    private class DeferredBag(private val values: List<Deferred<String>>) : Collection<Deferred<String>> by values
    @JvmStatic fun finishScheduled(): String = runBlocking {
        val result = scheduled!!.await()
        check(scheduledLog == "start;second;first;end;")
        check(scheduled!!.isCompleted)
        result
    }
    @JvmStatic fun cancellationFinally(): Boolean = runBlocking {
        var cleaned = false
        val child = launch { try { delay(1_000) } finally { cleaned = true } }
        check(!child.isCompleted)
        child.cancel()
        check(child.isCancelled)
        child.join()
        cleaned && child.isCompleted
    }
    @JvmStatic fun scheduledFailure(): String = runBlocking {
        val owner = CoroutineScope(SupervisorJob())
        val slow = owner.async { delay(30); "late" }
        val failure = owner.async<String> { yield(); error("owned scheduled failure") }
        try { awaitAll(slow, failure); "missing failure" }
        catch (error: IllegalStateException) { slow.cancel(); error.message!! }
    }
    @JvmStatic fun timeoutAfterSuspension(): Boolean = runBlocking {
        try { withTimeout(5L) { delay(50L) }; false }
        catch (_: TimeoutCancellationException) { true }
    }
    @JvmStatic fun waitsForLaunchedChild(): Boolean = runBlocking {
        val owner = CoroutineScope(coroutineContext)
        owner.launch { delay(2); scheduledLog = "child finished" }
        true
    }
    @JvmStatic fun launchedChildResult(): String = scheduledLog

    private var saved: Continuation<String>? = null
    private var outcome = "pending"

    @JvmStatic fun begin() {
        saved = null
        outcome = "pending"
        val block: suspend () -> String = {
            val text = suspendCoroutine<String> { saved = it }
            "$text done"
        }
        block.startCoroutine(object : Continuation<String> {
            override val context = EmptyCoroutineContext
            override fun resumeWith(result: Result<String>) {
                outcome = result.fold({ it }, { "failure:${it.message}" })
            }
        })
    }

    @JvmStatic fun finish(fail: Boolean): String {
        val continuation = saved!!
        saved = null
        continuation.resumeWith(if (fail) Result.failure(IllegalStateException("owned")) else Result.success("owned"))
        return outcome
    }

    @JvmStatic fun doubleResume(): Boolean {
        val continuation = saved!!
        continuation.resume("owned")
        return try {
            continuation.resume("again")
            false
        } catch (_: IllegalStateException) {
            true
        }
    }

    open class Parent {
        open fun describe(prefix: String) = "parent:$prefix"
    }
    class Child : Parent() {
        override fun describe(prefix: String) = "child:$prefix"
    }
    class Numbers {
        fun widen(value: Long) = value + 1
        private fun secret(value: Int) = value * 2
        fun fail(): Nothing = throw IllegalArgumentException("owned method failure")
    }

    @JvmStatic fun reflectVirtual(): String = Parent::class.java
        .getMethod("describe", String::class.java)
        .invoke(Child(), "owned") as String

    @JvmStatic fun reflectWiden(): Long = Numbers::class.java
        .getMethod("widen", Long::class.javaPrimitiveType)
        .invoke(Numbers(), 41.toByte()) as Long

    @JvmStatic fun reflectPrivate(): Int = Numbers::class.java
        .getDeclaredMethod("secret", Int::class.javaPrimitiveType)
        .apply { isAccessible = true }
        .invoke(Numbers(), 21) as Int

    @JvmStatic fun reflectFailure(): String = try {
        Numbers::class.java.getMethod("fail").invoke(Numbers())
        "missing failure"
    } catch (error: java.lang.reflect.InvocationTargetException) {
        error.targetException.message!!
    }

    private class Key(val text: String) {
        override fun equals(other: Any?) = other is Key && text == other.text
        override fun hashCode() = text.hashCode()
    }

    @JvmStatic fun arrayContracts(): Boolean {
        val values = arrayOf<Any?>(null, Key("owned"), "last")
        check(values.first() == null) { "Probe assertion 82" }
        check(values.last() == "last") { "Probe assertion 83" }
        check(values.indexOf(Key("owned")) == 1) { "Probe assertion 84" }
        check(values.indexOf(null) == 0) { "Probe assertion 85" }
        check(values.indexOf("missing") == -1) { "Probe assertion 86" }
        try { emptyArray<Any>().last(); return false } catch (_: NoSuchElementException) {}
        return true
    }

    @JvmStatic fun dequeContracts(): Boolean {
        val deque = ArrayDeque<String?>(listOf("b", null))
        deque.addFirst("a")
        deque.addLast("c")
        val list: MutableList<String?> = deque
        check(list.size == 4 && list[1] == "b") { "Probe assertion 96" }
        check(list.set(1, "B") == "b") { "Probe assertion 97" }
        check(deque.removeFirst() == "a") { "Probe assertion 98" }
        check(deque.removeLast() == "c") { "Probe assertion 99" }
        check(deque.first() == "B" && deque.last() == null) { "Probe assertion 100" }
        deque.addAll(deque)
        check(deque.size == 4) { "Probe assertion 102" }
        val typed = deque.toTypedArray()
        check(typed.size == 4 && typed[0] == "B" && typed[1] == null) { "Probe assertion 104" }
        check(deque.iterator().next() == "B") { "Probe assertion 105" }
        deque.clear()
        check(deque.isEmpty() && deque.removeFirstOrNull() == null) { "Probe assertion 107" }
        try { deque.removeLast(); return false } catch (_: NoSuchElementException) {}
        try { ArrayDeque<Any>(-1); return false } catch (_: IllegalArgumentException) {}
        try { deque[0]; return false } catch (_: IndexOutOfBoundsException) {}
        return true
    }

    private var retainedMap: Map<String, String?>? = null
    private var defaultCalls = 0

    @JvmStatic fun prepareDefaultMap() {
        defaultCalls = 0
        val underlying = linkedMapOf<String, String?>("present" to "owned", "null" to null)
        val original: Map<String, String?> = underlying
        retainedMap = original.withDefault { key -> defaultCalls++; "default:$key" }
        underlying["later"] = "changed"
    }

    @JvmStatic fun defaultMapContracts(): Boolean {
        val map = retainedMap!!
        check(map["missing"] == null && defaultCalls == 0) { "Probe assertion 127" }
        check(map.getValue("null") == null && defaultCalls == 0) { "Probe assertion 128" }
        check(map.getValue("later") == "changed") { "Probe assertion 129" }
        check(map.getValue("missing") == "default:missing" && defaultCalls == 1) { "Probe assertion 130" }
        check(map.getValue("missing") == "default:missing" && defaultCalls == 2) { "Probe assertion 131" }
        check(!map.containsKey("missing") && map.size == 3) { "Probe assertion 132" }
        check(map.withDefault { "replacement" }.getValue("missing") == "replacement") { "Probe assertion 133" }
        check(defaultCalls == 2) { "Probe assertion 134" }
        val mutable = linkedMapOf<String, String?>().withDefault { "fallback" }
        mutable["written"] = "owned"
        check(mutable.getValue("written") == "owned") { "Probe assertion 137" }
        check(mutable.remove("written") == "owned") { "Probe assertion 138" }
        check(mutable.getValue("written") == "fallback") { "Probe assertion 139" }
        return true
    }

    private class WatchedText : CharSequence {
        var reads = 0
        override val length = 12
        override fun get(index: Int): Char {
            reads++
            check(index < 6) { "Sequence evaluated an unrequested line" }
            return "owned\nunused"[index]
        }
        override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = error("Not required")
    }

    private var retainedLines: Sequence<String>? = null
    private var lineCalls = 0

    @JvmStatic fun prepareLines() {
        lineCalls = 0
        retainedLines = "\r\nowned\rlast\n".lineSequence().map { lineCalls++; it.trim() }.filter { it.isNotEmpty() }
        check(lineCalls == 0) { "Probe assertion 160" }
    }

    @JvmStatic fun lineContracts(): Boolean {
        val text = WatchedText()
        check(text.lineSequence().first { it.isNotBlank() } == "owned") { "Probe assertion 165" }
        check(text.reads == 6) { "Probe assertion 166" }
        check(retainedLines!!.first() == "owned" && lineCalls == 2) { "Probe assertion 167" }
        check(retainedLines!!.toList() == listOf("owned", "last")) { "Probe assertion 168" }
        check("a\r\nb\rc\n".lineSequence().toList() == listOf("a", "b", "c", "")) { "Probe assertion 169" }
        check("".lineSequence().toList() == listOf("")) { "Probe assertion 170" }
        val mutable = StringBuilder("before")
        val lines = mutable.lineSequence()
        mutable.append(" after")
        check(lines.first() == "before after") { "Probe assertion 174" }
        return true
    }

    @JvmStatic fun sequenceConsumerContracts(): Boolean {
        val sequence = "owned\nother\nowned".lineSequence().map { it.trim() }
        check(sequence.joinToString("|") == "owned|other|owned")
        check(sequence.toSet().size == 2)
        check(sequence.distinct().toList() == listOf("owned", "other"))
        check(sequence.count() == 3)
        check(sequence.lastOrNull() == "owned")
        check(sequence.mapNotNull { if (it == "owned") it else null }.toList() == listOf("owned", "owned"))
        return true
    }

    private class ChosenRandom : kotlin.random.Random() {
        override fun nextBits(bitCount: Int): Int = error("Unexpected random entry point")
        override fun nextInt(from: Int, until: Int): Int {
            check(from == 97 && until == 123) { "Probe assertion 181" }
            return 122
        }
    }

    @JvmStatic fun characterContracts(): Boolean {
        val units = "A\uD83D\uDE00Z".toList()
        check(units.size == 4 && units[1].code == 0xD83D && units[2].code == 0xDE00) { "Probe assertion 188" }
        val iterator = ('\uFFFE'..'\uFFFF').iterator()
        check(iterator.nextChar().code == 65534) { "Probe assertion 190" }
        check(iterator.nextChar().code == 65535 && !iterator.hasNext()) { "Probe assertion 191" }
        try { iterator.nextChar(); return false } catch (_: NoSuchElementException) {}
        val boxed: Iterator<Char> = ('a'..'b').iterator()
        check(boxed.next() == 'a' && boxed.next() == 'b' && !boxed.hasNext()) { "Probe assertion 194" }
        check(('a'..'z').random(ChosenRandom()) == 'z') { "Probe assertion 195" }
        try { ('z'..'a').random(ChosenRandom()); return false } catch (_: NoSuchElementException) {}
        return true
    }
}
