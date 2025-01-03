#[allow(unused_use)]
module race_sui::settle;
use std::string::{Self, String};
use sui::address;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use std::debug;
use race_sui::game::{Game, EntryLock};

// === Errors ===
const ESettlePlayerNotFound: u64 = 450;
const ESettleCoinMismatch: u64 = 451;

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

public struct Settle has drop, store {
    // identical to settle_version
    player_id: u64,
    amount: u64,
    eject: bool,
}

public struct Pay has drop, store {
    receiver: address,
    amount: u64,
    coin_idx: u64,
}

public struct Transfer has drop, store {
    slot_id: u8,
    amount: u64,
}

public struct Award has drop, store {
    // identical to settle_version
    player_id: u64,
    bonus_identifier: String,

}
#[allow(unused_field)]
public struct SettleParams has drop {
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

public fun handle_settles<T>(
    game: &mut Game<T>,
    settles: vector<Settle>,
    mut coins: vector<Coin<T>>,
    ctx: &mut TxContext,
) {
    let mut pays: vector<Pay> = vector::empty();
    let mut i = 0;
    let n = vector::length(&settles);
    let m = game.player_num() as u64;
    while (i < n) {
        let mut found =  false;
        let mut j = 0;
        let settle = vector::borrow(&settles, i);
        while (j < m) {
            if (game.is_settle_player(j, settle.player_id)) {
                vector::push_back(
                    &mut pays,
                    Pay {
                        receiver: game.player_addr(j),
                        amount: settle.amount,
                        coin_idx: i
                    }
                );
                if (settle.eject) {
                    game.eject_player(j);
                };
                found = true;
                break
            };
            j = j + 1;
        };
        if (!found) abort ESettlePlayerNotFound;
        i = i + 1;
    };

    i = 0;
    let k = vector::length(&pays);
    assert!(n == k, ESettleCoinMismatch);
    while (i < k) {
        let payinfo = vector::borrow(&pays, i);
        let payment: Balance<T> = game.split_balance(payinfo.amount);
        let mut paycoin: Coin<T> = vector::remove(&mut coins, payinfo.coin_idx);
        paycoin.join(coin::from_balance(payment, ctx));
        transfer::public_transfer(paycoin, payinfo.receiver);
        i = i + 1;
    };
    vector::destroy_empty(coins); // if any coin left unconsumed, abort with error
}

#[allow(unused_variable)]
public fun handle_transfers<T>(
    game: &mut Game<T>,
    settles: vector<Transfer>,
    ctx: &mut TxContext,
) {

}
#[allow(unused_variable)]
public fun handle_bounses<T>(
    game: &mut Game<T>,
    settles: vector<Award>,
    ctx: &mut TxContext,
) {

}
#[allow(unused_variable)]
public fun settle(

    _ctx: &mut TxContext
) {

}
