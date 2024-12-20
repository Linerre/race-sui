#[allow(unused_use)]
module race_sui::settle;
use std::string::{Self, String};
use sui::address;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use std::debug;


use race_sui::game::{Game, EntryLock};

// === Structs ===
public enum PlayerStatus {
    Normal,
    Left,
    Dropout,
}

public enum AssetChange {
    Add,
    Sub,
    NoChange,
}

// TODO: add phantom T
public struct Settle has copy, store, drop {
    // identical to settle_version
    player_id: u64,
    amount: u64,
    eject: bool,
}

// TODO: add phantom T
public struct Transfer has copy, store, drop {
    slot_id: u8,
    amount: u64,
}

// TODO: add phantom T
public struct Award has copy, store, drop {
    // identical to settle_version
    player_id: u64,
    bonus_identifier: String,
}

#[allow(unused_field)]
public struct SettleParams {
    settles: vector<Settle>,
    transfers: vector<Transfer>,
    awards: vector<Award>,
    checkpoint: vector<u8>,
    access_version: u64,
    settle_version: u64,
    next_settle_version: u64,
    entry_lock: Option<EntryLock>,
    reset: bool,
    accept_deposits: vector<u64>,
}

public fun create_settle(player_id: u64, amount: u64, eject: bool): Settle {
    Settle { player_id, amount, eject }
}

public fun create_transfer(slot_id: u8, amount: u64,): Transfer {
    Transfer { slot_id, amount }
}

public fun create_award(player_id: u64, bonus_identifier: String): Award {
    Award { player_id, bonus_identifier }
}

#[allow(unused_variable)]
public fun handle_settles(
    game: &mut Game,
    settles: vector<Settle>,
    ctx: &mut TxContext,
) {

}

#[allow(unused_variable)]
public fun handle_transfers(
    game: &mut Game,
    settles: vector<Transfer>,
    ctx: &mut TxContext,
) {

}
#[allow(unused_variable)]
public fun handle_bounses(
    game: &mut Game,
    settles: vector<Award>,
    ctx: &mut TxContext,
) {

}
#[allow(unused_variable)]
public fun settle(

    _ctx: &mut TxContext
) {

}
