#[allow(unused_use)]
module race_sui::recipient;

use std::string::{Self, String};
use sui::bcs::{Self, BCS};

// === Error codes ===
const EInvalidRecipientOwnerVariant: u64 = 440;
const EInvalidRecipientOwnerIdentifier: u64 = 440;

// === Structs ===
public enum RecipientSlotType has copy, store {
    Nft,
    Token,
}

public enum RecipientSlotOwner has copy, store {
    /// string may be a game role
    Unassigned { identifier: String },
    /// address is the owner's account addr
    Assigned { addr: address }
}

public struct RecipientSlotShare has copy, store {
    owner: RecipientSlotOwner,
    weights: u16,
    /// The total amount a recipient has claimed in the past
    claim_amount: u64,
}

public struct RecipientSlot has copy, store {
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

    let slot_num = raw.peel_u32();
    let mut slots = vector::empty<RecipientSlot>();

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
        let mut shares = vector::empty<RecipientSlotShare>();
        let shares_num = raw.peel_u32();
        let mut j = 1;
        while(j <= shares_num) {
            // get a temp bytes array to extract variant type
            let tmp_bytes = raw.into_remainder_bytes();
            let variant_type = *vector::borrow(&tmp_bytes, 0);
            // restore raw byte array;
            raw = bcs::new(tmp_bytes);

            let owner = match (variant_type) {
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
            };
            let weights = raw.peel_u16();
            let claim_amount = raw.peel_u64();
            vector::push_back(
                &mut shares,
                RecipientSlotShare {
                    owner,
                    weights,
                    claim_amount
                });
            j = j + 1;
        };
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

// public entry fun get_recipient() {};

// public entry fun recipient_claim() {};

// === Private functions ===
