/// Player profile, the on-chain player account
#[allow(duplicate_alias)]
module race_sui::profile;

use sui::table::{Self, Table};
use std::string::String;

// === Errors ===
const EProfileOwnerMismatch: u64 = 415;
const EProfileAlreadyExists: u64 = 416;

// === Structs ===
public struct ProfileTable has key {
    /// Table's on-chain id
    id: UID,
    /// Table of player address to profile ID (converted from its UID)
    addr_to_pid: Table<address, ID>,
}

public struct Profile has key, store {
    /// Profile unique ID
    id: UID,
    /// Owner wallet address
    owner: address,
    /// Player's on-chain nick name
    nick: String,
    /// Player's profile image
    pfp: Option<address>,
}

// === Module Initializer ===
/// Called only once on module publish to create a shared table which
/// stores the mapping from user addr to their on-chain profile
fun init(ctx: &mut TxContext) {
    transfer::share_object(ProfileTable {
        id: object::new(ctx),
        addr_to_pid: table::new(ctx),
    });
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
        !table::contains(&profile_table.addr_to_pid, sender),
        EProfileAlreadyExists
    );

    // record the new profile in the map and copy the profile address
    let profile = Profile { id: object::new(ctx), owner: sender, nick, pfp };
    table::add(
        &mut profile_table.addr_to_pid,
        sender, object::uid_to_inner(&profile.id)
    );
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


// === Private Functions ===
