module race_sui::settle;
use std::string::String;
use sui::balance::Balance;
use sui::coin::{Self, Coin};
use race_sui::game::{
    BalanceChange, EntryLock, Game, Prize, new_balance_change, unpack_bonus
};
use race_sui::recipient::{Recipient, RecipientSlot};

// === Errors ===
const ESettlePlayerNotFound: u64 = 450;
const ESettlePayMismatch: u64 = 451;
const EInvalidSettleTxSender: u64 = 453;
const EInvalidBonusReceiver: u64 = 457;
const EInvalidBonusIdentifier: u64 = 458;
const EInvalidSettleVersion: u64 = 459;
const EInvalidNextSettleVersion: u64 = 460;
const EInvalidSettleServer: u64 = 461;
const ESettlePreChecksNotPassed: u64 = 462;
const EInvalidGameStake: u64 = 463;

// === Structs ===
public enum PlayerStatus {
    Normal,
    Left,
    Dropout,
}

public struct Settle has copy, drop, store {
    // identical to access_version
    player_id: u64,
    amount: u64,
    change: Option<BalanceChange>,
    eject: bool
}

public struct Pay has copy, store {
    receiver: address,
    settle: Settle,
}

// Can only be made by `pre_settle_checks` function
public struct CheckPass has copy, drop {
    passed: bool
}

public fun create_settle(
    player_id: u64,
    amount: u64,
    change_type: u8,            // 0: None, 1: Add, 2: Sub
    change_amount: u64,         // 0 if there is no change
    eject: bool,
): Settle {
    let change: Option<BalanceChange> = if (change_amount == 0) {
        option::none()
    } else {
        option::some(new_balance_change(change_type, change_amount))
    };
    Settle { player_id, amount, change, eject }
}

public fun handle_settles<T>(
    game: &mut Game<T>,
    settles: vector<Settle>,
    pre_checks: CheckPass,
    ctx: &mut TxContext,
) {
    assert!(pre_checks.passed(), ESettlePreChecksNotPassed);
    let mut pays: vector<Pay> = vector::empty();
    let mut ejects: vector<u64> = vector::empty();
    let mut i = 0;
    let n = vector::length(&settles);
    let m = game.player_num() as u64;
    while (i < n) {
        let mut found =  false;
        let mut j = 0;
        let settle = vector::borrow(&settles, i);
        while (j < m) {
            if (game.validate_player_at_idx(j, settle.player_id)) {
                pays.push_back(
                    Pay {
                        receiver: game.player_addr(j),
                        settle: *settle // copy the settle
                    }
                );
                if (settle.eject) {
                    ejects.push_back(j); // record players to be removed
                };
                found = true;
                break
            };
            j = j + 1;
        };
        if (!found) abort ESettlePlayerNotFound;
        i = i + 1;
    };

    game.eject_players(ejects);
    let k = vector::length(&pays);
    assert!(n == k, ESettlePayMismatch);
    while (!pays.is_empty()) {
        let Pay { receiver, settle } = pays.pop_back();
        let Settle { player_id, amount, change, .. } = settle;
        // if any player balance change, update it
        if (change.is_some()) {
            let bchange: BalanceChange = change.destroy_some();
            game.change_player_balance(player_id, bchange);
        };
        // pay the settle player
        let pay_amount: Balance<T> = game.split_stake(amount);
        let paycoin: Coin<T> = coin::from_balance(pay_amount, ctx);
        transfer::public_transfer(paycoin, receiver);
    };
    vector::destroy_empty(pays);
}


public fun handle_transfer<T>(
    game: &mut Game<T>,
    slot: &mut RecipientSlot<T>,
    recipient: &mut Recipient,
    amount: u64,
    pre_checks: CheckPass,
) {
    assert!(pre_checks.passed(), ESettlePreChecksNotPassed);
    let payment: Balance<T> = game.split_stake(amount);
    slot.deposit(payment);
    // update (sync) the slot balance
    let slot_id = slot.slot_id();
    let slot_balance = slot.slot_balance();
    recipient.sync_slot_balance(slot_id, slot_balance);
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
    assert!(game.validate_player_id(player_id), EInvalidBonusReceiver);
    assert!(bonus.validate_identifer(identifier), EInvalidBonusIdentifier);

    let (bonus_uid, _amount, obj) = unpack_bonus(bonus);
    transfer::public_transfer<K>(obj, player_addr);
    object::delete(bonus_uid);
}

// This should be the first move call in the PTB for settlement. It returns a struct
// so that front end cannot simply pass a boolean value to bypass the prechecks.
// Sui Move runtime at the moment does not accept struct or enum being passed directly
// from front end and thus ensures that this function is mandatory in the settlment
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

// Finish the settle by housekeeping
public fun finish_settle<T>(
    game: &mut Game<T>,
    accept_deposits: vector<u64>,
    next_settle_version: u64,
    checkpoint_data: vector<u8>,     // serialized data of checkpointonchain
    mut entry_lock: Option<EntryLock>,
    pre_checks: CheckPass,
) {
    assert!(pre_checks.passed(), ESettlePreChecksNotPassed);
    game.update_deposits(accept_deposits);
    game.retain_pending_deposits();

    // game stake = sum(balance) + rejected deposits + pending deposits
    assert!(game.validate_stake(), EInvalidGameStake);
    // update player balances list
    game.update_player_balances();
    // update other info
    game.update_settle_version(next_settle_version);
    game.update_checkpoint_data(checkpoint_data);
    if (entry_lock.is_some()) {
        game.update_entry_lock(entry_lock.extract());
    };
}


fun passed(self: &CheckPass): bool {
    self.passed
}

// === For Test Only ===
#[test]
fun test_settle() {
    use race_sui::game::{make_fake_game, share_game};
    use race_sui::recipient::{make_fake_recipient, make_fake_slot, share_recipient, share_slot};
    let mut ctx = tx_context::dummy();
    let mut game = make_fake_game<0x2::sui::SUI>(&mut ctx);
    let mut rslot = make_fake_slot<0x2::sui::SUI>(&mut ctx);
    let slot = rslot.snapshot();
    let mut recipient = make_fake_recipient(slot, &mut ctx);
    let original_game_balance = 2_000_000_000;

    // game balance shoud be 2 SUI
    assert!(game.stake() == original_game_balance);

    // print recipient before settlement
    std::debug::print(&recipient);

    let pre_checks = pre_settle_checks(
        &game,
        @0x7a1f6dc139d351b41066ea726d9b53670b6d827a0745d504dc93e61a581f7192,
        1,
        4
    );
    let settles = vector[
        Settle {player_id: 3, amount: 1_067_000_000, eject: true, change: option::none()}
    ];

    // test settle
    handle_settles<0x2::sui::SUI>(&mut game, settles, pre_checks, &mut ctx);

    // test transfer
    handle_transfer<0x2::sui::SUI>(
        &mut game,
        &mut rslot,
        &mut recipient,
        3000000,
        pre_checks
    );

    // print recipient after settlement
    std::debug::print(&recipient);

    // game should have one player left
    assert!(game.player_num() == 1);

    // player should have been ejected
    assert!(!game.validate_player_id(3));

    // game balance should be deducet the given amount
    std::debug::print(&game.stake());
    let curr_game_balance = original_game_balance - 1_067_000_000 - 3000000;
    assert!(game.stake() == curr_game_balance);

    // slot balance should be synced
    assert!(recipient.recipient_slot_balance(0) == rslot.slot_balance());

    share_game(game);
    share_slot(rslot);
    share_recipient(recipient);
}
