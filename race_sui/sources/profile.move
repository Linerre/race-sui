/// Player profile, the on-chain player account
#[allow(duplicate_alias)]
module race_sui::profile;

use sui::object::{Self, UID};
use sui::transfer;
use sui::tx_context::{Self, TxContext};
use std::string::String;
use std::option::{Self, Option};

// === Constants ===
const EProfileOwnerMismatch: u64 = 415;

public struct Profile has key, store {
    /// Profile ID (address)
    id: UID,
    /// Owner wallet address
    owner: address,
    /// Player's on-chain nick name
    nick: String,
    /// Player's profile image
    pfp: Option<address>,
}

// === Entry functions ===
public entry fun create_profile(
    nick: String,
    pfp: Option<address>,
    ctx: &mut TxContext
) {
    let profile = create(tx_context::sender(ctx), nick, pfp, ctx);
    transfer::transfer(profile, tx_context::sender(ctx));
}

public entry fun update_profile(
    profile: &mut Profile,
    nick: String,
    pfp: Option<address>,
    ctx: &mut TxContext
) {
    update(profile, tx_context::sender(ctx), nick, pfp, ctx);
}

public fun create(owner: address, nick: String, pfp:  Option<address>, ctx: &mut TxContext): Profile {
    Profile { id: object::new(ctx), owner, nick, pfp }
}

public fun update(
    profile: &mut Profile,
    owner: address,
    nick: String,
    mut pfp: Option<address>,
    ctx: &mut TxContext
) {
    assert!(tx_context::sender(ctx) == owner, EProfileOwnerMismatch);
    profile.nick = nick;
    if (option::is_some(&pfp)) {
        let new_pfp = option::extract(&mut pfp);
        let old_pfp = option::swap_or_fill(&mut profile.pfp, new_pfp);
        _ = old_pfp;
    }
}
