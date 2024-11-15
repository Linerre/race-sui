/// Player profile, the on-chain player account
module race_sui::profile {
    use std::string::String;

    // === Constants ===
    const EProfileOwnerMismatch: u64 = 415;

    public struct Profile has key, store {
        id: UID,
        owner: address,
        nick: String,
        pfp: Option<address>,
    }

    public fun create(owner: address, nick: String, pfp:  Option<address>, ctx: &mut TxContext) {
        let profile = Profile { id: object::new(ctx), owner, nick, pfp };
        transfer::transfer(profile, tx_context::sender(ctx));
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

}
