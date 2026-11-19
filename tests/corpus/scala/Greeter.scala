// the greeter
// ^^^^^^^^^^^ comment
package app.greet

import scala.util.{Failure, Success}

/** A greeter. */
// ^^^^^^^^^^^^^^ comment
@deprecated("old", "1.0")
// <- special
case class Point(x: Int, y: Int = 0)
// ^ keyword
//         ^^^^^ special

sealed trait Shape {
  // ^ keyword
  //         ^^^^^ special
  def area: Double
  //  ^^^^ definition
}

object Registry {
  //   ^^^^^^^^ special
  final val Max = 0x10L
  //              ^^^^^ number
  private var names: List[String] = Nil
}

enum Color(val rgb: Int) {
  case Red extends Color(0xff0000)
  //   ^^^ constant
  case Green extends Color(0x00ff00)
}

class Greeter[T](name: String) extends Base with Runnable {
  override def run(): Unit = {
    //         ^^^ definition
    //                ^^^^ special
    val names = List("a", "b")
    //               ^^^ string
    for (each <- names) {
      if (each.isEmpty) {
        println("empty")
        // ^^^^ function
      } else {
        println(greet(each, 1.5, true))
        //                  ^^^ number
        //                       ^^^^ constant
      }
    }
    val kind = names.size match {
      //                  ^^^^^ keyword
      case 0 => "none"
      case 1 =>
        "one"
      case _ => "many"
    }
    names.foreach { item => log(item) }
    //    ^^^^^^^ function
    val message = s"hi $name and ${name.length} done"
    //            ^ function       ^^^^ plain
    //             ^^^^^ string
    //                  ^^^^ plain
    val block =
      """raw
        |text""".stripMargin
    val nothing: String = null
    //                    ^^^^ constant
    val letter = 'c'
    //           ^^^ string
    try {
      work(Array(1, 2))
    } catch {
      case e: RuntimeException => throw e
    }
  }

  private def greet(
      who: String,
      weight: Double,
      loud: Boolean
  ): String =
    "hello " + who
}

def shout(text: String): String = text.toUpperCase
//  ^^^^^ definition

class Braceless(name: String):
  def greet(): String =
    val count = 1
    s"hi $name"

  def describe(x: Int): String =
    x match
      case 1 => "one"
      case _ =>
        "many"
