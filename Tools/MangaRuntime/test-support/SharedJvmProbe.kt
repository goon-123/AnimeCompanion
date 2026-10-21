// App-owned regression code, compiled into test-only DEX by rebuild-manga-probe.py.
package app.animecompanion.probe

import kotlin.coroutines.*

object SharedJvmProbe {
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
}
