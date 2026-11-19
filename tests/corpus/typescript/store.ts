// A small typed store.
// ^^^^^^^^^^^^^^^^^^^^ comment
import { EventEmitter } from "events";
// ^^^ keyword               ^^^^^^^^ string

export interface Item {
  //   ^^^^^^^^^ keyword
  id: number;
  //  ^^^^^^ special
  name: string;
  tags?: string[];
}

type Listener = (item: Item) => void;
//   ^^^^^^^^ special

enum Kind {
  Plain,
  Fancy = "fancy",
}

export class Store<T extends Item> extends EventEmitter {
  //         ^^^^^ special
  private items: Map<number, T> = new Map();
  readonly limit = 0x10;
  //               ^^^^ number

  constructor(private readonly label: string) {
    // ^^^^^^ definition
    super();
    // ^^ keyword
  }

  add(item: T): boolean {
    if (this.items.size >= this.limit) {
      return false;
    }
    this.items.set(item.id, item);
    this.emit("added", item);
    //   ^^^^ function
    return true;
  }

  async find(id: number): Promise<T | undefined> {
    const found = this.items.get(id) ?? null;
    //                                  ^^^^ constant
    return found === null ? undefined : found;
  }

  describe(): string {
    return `${this.label}: ${this.items.size} items, ${Kind.Fancy}`;
  }
}

export function subscribe(store: Store<Item>, listener: Listener): void {
  //            ^^^^^^^^^ definition
  store.on("added", (item: Item) => {
    listener(item);
  });
}
