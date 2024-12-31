#[allow(unused_use)]
module race_sui::settle;
use std::string::{Self, String};
use sui::address;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use std::debug;
use race_sui::game::{Bonus, Game, EntryLock, unpack_coin_bonus, unpack_obj_bonus};
use race_sui::recipient::{RecipientSlot};

// === Errors ===
const ESettlePlayerNotFound: u64 = 450;
const ESettleCoinMismatch: u64 = 451;
const EInvalidSettleTxSender: u64 = 453;
const EInvalidTransferTxSender: u64 = 454;
const EInvalidBonusTxSender: u64 = 455;
const EBonusNotFoundInGame: u64 = 456;
const EInvalidBonusReceiver: u64 = 457;
const EInvalidBonusIdentifier: u64 = 458;

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

public struct Award has drop, store {
    // identical to settle_version
    player_id: u64,
    bonus_id: ID,
    bonus_identifier: String,

}
#[allow(unused_field)]
public struct SettleParams<phantom T> {
    settles: vector<Settle>,
    // transfers: vector<Rake<T>>,
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

public fun create_award(player_id: u64, bonus_id: ID, bonus_identifier: String): Award {
    Award { player_id, bonus_id, bonus_identifier }
}

public fun handle_settles<T>(
    game: &mut Game<T>,
    settles: vector<Settle>,
    mut coins: vector<Coin<T>>,
    ctx: &mut TxContext,
) {
    assert!(game.validat_sender(&ctx.sender()), EInvalidSettleTxSender);
    let mut pays: vector<Pay> = vector::empty();
    let mut i = 0;
    let n = vector::length(&settles);
    let m = game.player_num() as u64;
    while (i < n) {
        let mut found =  false;
        let mut j = 0;
        let settle = vector::borrow(&settles, i);
        while (j < m) {
            if (game.validate_player_at_idx(j, settle.player_id)) {
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

public fun handle_transfer<T>(
    game: &mut Game<T>,
    slot: &mut RecipientSlot<T>,
    amount: u64,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(game.validat_sender(&sender), EInvalidTransferTxSender);

    let payment: Balance<T> = game.split_balance(amount);
    slot.deposit(payment);
}

public fun handle_coin_bonus<T, K: key + store>(
    game: &mut Game<T>,
    bonus: Bonus<Coin<K>>,
    identifier: String,
    player_id: u64,
    player_addr: address,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(game.validat_sender(&sender), EInvalidBonusTxSender);
    assert!(game.has_bonus(&bonus.bonus_id()), EBonusNotFoundInGame);
    assert!(game.validate_player(player_id), EInvalidBonusReceiver);
    assert!(bonus.validate_identifer(identifier), EInvalidBonusIdentifier);

    let (bonus_uid, _amount, coin) = unpack_coin_bonus(bonus);
    transfer::public_transfer(coin, player_addr);
    object::delete(bonus_uid);
}

public fun handle_obj_bonus<T, K: key + store>(
    game: &mut Game<T>,
    bonus: Bonus<K>,
    identifier: String,
    player_id: u64,
    player_addr: address,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(game.validat_sender(&sender), EInvalidBonusTxSender);
    assert!(game.has_bonus(&bonus.bonus_id()), EBonusNotFoundInGame);
    assert!(game.validate_player(player_id), EInvalidBonusReceiver);
    assert!(bonus.validate_identifer(identifier), EInvalidBonusIdentifier);

    let (bonus_uid, _amount, obj) = unpack_obj_bonus(bonus);
    transfer::public_transfer(obj, player_addr);
    object::delete(bonus_uid);
}
