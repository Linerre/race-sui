/// A recipient is an on-chain object that acts like a treasury with slots
/// Each slot has an owner (wallet address) and a specific coin/nft as the
/// metric of the assets stored in it.  Only the owner can claim the assets
#[allow(unused_use)]
module race_sui::recipient;

use std::string::{Self, String};
use sui::address;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;

// === Error codes ===
const EInvalidRecipientOwnerVariant: u64 = 440;
const EInvalidRecipienType: u64 = 442;
const ESlotOwnerIdentifierTooLong: u64 = 443;
const ESlotOwnerIdentifierEmtpy: u64 = 444;

// === Structs ===
public enum RecipientSlotType has copy, drop, store {
    Nft,
    Token,
}

public enum RecipientSlotOwner has copy, drop, store {
    // string represents a game role
    Unassigned { identifier: String },
    // address is the owner's addr
    Assigned { addr: address }
}

public struct RecipientSlotShare has copy, drop, store {
    owner: RecipientSlotOwner,
    weights: u16,
    // total amount a recipient has claimed in the past, initially 0
    claim_amount: u64,
}

/// One recipient slot which, once created, has a specific COIN associated
/// `token_addr` is the full path to this coin's struct, e.g., 0x02::sui::SUI
/// the slot id used in game, starting at 0 and no duplicates
public struct RecipientSlot<phantom T> has key, store {
    id: UID,
    slot_id: u8,
    slot_type: RecipientSlotType,
    token_addr: String,
    shares: vector<RecipientSlotShare>,
    balance: Balance<T>,
}

/// Like RecipientSlot but without T, and thus can be stored in the Recipient object
/// and makes it much easier for the front-end to query on chain Recipient
public struct Slot has store {
    id: ID,
    slot_id: u8,
    slot_type: RecipientSlotType,
    token_addr: String,
    shares: vector<RecipientSlotShare>,
    balance: u64
}

/// An on-chain recipient object. `slots` stores snapshots of each on-chain slots
public struct Recipient has key, store {
    id: UID,
    cap_addr: Option<address>,
    slots: vector<Slot>,
}

/// To record the slot ids during the recipient creation and gets
/// dropped once recipient is created -- hot potato pattern
public struct RecipientBuilder {
    slots: vector<Slot>
}

// ===  Public functions ===
public fun new_recipient_builder(): RecipientBuilder {
    RecipientBuilder { slots: vector::empty<Slot>() }
}

public fun create_slot_share(
    owner_type: u8,           // 0: unassigned, 1: assgined
    owner_info: String,       // identifier or address (without `0x` prefix)
    weights: u16,
): RecipientSlotShare {
    let owner = match (owner_type) {
        0 => {
            assert!(!string::is_empty(&owner_info), ESlotOwnerIdentifierEmtpy);
            assert!(string::length(&owner_info) <= 16, ESlotOwnerIdentifierTooLong);
            RecipientSlotOwner::Unassigned { identifier: owner_info }
        },
        1 => {
            let addr = address::from_ascii_bytes(string::as_bytes(&owner_info));
            RecipientSlotOwner::Assigned { addr }
        },
        _ => abort EInvalidRecipientOwnerVariant
    };

    RecipientSlotShare {
        owner,
        weights,
        claim_amount: 0
    }
}

public fun create_recipient_slot<T>(
    slot_id: u8,                    // slot id, in-game only
    token_addr: String,
    slot_type_info: u8,
    shares: vector<RecipientSlotShare>,
    recipient_builder: RecipientBuilder,
    ctx: &mut TxContext
): RecipientBuilder {

    let slot_type = create_slot_type(slot_type_info);

    let id = object::new(ctx);
    let balance = balance::zero<T>();
    let slot = RecipientSlot {
        id,
        slot_id,
        slot_type,
        token_addr,
        shares,
        balance
    };

    // store a snapshot of the slot object
    let RecipientBuilder { mut slots } = recipient_builder;
    vector::push_back(&mut slots, slot.snapshot());

    // share the slot publicly
    transfer::share_object(slot);

    // pass the builder on
    RecipientBuilder { slots }
}

public fun create_recipient(
    cap_addr: Option<address>,
    recipient_builder: RecipientBuilder,
    ctx: &mut TxContext,
) {
    // consume the hot potato
    let RecipientBuilder { slots } = recipient_builder;

    let recipient = Recipient {
        id: object::new(ctx),
        cap_addr,
        slots
    };

    transfer::share_object(recipient);
}

