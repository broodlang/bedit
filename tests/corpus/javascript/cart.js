import { a, b } from "./x.js";
// ^^^ keyword       ^^^^^^^^ string

// Greets.
// ^^^^^^^ comment
export function greet(name, options = {}) {
  //            ^^^^^ definition
  const parts = [
    "hello",
    `dear ${name}`,
  ];
  if (options.loud) {
    return parts.join(" ").toUpperCase();
    //                     ^^^^^^^^^^^ function
  }
  switch (name) {
    case "x":
      return null;
      //     ^^^^ constant
    default:
      break;
  }
  return this.format(parts, 42, true);
  //                        ^^ number
  //                            ^^^^ constant
}

class Greeter {
  greet() {
    return greet("world");
  }
}
