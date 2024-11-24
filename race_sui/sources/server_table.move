/// A single instance map of player addr to their own server
module race_sui::server_table;

use sui::package::{Self};
use sui::table::{Self, Table};

// === Structs ===
/// A admin capability to allow only the package publisher
/// to init a profile table for once and transfer it to publisher
public struct ServerTableCap has key {
    id: UID
}

/// A map that stores the mapping between owners and their profiles
/// It is a singleton ensured by Sui's One-Time Witness pattern and
/// 1. one owner can have only one on-chain server
/// 2. only the package publisher can delete this table
public struct ServerTable has key {
    /// Table's on-chain id
    id: UID,
    /// publisher (owner) addr
    publisher: address,
    /// Table of onwer address to server ID (converted from its UID)
    addr_to_sid: Table<address, ID>,
}

/// A one-time witness to generate and authenticate the publishership
/// only the publisher of this package can delete the server table
public struct SERVER_TABLE has drop {}


// === Module Initializer ===
fun init(otw: SERVER_TABLE, ctx: &mut TxContext) {
    // create and send the Publisher object to the publisher
    package::claim_and_keep(otw, ctx);

    // create and send server cap to the publisher
    let stable_cap = ServerTableCap { id: object::new(ctx) };
    transfer::transfer(stable_cap, ctx.sender());

    // init server table and share it publicly
    let stable = ServerTable {
        id: object::new(ctx),
        publisher: ctx.sender(),
        addr_to_sid: table::new<address, ID>(ctx)
    };

    transfer::share_object(stable);
}

// === Public-view functions ===
/// Check if an addr (owner) has already existed in the server table
public fun owner_exists(stable: &ServerTable, owner: address): bool {
    table::contains(&stable.addr_to_sid, owner)
}

/// Get the server table owner, that is, the package publisher's address
public fun server_table_owner(stable: &ServerTable): address {
    stable.publisher
}

// === Public package functions ===
/// Register a newly created server in the server table
public(package) fun add_server(
    stable: &mut ServerTable,
    owner: address,             // server owner
    sid: ID
) {
    table::add(
        &mut stable.addr_to_sid,
        owner,
        sid
    );
}
