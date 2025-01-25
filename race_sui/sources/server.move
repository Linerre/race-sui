module race_sui::server;

use std::string::String;

// === Error codes ===

// === Struct ===
public struct Server has key {
    /// Server address
    id: UID,
    /// Server owner address
    owner: address,
    /// Server endpoint
    endpoint: String,
}

// === Entry function ===
/// Create an on-chain server object whose ID will be stored in the
/// global ServerTable. Each user address can own one server only
#[allow(lint(self_transfer))]
public fun register_server(
    endpoint: String,
    ctx: &mut TxContext
) {
    let owner: address = ctx.sender();

    let server = Server {
        id: object::new(ctx),
        owner,
        endpoint,
    };

    transfer::transfer(server, owner);
}

// === Public-view functions ===
public fun addr(self: &Server): address {
    object::uid_to_address(&self.id)
}

public fun endpoint(self: &Server): String {
    self.endpoint
}

public fun owner(self: &Server): address {
    self.owner
}
