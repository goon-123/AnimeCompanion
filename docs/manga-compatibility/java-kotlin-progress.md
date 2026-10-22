# Shared Java/Kotlin task progress

Task: finish shared coroutine handling, typed collections, reflection and
date/time support needed by manga extensions, including Komga and JinmanTiantang.

| Delivery | Rough completion estimate | Evidence |
| --- | --- | --- |
| Merged build 57 / PR #38 | 80% | Komga/Jinman owned reading flows; continuation resume, method/property reflection and eight observed date/reflection blockers covered |
| Merged build 58 / PR #39 | 85% | Nine observed collection/type/string blockers removed; compiled Kotlin contracts; WaManga/HentaiHere complete owned flows |
| Proposed build 59 | 90% | Cooperative delayed/pending tasks, ordered awaitAll on guest collections, cancellation/finally and nested-child completion; real field access and field-owner bytecode fix; nanosecond value contracts and saturating TimeUnit conversions |

These are engineering estimates for this roadmap item. They are not percentages
of the Java/Kotlin API surface, all working extensions or development time.
Do not raise the estimate merely because more methods were registered. Each
subsequent PR should report the previous and new estimate, exact verified
behavior, validation and known remaining gaps to the user.

## What works in the covered paths

- Komga source 0 and JinmanTiantang have exact-version owned reading evidence.
- Compiler-produced guest code actually suspends/resumes across GC, retains
  failures, rejects duplicate resume and exercises lazy start/cancellation.
- A bounded VM-local queue schedules delays/yield, pending await/join/awaitAll
  and nested children on one guest thread. Parent failures cancel dependent work;
  supervisor isolation, finally completion and timeout restoration have tests.
- Real field lookup/get/set observes declaring classes (including hidden fields),
  access overrides, static initialization, primitive widening and reference types.
  The pre-existing fieldless host delegate injection ABI is preserved separately.
- Instant/Duration equality, hashes, ordering and strings preserve nanoseconds;
  TimeUnit converts every standard unit with signed saturation/truncation.
- Typed reference-array copies/concatenation, ordered sets, deque operations,
  array search and map defaults have execution tests.
- Method and Kotlin property references dispatch actual guest code.
- Common Java/Kotlin dates, durations, localized fields, fractional parsing and
  zone/calendar arithmetic have covered contracts.
- Lazy line sequences stop at the requested result, retain callbacks through GC
  and preserve delimiter/UTF-16 behavior in the covered operations.

## Remaining work before calling this item finished

1. True parallel-task execution, full dispatcher/CoroutineStart behavior,
   cancellation handlers/channels/flows and other coroutine APIs beyond the
   covered cooperative scheduling paths. Host HTTP remains synchronous.
2. Advanced reflection, including dynamic proxies, constructors/generic type
   metadata and remaining Kotlin reflection entry points required by packages.
3. Remaining date/time formatter patterns/units, calendar range and precision
   contracts; formatter/chapter transport is still millisecond based.
4. Additional typed/mutable collection and sequence contracts, iterator
   invalidation/views and other helpers reached by the frozen catalog.
5. Further exact-APK and native reading validation as those paths become
   reachable. A generic empty-response preflight is not reading evidence.

MangoLibreria 1.6.4 now enumerates and exposes settings after the TimeUnit class
fix. Reading still stops at the separate OkHttp Builder connectTimeout(TimeUnit)
overload; it is not a newly verified reader. Unsupported completion sources fail
explicitly; the scheduler does not manufacture a completed value or skip timers.

JavaScript array-result conversion (currently blocking Comicabc's reader),
source metadata transport, browser/authentication, crypto/TLS and unrelated
Android/Okio APIs belong to the wider extension-compatibility backlog. They are
not counted as completion of this Java/Kotlin item.
