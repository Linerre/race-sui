/// Player profile, the on-chain player account
#[allow(duplicate_alias)]
module race_sui::profile;

use std::string::String;
use race_sui::profile_table::{ProfileTable, add_profile, profile_exists};

// === Errors ===
const EProfileOwnerMismatch: u64 = 415;
const EProfileAlreadyExists: u64 = 416;

// === Structs ===
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

// === Public-view functions ===
public fun nick(self: &Profile): String {
    self.nick
}

public fun pfp(self: &Profile): Option<address> {
    self.pfp
}
// === Private Functions ===
