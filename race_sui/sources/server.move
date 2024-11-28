module race_sui::server;

use std::string::{Self, String};
use sui::url::{Self, Url};
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
    endpoint: Url,
}

// === Entry function ===
/// Create an on-chain server object
public entry fun register_server(
    endpoint: String,
    server_table: &mut ServerTable,
    ctx: &mut TxContext
): address {
    let owner: address = ctx.sender();

    assert!(
        !owner_exists(server_table, owner),
        EOwnerAlreadyRegisteredServer
    );

    let server = Server {
        id: object::new(ctx),
        owner,
        endpoint: url::new_unsafe(string::to_ascii(endpoint)),
    };
    // record the owner-server relation in the table
    add_server(server_table, owner, object::uid_to_inner(&server.id));

    // copy newly created server addr for return
    let server_addr = object::uid_to_address(&server.id);
    transfer::transfer(server, owner);

    server_addr
}

// === Public-view functions ===
public fun addr(self: &Server): address {
    object::uid_to_address(&self.id)
}

public fun endpoint(self: &Server): Url {
    self.endpoint
}

public fun owner(self: &Server): address {
    self.owner
}
