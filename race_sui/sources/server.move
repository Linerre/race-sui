module race_sui::server {
    use std::string::{Self, String};
    // use std::ascii::{Self, String as AsciiString};
    use sui::object::{Self, UID};
    use sui::table;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url::{Self, Url};
    use race_sui::game::{Self, ServerJoin, Game};

    struct Server has key {
        id: UID,
        owner: address,
        endpoint: Url,
    }
    // === Constants ===
    const MAX_SERVER_NUM: u64 = 10;
    const EServerNumberExceedsLimit: u64 = 4;
    const EDuplicateServerJoin: u64 = 5;

    // === Accessors ===
    public fun uid(self: &Server): &UID {
        &self.id
    }

    /// Create an on-chain server object, corresponding to register_server ix in race-solana
    public fun create(endpoint: String, ctx: &mut TxContext) {
        let owner: address = tx_context::sender(ctx);
        let server = Server {
            id: object::new(ctx),
            owner,
            endpoint: url::new_unsafe(string::to_ascii(endpoint)),
        };

        transfer::transfer(server, owner);
    }

    /// Server joins a game
    ///
    /// When a server joins an on-chain game, it can be either of the following cases:
    ///
    /// 1. It is the first to join and thus it becomes the transactor
    /// 2. It is the nth to join where n is in the range of [2,10] (inclusive)
    public fun serve(game: &mut Game, server: &Server, verify_key: String, ctx: &mut TxContext) {
        assert!(table::length(game::servers(game)) < MAX_SERVER_NUM, EServerNumberExceedsLimit);

        let server_addr = object::uid_to_address(&server.id);
        assert!(!table::contains(game::servers(game), server_addr), EDuplicateServerJoin);

        let new_access_version = game::access_version(game) + 1;
        game::server_join(game, server_addr, server.endpoint, new_access_version, verify_key);

    }

}
