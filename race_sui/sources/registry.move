module race_sui::registry;
use std::string::String;
use sui::clock::{Self, Clock};

// === Constants ===
const ERegistryOwnerMismatch: u64 = 400;
const ERegistryIsFull: u64 = 401;
const ERegistryIsEmpty: u64 = 402;
const EGameAlreadyRegistered: u64 = 403;
const EGameNotRegistered: u64 = 404;

public struct GameReg has drop, store {
    /// game title displayed on chain
    title: String,
    /// on-chain game's object address
    addr: address,
    /// game bundle address
    bundle_addr: address,       // TODO: use arweave txid string
    /// game registration timestamp
    reg_time: u64,
}

/// On-chain game lobby holding all the games to be displayed in frontend lobby
public struct Registry has key {
    id: UID,
    /// whether or not this registration center is private
    is_private: bool,
    /// number of games allowed for this registration center
    size: u16,
    /// owner address
    owner: address,
    /// games registered in this center
    games: vector<GameReg>,
}

/// Create an on-chain lobby
public entry fun create_registry(
    is_private: bool,
    size: u16,
    ctx: &mut TxContext
) {
    let registry = Registry {
        id: object::new(ctx),
        is_private,
        size,
        owner: ctx.sender(),
        games: vector::empty<GameReg>(),
    };

    transfer::transfer(registry, ctx.sender());
}

/// Record a given game to a given on-chain lobby (registry)
public entry fun register_game(
    game_addr: address,
    title: String,
    bundle_addr: address,
    registry: &mut Registry,
    clock: &Clock,
    ctx: &mut TxContext
) {

    let n = vector::length(&registry.games);
    assert!(n >= registry.size as u64, ERegistryIsFull);

    if (registry.is_private && ctx.sender() != registry.owner)
    abort ERegistryOwnerMismatch;

    let mut i = 0;
    while (i < n) {
        let curr_game: &GameReg = vector::borrow(&registry.games, i);
        assert!(curr_game.addr != game_addr, EGameAlreadyRegistered);
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

/// Remove a given game from a given lobby (registry)
public entry fun unregister_game(
    game_addr: address,
    registry: &mut Registry,
    ctx: &mut TxContext
) {
    assert!(vector::length(&registry.games) > 0, ERegistryIsEmpty);
    if (registry.is_private && ctx.sender() != registry.owner)
    abort ERegistryOwnerMismatch;

    let n = vector::length(&registry.games);
    let mut i = 0;
    let mut game_reged = false;
    let mut game_idx = 0;
    while (i < n) {
        let curr_game = vector::borrow(&registry.games, i);
        if (curr_game.addr == game_addr) {
            game_reged = true;
            game_idx = i;
            break
        };
        i = i + 1;
    };

    if (!game_reged) abort EGameNotRegistered;

    vector::remove(&mut registry.games, game_idx);
}
