#[allow(duplicate_alias)]
module race_sui::server {
    use std::string::{Self, String};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url::{Self, Url};


    public struct Server has key {
        /// Server address
        id: UID,
        /// Server owner address
        owner: address,
        /// Server endpoint
        endpoint: Url,
    }

    // === Accessors ===
    public fun uid(self: &Server): &UID {
        &self.id
    }

    public fun endpoint(self: &Server): Url {
        self.endpoint
    }

    public fun owner(self: &Server): &address {
        &self.owner
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

}
