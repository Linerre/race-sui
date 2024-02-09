module race_sui::regisry {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};

    struct GameReg {
        addr: address,
        bundle_addr: address,
        reg_time: u64,
    }

    struct Registry has key {
        id: UID,
        is_private: bool,
        size: u64,
        owner: address,
        // games: Vector<GameReg>,
    }

}
