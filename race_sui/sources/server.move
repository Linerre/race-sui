module race_sui::server;

use std::string::String;
use race_sui::server_table::{ServerTable, add_server, owner_exists};


// === Error codes ===
const EOwnerAlreadyRegisteredServer: u64 = 430;

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
public fun register_server(
    endpoint: String,
    server_table: &mut ServerTable,
    ctx: &mut TxContext
) {
    let owner: address = ctx.sender();

    if (owner_exists(server_table, owner))
    abort EOwnerAlreadyRegisteredServer;

    let server = Server {
        id: object::new(ctx),
        owner,
        endpoint,
    };
    // record the owner-server relation in the table
    add_server(server_table, owner, object::uid_to_inner(&server.id));

    // copy newly created server addr for return
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
