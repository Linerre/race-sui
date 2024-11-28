/// Player profile, the on-chain player account
#[allow(duplicate_alias)]
module race_sui::profile;

use std::string::{Self, String};
use race_sui::profile_table::{ProfileTable, add_profile, profile_exists};

const MAX_NICK_LEN: u64 = 33;

// === Errors ===
const EProfileOwnerMismatch: u64 = 421;
const EProfileAlreadyExists: u64 = 422;
const EProfileNickTooLong: u64 = 423;

// === Structs ===
public struct Profile has key, store {
    /// Profile unique ID
    id: UID,
    /// Owner wallet address
    owner: address,
    /// Player's on-chain nick name, up to 16 chars/bytes
    nick: String,
    /// Player's profile image
    pfp: Option<address>,
}

// === Entry functions ===
public entry fun create_profile(
    nick: String,
    pfp: Option<address>,
    profile_table: &mut ProfileTable,
    ctx: &mut TxContext
): address {
    let sender = ctx.sender();

    assert!(
        !profile_exists(profile_table, sender),
        EProfileAlreadyExists
    );

    assert!(
        string::length(&nick) > 0 && string::length(&nick) <= MAX_NICK_LEN,
        EProfileNickTooLong
    );

    // record the new profile in the map
    let profile = Profile { id: object::new(ctx), owner: sender, nick, pfp };
    add_profile(profile_table, sender, object::uid_to_inner(&profile.id));

    // copy newly created profile addr for return
    let profile_addr = object::uid_to_address(&profile.id);
    transfer::transfer(profile, ctx.sender());

    profile_addr
}

public entry fun update_profile(
    profile: &mut Profile,
    nick: String,
    pfp: Option<address>,
    ctx: &TxContext
) {
    assert!(ctx.sender() == profile.owner, EProfileOwnerMismatch);

    profile.nick = nick;

    if (option::is_some(&pfp)) {
        profile.pfp = pfp;
    };
}

// public fun get_profile(ptable: &ProfileTable, player: address): Profile {
//
// }

// === Public-view functions ===
public fun nick(self: &Profile): String {
    self.nick
}

public fun pfp(self: &Profile): Option<address> {
    self.pfp
}
// === Private Functions ===
