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

    // A handle Rust owns. No close call anywhere below: going out of scope
    // runs the native destructor.
    let mut tally = calculator::Tally::new().expect("the constructor succeeds");
    println!("tally.add(40) = {}", tally.add(40));
    println!("tally.add(2) = {}", tally.add(2));
    println!("tally.peek() = {}", tally.peek());

    // A view borrowed out of the tally, whose lifetime is that borrow.
    {
        let mut reading = tally.borrow_reading();
        println!("reading.total() = {}", reading.total());
    }

    // A buffer the library allocated and Rust now owns. Nothing is copied,
    // and it is released when it goes out of scope.
    let rendered = tally.render().expect("rendering succeeds");
    println!("tally.render() = {}", rendered.to_str_lossy());

    drop(rendered);
    drop(tally);
    println!("live bytes after drop = {}", calculator::live_bytes());
}
