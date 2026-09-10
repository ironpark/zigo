//! The Rust mirror of `examples/00-quick-start`'s Go demo.

fn main() {
    // A scalar, which is the whole of the Go quick start.
    println!("2 + 3 = {}", calculator::add(2, 3));
    // A borrowed slice.
    println!("sum([1, 2, 3]) = {}", calculator::sum(&[1, 2, 3]));
    // An error union, which Rust receives as a `Result`.
    match calculator::divide(7, 2) {
        Ok(value) => println!("7 / 2 = {value}"),
        Err(error) => println!("7 / 2 failed: {error}"),
    }
    match calculator::divide(1, 0) {
        Ok(value) => println!("1 / 0 = {value}"),
        Err(error) => println!("1 / 0 failed: {error}"),
    }
}
