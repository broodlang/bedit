// the greeter
// ^^^^^^^^^^^ comment
package app.greet

import kotlin.math.max

/** A greeter. */
// ^^^^^^^^^^^^^^ comment
@JvmInline
// <- special
value class Name(val value: String)
//                   ^^^^^ variable

data class Point(val x: Int, val y: Int = 0)
// ^ keyword
//         ^^^^^ special

sealed interface Shape {
    fun area(): Double
    //  ^^^^ definition
}

enum class Color(val rgb: Int) {
    RED(0xFF0000),
    // <- constant
    //  ^^^^^^^^ number
    GREEN(0x00FF00);

    fun next(): Color = GREEN
}

object Registry {
    // ^^^^^^^^ special
    private const val MAX = 10L
    //                      ^^^ number
    val names = mutableListOf<String>()
}

class Greeter<T : Any>(private val name: String) : Base(), Runnable {
    //                                                     ^^^^^^^^ special
    companion object {
        // ^^ keyword
        fun create(): Greeter<String> = Greeter("x")
    }

    init {
        require(name.isNotEmpty())
    }

    override fun run() {
        //       ^^^ definition
        val names = listOf("a", "b")
        //          ^^^^^^ function
        //                 ^^^ string
        for (each in names) {
            if (each.isEmpty()) {
                //   ^^^^^^^ function
                continue
            } else {
                println(greet(each, 1.5, true))
                //                  ^^^ number
                //                       ^^^^ constant
            }
        }
        val kind =
            when (names.size) {
                0 -> "none"
                1 -> {
                    "one"
                }
                else -> "many"
            }
        names.forEach {
            // ^^^^^^ function
            log(it)
        }
        val message = "hi $name and ${name.length} done"
        //            ^^^^^ string
        //                 ^^^^ plain
        //                     ^^^^^^^ string
        val block =
            """
            raw ${kind}
            """
                .trimIndent()
                // ^^^^^^^^ function
        val nothing: String? = null
        //                     ^^^^ constant
        val letter = 'c'
        //           ^^^ string
        try {
            work(arrayOf(1, 2))
        } catch (e: RuntimeException) {
            throw e
        } finally {
            super.toString()
        }
    }

    private fun greet(
        who: String,
        weight: Double,
        loud: Boolean,
    ): String {
        return "hello " + who
    }
}

fun String.shout(): String = uppercase()
//         ^^^^^ definition