public(package) fun deposit<T>(self: &mut RecipientSlot<T>, amount: Balance<T>) {
    balance::join(&mut self.balance, amount);
}

public(package) fun slot_id<T>(self: &RecipientSlot<T>): ID {
    self.id.to_inner()
}

public(package) fun slot_balance<T>(self: &RecipientSlot<T>): u64 {
    self.balance.value()
}

public(package) fun recipient_slot_balance(self: &Recipient, index: u64): u64 {
    self.slots.borrow(index).balance
}

// When a recipient slot object gets some transfered balance, this value should
// be synced with the corresponding slots stored in recipient object
public(package) fun sync_slot_balance(
    self: &mut Recipient,
    slot_id: ID,
    new_balance: u64
) {
    let mut i = 0;
    let n = self.slots.length();
    while(i < n) {
        let curr = self.slots.borrow_mut(i);
        if (curr.id == slot_id) {
            curr.balance = new_balance;
            break
        };
        i = i + 1;
    };
}

/// Claim stake from one slot
public fun recipient_claim<T>(
    receiver: address,
    slot: &mut RecipientSlot<T>,
    ctx: &mut TxContext,
) {
    let share_num = vector::length(&slot.shares);
    let (total_weights,total_claimed) = calc_totals(&slot.shares, share_num);

    let mut i = 0;
    let mut claim = 0;
    while (i < share_num) {
        let share: &mut RecipientSlotShare =
            vector::borrow_mut(&mut slot.shares, i);
        match (&share.owner) {
            RecipientSlotOwner::Assigned { addr } if (addr == receiver) => {
                claim  = (total_claimed * (share.weights as u64) / (total_weights as u64)) - share.claim_amount;
                share.claim_amount = share.claim_amount + claim;
                break
            },
            _ => ()
        };
        i = i + 1;
    };

    if (claim > 0) {
        // split from balance and create a new coin for transfer
        let claim_balance = balance::split(&mut slot.balance, claim);
        let claim_coin = coin::from_balance(claim_balance, ctx);
        transfer::public_transfer(claim_coin, receiver);
    }
}

// === Private functions ===
fun create_slot_type(slot_type: u8): RecipientSlotType {
    match (slot_type) {
        0 => RecipientSlotType::Nft,
        1 => RecipientSlotType::Token,
        _ => abort EInvalidRecipienType
    }
}

fun calc_totals(
    shares: &vector<RecipientSlotShare>,
    share_num: u64
): (u16, u64) {
    let mut i = 0;
    let mut total_weights = 0;
    let mut total_claimed = 0;
    while (i < share_num) {
        let share: &RecipientSlotShare = vector::borrow(shares, i);
        total_weights = total_weights + share.weights;
        total_claimed = total_claimed + share.claim_amount;
        i = i + 1;
    };

    (total_weights, total_claimed)
}

// take the reference of a slot object and make a slot struct
public(package) fun snapshot<T>(self: &RecipientSlot<T>): Slot {
    Slot {
        id: self.id.uid_to_inner(),
        slot_id: self.slot_id,
        slot_type: self.slot_type,
        token_addr: self.token_addr,
        shares: self.shares,
        balance: self.balance.value()
    }
}

// === Test only ===
#[test_only]
public(package) fun make_fake_slot<T>(ctx: &mut TxContext): RecipientSlot<T> {
    RecipientSlot<T> {
        id: object::new(ctx),
        slot_id: 0,
        slot_type: RecipientSlotType::Token,
        token_addr: string::utf8(b"0x2::sui::SUI"),
        shares: vector[
            RecipientSlotShare {
                owner: RecipientSlotOwner::Assigned {
                    addr: @0x7a1f6dc139d351b41066ea726d9b53670b6d827a0745d504dc93e61a581f7192
                },
                weights: 100,
                claim_amount: 0
            }
        ],
        balance: balance::zero<T>()
    }
}

#[test_only]
public(package) fun make_fake_recipient(
    slot: Slot,
    ctx: &mut TxContext,
): Recipient {
    Recipient {
        id: object::new(ctx),
        cap_addr: option::none(),
        slots: vector[slot],
    }
}

#[test_only]
public(package) fun share_slot<T>(slot: RecipientSlot<T>) {
    transfer::share_object(slot);
}

#[test_only]
public(package) fun share_recipient(recipient: Recipient) {
    transfer::share_object(recipient);
}
