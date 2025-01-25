/// Player profile, the on-chain player account
#[allow(duplicate_alias)]
module race_sui::profile;

use std::string::{Self, String};
const MAX_NICK_LEN: u64 = 33;

// === Errors ===
const EProfileOwnerMismatch: u64 = 421;
const EProfileNickTooLong: u64 = 423;

// === Structs ===
public struct PlayerProfile has key, store {
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
#[allow(lint(self_transfer))]
public entry fun create_profile(
    nick: String,
    pfp: Option<address>,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();

    assert!(
        string::length(&nick) > 0 && string::length(&nick) <= MAX_NICK_LEN,
        EProfileNickTooLong
    );

    let profile = PlayerProfile { id: object::new(ctx), owner: sender, nick, pfp };
    transfer::transfer(profile, ctx.sender());
}

public entry fun update_profile(
    profile: &mut PlayerProfile,
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
public fun nick(self: &PlayerProfile): String {
    self.nick
}

public fun pfp(self: &PlayerProfile): Option<address> {
    self.pfp
}
// === Private Functions ===
