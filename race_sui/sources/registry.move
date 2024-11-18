#[allow(duplicate_alias)]
module race_sui::registry {
    use std::string::String;
    use std::vector;
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    // === Constants ===
    const ERegistryOwnerMismatch: u64 = 400;
    const ERegistryIsFull: u64 = 401;
    const ERegistryIsEmpty: u64 = 402;
    const EDuplicateGameRegistration: u64 = 403;
    const EGameNotRegistered: u64 = 404;

    public struct GameReg has drop, store {
        /// game title/name displayed on chain
        title: String,
        /// on-chain game's object address
        addr: address,
        bundle_addr: address,
        reg_time: u64,
    }

    public struct Registry has key {
        id: UID,
        /// whether or not this registration center is private
        is_private: bool,
        /// number of games allowed for this registration center
        size: u64,
        /// owner address
        owner: address,
        /// games registered in this center
        games: vector<GameReg>,
    }


    public fun create(owner: address, is_private: bool, size: u64, ctx: &mut TxContext) {
        let registry = Registry {
            id: object::new(ctx),
            is_private,
            size,
            owner,
            games: vector::empty<GameReg>(),
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

        let n = vector::length(&registry.games);
        assert!(n >= registry.size, ERegistryIsFull);

        // Comparison consumes the value, so use reference to avoid the consumption
        // See: https://move-language.github.io/move/equality.html#restrictions
        if (registry.is_private && &tx_context::sender(ctx) != &registry.owner)
            abort ERegistryOwnerMismatch;

        let mut i = 0;
        while (i < n) {
            let curr_game: &GameReg = vector::borrow(&registry.games, i);
            assert!(&curr_game.addr != &game_addr, EDuplicateGameRegistration);
            i = i + 1;
        };

        let game_reg = GameReg {
            addr: game_addr,
            title,
            bundle_addr,
            reg_time: clock::timestamp_ms(clock),
        };

        vector::push_back(&mut registry.games, game_reg);
    }

    public fun unregister_game(game_addr: address, registry: &mut Registry, ctx: &mut TxContext) {
        assert!(vector::length(&registry.games) > 0, ERegistryIsEmpty);
        if (registry.is_private && &tx_context::sender(ctx) != &registry.owner)
            abort ERegistryOwnerMismatch;

        let n = vector::length(&registry.games);
        let mut i = 0;
        let mut game_reged = false;
        let mut game_idx = 0;
        while (i < n) {
            let curr_game = vector::borrow(&registry.games, i);
            if (&curr_game.addr == &game_addr) {
                game_reged = true;
                game_idx = i;
                break
            };
            i = i + 1;
        };

        if (!game_reged) abort EGameNotRegistered;

        vector::remove(&mut registry.games, game_idx);
    }
}
