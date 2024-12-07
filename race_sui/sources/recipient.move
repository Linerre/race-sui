/// A recipient is an on-chain object that acts like a treasury with slots
/// Each slot has an owner (wallet address) and a specific coin/nft as the
/// metric of the assets stored in it.  Only the owner can claim the assets
module race_sui::recipient;

use std::string::{Self, String};
use sui::bcs::{Self, BCS};
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};

// === Error codes ===
const EInvalidRecipientOwnerVariant: u64 = 440;
const EInvalidRecipientOwnerIdentifier: u64 = 441;
const EInvalidRecipienType: u64 = 442;
const ESlotOwnerIdentifierTooLong: u64 = 443;
const ESlotOwnerIdentifierEmtpy: u64 = 444;

// === Structs ===
/// For hot potato pattern, passed through each slot creation process
public struct RecipientBuilder {
    slot_ids: vector<ID>
}

public enum RecipientSlotType has copy, drop, store {
    Nft,
    Token,
}

public enum RecipientSlotOwner has copy, drop, store {
    /// string may be a game role
    Unassigned { identifier: String },
    /// address is the owner's account addr
    Assigned { addr: address }
}

public struct RecipientSlotShare has copy, drop, store {
    owner: RecipientSlotOwner,
    weights: u16,
    /// The total amount a recipient has claimed in the past
    claim_amount: u64,
}

public struct RecipientSlot<phantom T> has key, store {
    id: UID,
    /// recipient id, starting with 0, no dupliactes
    rid: u8,
    slot_type: RecipientSlotType,
    token_addr: address,
    shares: vector<RecipientSlotShare>,
    balance: Balance<T>,
}

/// An on-chain recipient object
public struct Recipient has key, store {
    id: UID,
    cap_addr: Option<address>,
    slot_ids: vector<ID>,
}

// ===  Public functions ===
public fun new_recipient_builder(): RecipientBuilder {
    RecipientBuilder { slot_ids: vector::empty<ID>() }
}

public fun create_recipient_slot<T>(
    rid: u8,
    token_addr: address,
    raw_slot_type: vector<u8>,
    raw_shares: vector<u8>,
    recipient_builder: RecipientBuilder,
    ctx: &mut TxContext
): RecipientBuilder {
    let mut slot_type_bcs = bcs::new(raw_slot_type);
    let mut shares_bcs = bcs::new(raw_shares);
    let slot_type = unpack_recipient_slot_type(&mut slot_type_bcs);
    let shares = unpack_slot_shares(&mut shares_bcs);

    let id = object::new(ctx);
    let slot_id = object::uid_to_inner(&id);
    let balance = balance::zero<T>();
    let slot = RecipientSlot {
        id,
        rid,
        slot_type,
        token_addr,
        shares,
        balance
    };

    // share the slot publicly
    transfer::share_object(slot);

    // reconstruct the builder and pass it on
    let RecipientBuilder { mut slot_ids } = recipient_builder;
    vector::push_back(&mut slot_ids, slot_id);
    RecipientBuilder { slot_ids }
}

public fun create_recipient(
    cap_addr: Option<address>,
    recipient_builder: RecipientBuilder,
    ctx: &mut TxContext,
) {
    // consume the hot potato
    let RecipientBuilder { slot_ids } = recipient_builder;

    let recipient = Recipient {
        id: object::new(ctx),
        cap_addr,
        slot_ids
    };

    transfer::share_object(recipient);
}

/// Allow anyone to deposit coins into the balance of a recipient slot
public entry fun deposit_to_slot<T>(
    slot: &mut RecipientSlot<T>,
    coin: Coin<T>
) {
    let coin_balance = coin::into_balance(coin);
    balance::join(&mut slot.balance, coin_balance);
}


