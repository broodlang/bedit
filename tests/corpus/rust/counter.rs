use std::collections::{HashMap, HashSet};
// <- keyword

// A counter.
// ^^^^^^^^^^ comment
#[derive(Debug)]
// ^^^^^^^^^^^^^ special
pub struct Counter<'a> {
    //     ^^^^^^^ special
    name: &'a str,
    seen: HashMap<String, usize>,
    //                    ^^^^^ special
}

impl<'a> Counter<'a> {
    pub fn new(name: &'a str) -> Self {
        // ^^^ definition
        Self {
            name,
            seen: HashMap::new(),
            //             ^^^ function
        }
    }

    /// Count each word.
    // ^^^^^^^^^^^^^^^^^ comment
    pub fn add(&mut self, words: &[&str]) -> usize {
        let mut total = 0;
        //              ^ number
        for word in words {
            match word.len() {
                0 => continue,
                n if n > 10 => {
                    total += 2;
                }
                _ => total += 1,
            }
            *self.seen.entry(word.to_string()).or_insert(0) += 1;
            //                                 ^^^^^^^^^ function
        }
        if total > 0 {
            println!("{}: {}", self.name, total);
            // ^^^^ function
            //       ^^^^^^^^ string
        } else {
            eprintln!("nothing");
        }
        words.iter().for_each(|word| {
            let _ = HashSet::<&str>::from([*word]);
        });
        total
    }
}

enum Shape {
    Circle(f64),
    Rect { w: f64, h: f64 },
}
