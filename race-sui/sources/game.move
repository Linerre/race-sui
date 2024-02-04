module race_sui::game {
    use sui::object::{Self, UID};

    struct Game has key {
        id: UID,
        title: String,
        bundle_addr: String,
        transactor_addr: String,
        access_version: u64,
        settle_version: u64,
        max_players: u16,
    }
}
