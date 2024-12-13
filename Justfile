set dotenv-load

local:
    RUST_LOG="off,sui_node=info" cargo run --bin sui-test-validator

build:
    cd race_sui && sui move build

byte:
    cd race_sui && sui client verify-bytecode-meter

addr:
    cd race_sui && sui client address

publish:
    cd race_sui && sui client publish --json --force

test:
    cd race_sui && sui move test