/// Claim stake from one slot
public entry fun recipient_claim<T>(
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

fun unpack_recipient_slot_type(raw: &mut BCS): RecipientSlotType {
    match (raw.peel_vec_length()) {
        0 => RecipientSlotType::Nft,
        1 => RecipientSlotType::Token,
        _ => abort EInvalidRecipienType
    }
}

/// Deserialize to get a vector of RecipientSlotShare structs
fun unpack_slot_shares(raw: &mut BCS): vector<RecipientSlotShare> {
    let mut shares = vector::empty<RecipientSlotShare>();
    let shares_num: u64 = raw.peel_vec_length();
    let mut j = 1u64;

    while(j <= shares_num) {
        let owner = unpack_recipient_slot_owner(raw);
        let weights = raw.peel_u16();
        let claim_amount = raw.peel_u64();
        vector::push_back(
            &mut shares,
            RecipientSlotShare {
                owner,
                weights,
                claim_amount
            });

        // move to next slot share
        j = j + 1;
    };

    shares
}

fun unpack_recipient_slot_owner(raw: &mut BCS): RecipientSlotOwner {
    // variant index is ULEB128 32-bit unsiged integer per BCS spec:
    // https://github.com/diem/bcs?tab=readme-ov-file#externally-tagged-enumerations
    let variant_type = raw.peel_vec_length();
    match (variant_type) {
        0 => {
            let mut ret: Option<String> =
                string::try_utf8(raw.peel_vec_u8());
            if (ret.is_none()) abort EInvalidRecipientOwnerIdentifier;

            // check slot owner identifier string
            let identi = option::borrow(&ret);
            assert!(!string::is_empty(identi), ESlotOwnerIdentifierEmtpy);
            assert!(string::length(identi) <= 16, ESlotOwnerIdentifierTooLong);

            RecipientSlotOwner::Unassigned {
                identifier: ret.extract()
            }
        },
        1 => {
            RecipientSlotOwner::Assigned {
                addr: raw.peel_address()
            }
        },
        _ => abort EInvalidRecipientOwnerVariant
    }
}

// === Tests ===
#[test]
fun test_unpack_recipient_slot_type() {
    use std::bcs as stdbcs;
    // see https://docs.sui.io/guides/developer/dev-cheat-sheet#testing
    use sui::test_utils as tutils;

    let type1 = RecipientSlotType::Nft;
    let type2 = RecipientSlotType::Token;

    let bytes1 = stdbcs::to_bytes(&type1);
    let bytes2 = stdbcs::to_bytes(&type2);

    let mut raw1 = bcs::new(bytes1);
    let mut raw2 = bcs::new(bytes2);

    tutils::assert_eq(unpack_recipient_slot_type(&mut raw1), type1);
    tutils::assert_eq(unpack_recipient_slot_type(&mut raw2), type2);
}


#[test]
fun test_unpack_recipient_slot_owner() {
    use std::bcs as stdbcs;
    let addr1 = @0xCAFE;
    let addr2 = @0xFACE;

    let share1 = RecipientSlotOwner::Assigned { addr: addr1 };
    let share2 = RecipientSlotOwner::Unassigned {
            identifier: string::utf8(b"Race")
    };

    let bytes1 = stdbcs::to_bytes(&share1);
    let bytes2 = stdbcs::to_bytes(&share2);

    let mut raw1 = bcs::new(bytes1);
    let mut raw2 = bcs::new(bytes2);

    assert!(unpack_recipient_slot_owner(&mut raw1) == share1);
    assert!(unpack_recipient_slot_owner(&mut raw2) == share2);
}

#[test]
fun test_unpack_recipient_slot_share() {
    use std::bcs as stdbcs;
    use std::debug;

    let addr1 = @0xCAFE;
    let addr2 = @0xFACE;

    let shares = vector<RecipientSlotShare>[
        RecipientSlotShare {
            owner: RecipientSlotOwner::Assigned { addr: addr1 },
            weights: 20,
            claim_amount: 0
        },
        RecipientSlotShare {
            owner: RecipientSlotOwner::Assigned { addr: addr2 },
            weights: 30,
            claim_amount: 10
        },
        RecipientSlotShare {
            owner: RecipientSlotOwner::Unassigned {
                identifier: string::utf8(b"Race")
            },
            weights: 50,
            claim_amount: 60
        }
    ];

    debug::print(&shares);

    let bytes = stdbcs::to_bytes(&shares);
    let mut raw = bcs::new(bytes);

    assert!(unpack_slot_shares(&mut raw) == shares);
}
