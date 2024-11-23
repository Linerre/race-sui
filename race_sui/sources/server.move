module race_sui::server;

use std::string::{Self, String};

use sui::url::{Self, Url};
use sui::table::{Self, Table};

// === Struct ===
public struct ServerTable has key {
    id: UID,
    // map of wallet address to server address
    waddr_to_saddr: Table<address, ID>,
}

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

// === Module Initilizer ===

// === Entry function ===
/// Create an on-chain server object, like register_server ix in race-solana
public entry fun create(endpoint: String, ctx: &mut TxContext) {
    let owner: address = ctx.sender();
    let server = Server {
        id: object::new(ctx),
        owner,
        endpoint: url::new_unsafe(string::to_ascii(endpoint)),
    };

    transfer::transfer(server, owner);
}
