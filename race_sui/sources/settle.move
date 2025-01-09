#[allow(unused_use)]
module race_sui::settle;
use std::string::{Self, String};
use sui::address;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use std::debug;
use race_sui::game::{Bonus, EntryLock, Game, Prize, unpack_bonus};
use race_sui::recipient::{RecipientSlot};
use race_sui::server::Server;

// === Errors ===
const ESettlePlayerNotFound: u64 = 450;
const ESettleCoinMismatch: u64 = 451;
const EInvalidSettleTxSender: u64 = 453;
const EInvalidBonusReceiver: u64 = 457;
const EInvalidBonusIdentifier: u64 = 458;
const EInvalidSettleVersion: u64 = 459;
const EInvalidNextSettleVersion: u64 = 460;
const EInvalidSettleServer: u64 = 461;
const ESettlePreChecksNotPassed: u64 = 462;

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

public struct CheckPass has copy, drop {
    passed: bool
}

public fun create_settle(player_id: u64, amount: u64, eject: bool): Settle {
    Settle { player_id, amount, eject }
}

public fun handle_settles<T>(
    game: &mut Game<T>,
    settles: vector<Settle>,
    mut coins: vector<Coin<T>>,
    pre_checks: CheckPass,
    ctx: &mut TxContext,
) {
    assert!(pre_checks.passed(), ESettlePreChecksNotPassed);
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
        // FIXME: should not remove while looping through
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
    pre_checks: CheckPass,
) {
    assert!(pre_checks.passed(), ESettlePreChecksNotPassed);
    let payment: Balance<T> = game.split_balance(amount);
    slot.deposit(payment);
}

public fun handle_bonus<T, K: key + store>(
    game: &mut Game<T>,
    bonus: Prize<K>,
    identifier: String,
    player_id: u64,
    player_addr: address,
    pre_checks: CheckPass,
    _ctx: &mut TxContext,
) {
    assert!(pre_checks.passed(), ESettlePreChecksNotPassed);
    assert!(game.validate_player(player_id), EInvalidBonusReceiver);
    assert!(bonus.validate_identifer(identifier), EInvalidBonusIdentifier);

    let (bonus_uid, _amount, obj) = unpack_bonus(bonus);
    transfer::public_transfer<K>(obj, player_addr);
    object::delete(bonus_uid);
}

// This should be the first move call in the PTB for settlement. It returns a struct
// so that front end cannot simply pass a boolean value to bypass the prechecks.
// There is no other way to create the struct in order to makes this call mandatory.
public fun pre_settle_checks<T>(
    game: &Game<T>,
    server_owner: address,
    settle_version: u64,
    next_settle_version: u64,
): CheckPass {
    assert!(game.validate_sender(&server_owner), EInvalidSettleTxSender);
    assert!(game.validate_server(server_owner), EInvalidSettleServer);
    assert!(game.settle_version() == settle_version, EInvalidSettleVersion);
    assert!(game.settle_version() < next_settle_version, EInvalidNextSettleVersion);
    CheckPass {passed: true}
}

public fun finish_settle<T>(
    game: &mut Game<T>,
    accept_deposits: vector<u64>,
    next_settle_version: u64,
    new_checkpoint_data: vector<u8>,     // serialized data of checkpointonchain
    mut entry_lock: Option<EntryLock>,
    reset: bool,
    pre_checks: CheckPass,
) {
    assert!(pre_checks.passed(), ESettlePreChecksNotPassed);
    game.update_deposits(accept_deposits);
    game.retain_pending_deposits();
    game.update_settle_verson(next_settle_version);
    game.update_checkpoint_data(new_checkpoint_data);
    if (entry_lock.is_some()) {
        game.update_entry_lock(entry_lock.extract());
    };
    if (reset) {
        game.clear_players();
        game.clear_deposits();
    };
}


fun passed(self: &CheckPass): bool {
    self.passed
}
