module 0x0::registry {
    use std::string::{Self, String};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct GameReg has drop, store {
        /// game title/name displayed on chain
        title: String,
        /// on-chain game's object id
        addr: address,
        bundle_addr: address,
        reg_time: u64,
    }

    struct Registry has key {
        id: UID,
        /// whether or not this registration center is private
        is_private: bool,
        /// number of games allowed for this registration center
        size: u64,
        /// owner address
        owner: address,
        /// games registered in this center
        games: Table<address, GameReg>,
    }

    // === Constants ===
    const ERegistryOwnerMismatch: u64 = 4;
    const ERegistryIsFull: u64 = 5;
    const ERegistryIsEmpty: u64 = 6;
    const EDuplicateGameRegistration: u64 = 7;
    const EGameNotFound: u64 = 7;

    public fun create(owner: address, is_private: bool, size: u64, ctx: &mut TxContext) {
        let registry = Registry {
            id: object::new(ctx),
            is_private,
            size,
            owner,
            games: table::new<address, GameReg>(ctx),
        };

        transfer::transfer(registry, tx_context::sender(ctx));
    }

    public fun register_game(
        game_addr: address,
        title: String,
        bundle_addr: address,
        registry: &mut Registry,
        clock: &Clock,
        ctx: &mut TxContext
    ) {

        assert!(table::length(&registry.games) >= registry.size, ERegistryIsFull);

        if (registry.is_private && tx_context::sender(ctx) != registry.owner)
            abort ERegistryOwnerMismatch;

        assert!(!table::contains(&registry.games, game_addr), EDuplicateGameRegistration);

        let game_reg = GameReg {
            addr: game_addr,
            title,
            bundle_addr,
            reg_time: clock::timestamp_ms(clock),
        };

        table::add(&mut registry.games, game_addr, game_reg);

    }

    public fun unregister_game(game_addr: address, registry: &mut Registry, ctx: &mut TxContext) {
        assert!(table::length(&registry.games) > 0, ERegistryIsEmpty);
        if (registry.is_private && tx_context::sender(ctx) != registry.owner)
            abort ERegistryOwnerMismatch;

        if (!table::contains(&registry.games, game_addr)) abort EGameNotFound;

        table::remove(&mut registry.games, game_addr);

    }
}