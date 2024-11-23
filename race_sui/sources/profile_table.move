/// Player profile table is a single instance map of
/// player addr to their profile addr using Sui' OTW
module race_sui::profile_table;

use sui::package::{Self};
use sui::table::{Self, Table};

// === Structs ===
/// A one-time-use capability to allow only the package publisher
/// to init a profile table for once and transfer it to publisher
public struct ProfileTableCap has key {
    id: UID
}

/// A map that stores the mapping between players and their profiles
/// It is a singleton ensured by Sui's One-Time Witness pattern and
/// 1. one player can have only one profile
/// 2. only the publisher can delete this table
public struct ProfileTable has key {
    /// Table's on-chain id
    id: UID,
    /// publisher (owner) addr
    publisher: address,
    /// Table of player address to profile ID (converted from its UID)
    addr_to_pid: Table<address, ID>,
}

/// A one-time witness to generate and authenticate the publishership
/// only the publisher of this package can delete the profile table
public struct PROFILE_TABLE has drop {}

// === Module Initializer ===
fun init(otw: PROFILE_TABLE, ctx: &mut TxContext) {
    // create and send the Publisher object to the publisher
    package::claim_and_keep(otw, ctx);

    // create and send profile cap to the publisher
    let ptable_cap = ProfileTableCap { id: object::new(ctx) };
    transfer::transfer(ptable_cap, ctx.sender());

    // init profile table and share it publicly
    let ptable = ProfileTable {
        id: object::new(ctx),
        publisher: ctx.sender(),
        addr_to_pid: table::new<address, ID>(ctx)
    };

    transfer::share_object(ptable);
}


// === Methods for mutating and viewing profile table ===
public fun profile_exists(ptable: &ProfileTable, player: address): bool {
    table::contains(&ptable.addr_to_pid, player)
}

public fun profile_table_owner(ptable: &ProfileTable): address {
    ptable.publisher
}

// === Public pcckage functions ===
/// Add a newly created player file to the profile table
/// Should call this fn only within the package (i.e., by the other modules)
public(package) fun add_profile(
    ptable: &mut ProfileTable,
    player: address,
    pid: ID
) {
    table::add(
        &mut ptable.addr_to_pid, // table or map
        player,                  // player addr as key
        pid                      // player profile ID as value
    );
}
