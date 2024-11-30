#[allow(unused_use)]
module race_sui::recipient;

use std::string::{Self, String};
use sui::bcs::{Self, BCS};

// === Error codes ===
const EInvalidRecipientOwnerVariant: u64 = 440;
const EInvalidRecipientOwnerIdentifier: u64 = 440;

// === Structs ===
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

public struct RecipientSlot has copy, drop, store {
    /// recipient id
    rid: u8,
    slot_type: RecipientSlotType,
    token_addr: address,
    shares: vector<RecipientSlotShare>,
    balance: u64,
}

/// An on-chain recipient object
public struct Recipient has key, store {
    id: UID,
    cap_addr: Option<address>,
    slots: vector<RecipientSlot>,
}

// === Entry functions ===
public entry fun create_recipient(
    cap_addr: Option<address>,
    bytes: vector<u8>,
    ctx: &mut TxContext,
) {
    let mut raw: BCS = bcs::new(bytes);

    let mut slots = vector::empty<RecipientSlot>();
    let slot_num = raw.peel_vec_length();

    // loop to deserialize and construct each RecipientSlot
    let mut i = 1;
    while (i <= slot_num) {
        let rid = raw.peel_u8();
        let slot_type = if (raw.peel_u8() == 0) {
            RecipientSlotType::Nft
        } else {
            RecipientSlotType::Token
        };
        let token_addr = raw.peel_address();

        let shares = unpack_slot_shares(&mut raw);
        let balance = raw.peel_u64();

        vector::push_back(&mut slots, RecipientSlot {
            rid, slot_type, token_addr, shares, balance
        });

        // move to next slot
        i = i + 1;
    };

    let recipient = Recipient {
        id: object::new(ctx),
        cap_addr,
        slots
    };

    transfer::share_object(recipient);
}

// public entry fun get_recipient() {}

// public entry fun recipient_claim() {}

// === Private functions ===
/// Deserialize from raw bytes a vector of RecipientSlotShare structs
fun unpack_slot_shares(raw: &mut BCS): vector<RecipientSlotShare> {
    use std::debug;
    let mut shares = vector::empty<RecipientSlotShare>();
    let shares_num: u64 = raw.peel_vec_length();
    debug::print(&shares_num);
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
        debug::print(&shares);
        debug::print(&j);
        j = j + 1;
        debug::print(&j);
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
fun test_unpack_recipient_slot() {
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
