use std::io::{self, Write};

use clap::Parser;

#[derive(Parser)]
#[clap(author, version, about, long_about = None)]
struct Cli {
    /// Number of lines to redirect
    #[clap(short)]
    number: Option<usize>,
}

fn main() -> io::Result<()> {
    let cli = Cli::parse();

    let mut buffer = String::new();

    let stdin = io::stdin();
    for _ in 0..cli.number.unwrap_or(1) {
        stdin.read_line(&mut buffer)?;
        eprint!("{}", buffer);
        buffer.clear();
    }

    loop {
        let bytes_read = stdin.read_line(&mut buffer)?;
        if bytes_read == 0 {
            break
        }

        let res = io::stdout().write_all(buffer.as_bytes());
        if res.is_err() {
            break
        }
        buffer.clear();
    }

    Ok(())
}
