// the greeter
// ^^^^^^^^^^^ comment
package app.greet;

import java.util.List;

/** A greeter. */
// ^^^^^^^^^^^^^^ comment
@Service
public class Greeter<T> extends Base implements Runnable {
    //       ^^^^^^^ special    ^^^^ special
    private static final int MAX = 0x10;
    //                   ^^^ special
    //                             ^^^^ number
    private final String name;

    public Greeter(String name) {
        // ^^^^^^^ definition
        this.name = name;
        // ^ keyword
    }

    @Override
    // ^^^^^^ special
    public void run() {
        //      ^^^ definition
        List<String> names = List.of("a", "b");
        //                           ^ string
        for (String each : names) {
            if (each.isEmpty()) {
                //   ^^^^^^^ function
                continue;
            } else {
                System.out.println(greet(each, 1.5, true));
                //         ^^^^^^^ function    ^^^ number
                //                 ^^^^^ function   ^^^^ constant
            }
        }
        switch (names.size()) {
            case 0:
                break;
            default:
                names.forEach(item -> {
                    log(item);
                });
        }
        String message = STR."hi \{name.trim()} done";
        //                    ^^^ string
        //                       ^^ special
        //                         ^^^^ plain
        //                              ^^^^ function
        String block = """
            text block
            """;
        Object nothing = null;
        //               ^^^^ constant
        char letter = 'c';
        //            ^^^ string
        try {
            work(new int[] {1, 2});
        } catch (RuntimeException e) {
            throw e;
        } finally {
            super.close();
            // ^^ keyword
        }
    }

    int kind(String name) {
        return switch (name) {
            case "x" -> 1;
            default -> {
                yield 2;
            }
        };
    }

    private String greet(String who, double weight, boolean loud) {
        return "hello " + who;
    }
}

interface Shape {
    //    ^^^^^ special
    double area();
    //     ^^^^ definition
}

enum Color {
    RED,
    // <- constant
    GREEN;

    Color next() {
        return GREEN;
    }
}

record Point(int x, int y) {}
//     ^^^^^ special
