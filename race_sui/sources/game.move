module 0x0::game {
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url::{Self, Url};

    // ----------------------------------------
    // Children objects used in On-chain objects
    // ----------------------------------------
    struct PlayerJoin has key, store {
        id: UID,
        balance: u64,
        position: u64,
        access_version: u64,
        verify_key: String,
    }

    struct ServerJoin has key, store {
        id: UID,
        endpoint: Url,
        access_version: u64,
        verify_key: String,
    }

    // TODO: complete this struct
    struct Vote has store {
        voter: address,
        votee: address,
        // vote_type: VoteType
    }

    struct GameOwnerCap has key { id: UID }

    /// On-chain game account
    struct Game has key {
        id: UID,
        /// the contract version, used for upgrade
        version: String,
        /// game name displayed on chain
        title: String,
        /// addr to the game core logic program on Arweave
        bundle_addr: address,
        /// addr to the account that holds all players' deposits
        stake_account: address,
        /// mint id of the token used for the game
        token_mint: address,
        /// addr of the frist server joined the game,
        transactor_addr: Option<address>,
        /// a serial number, increased by 1 after each PlayerJoin or ServerJoin
        access_version: u64,
        /// a serial number, increased by 1 after each settlement
        settle_version: u64,
        /// game size
        max_players: u64,
        /// game players
        players: vector<PlayerJoin>,
        /// game servers (max: 10)
        servers: vector<ServerJoin>,

        // TODO: data_len and data

        /// game votes
        votes: vector<Vote>,
        /// the time when the game gets unlocked
        unlock_time: Option<u64>,
        /// entry type
        entry_type: EntryType,
        /// the recipient account
        recipient_addr: address,
        /// checkpoint data
        checkpoint: vector<u8>,
        /// the value of access version when checkpoint is set
        checkpoint_access_version: u64,
    }

    fun new(
        title: vector<u8>,
        bundle_addr: address,
        max_players: u64,
        ctx: &mut TxContext
    ): Game {
        Game {
            id: object::new(ctx),
            title: string::utf8(title),
            version: string::uft8(b"0.2.2"),
            bundle_addr,
            transactor_addr: option::none(),
            access_version: 0,
            settle_version: 0,
            max_players,
            players: vector::new(),
            servers: vector::new(),
            votes: vector::new(),
            unlock_time: option::none(),
            checkpoint: vector::new(),
            checkpoint_access_version: 0,
        }
    }

    public entry fun create(
        title: vector<u8>,
        bundle_addr: address,
        max_players: u64,
        ctx: &mut TxContext
    ) {
        let game = new(title, bundle_addr, max_players, ctx);
        transfer::transfer(game, tx_context::sender(ctx));
    }

    public entry fun close() {

    }

    public entry fun publish() {}

}
