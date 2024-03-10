set dotenv-load

sui-local:
  RUST_LOG="off,sui_node=info" cargo run --bin sui-test-validator

build:
  sui move build
