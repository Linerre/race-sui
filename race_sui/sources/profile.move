/// Player profile, the on-chain player account
module 0x0::profile {
    use std::string::String;
    use std::option::{Self, Option};

    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};


    struct Profile has key {
        id: UID,
        owner: address,
        nick: String,
        pfp: Option<address>,
    }

    // === Constants ===
    const EProfileOwnerMismatch: u64 = 3;


    public fun create(owner: address, nick: String, pfp: Option<address>, ctx: &mut TxContext) {
        let profile = Profile { id: object::new(ctx), owner, nick, pfp };
        transfer::transfer(profile, tx_context::sender(ctx));
    }

    public fun update(
        profile: &mut Profile,
        owner: address,
        nick: String,
        pfp: Option<address>,
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
}
