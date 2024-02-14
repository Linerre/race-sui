module 0x0::game {
    use std::vector;
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url::{Self, Url};

    // ----------------------------------------
    // Children objects used in On-chain objects
    // ----------------------------------------

    struct PlayerJoin has drop, store {
        addr: address,
        balance: u64,
        position: u64,
        access_version: u64,
        verify_key: String,
    }

    struct ServerJoin has drop, store {
        addr: address,
        endpoint: Url,
        access_version: u64,
        verify_key: String,
    }

    struct Vote has drop, store {
        voter: address,
        votee: address,
        vote_type: u8,
    }

    // EntryType (replace with `enum` once sui Move supports it)
    struct Cash {
        typeid: u8,
        min_deposit: u64,
        max_deposit: u64,
    }

    struct Ticket {
        typeid: u8,
        slot_id: u64,
        amount: u64,
    }

    struct Gating {
        collection: String,
    }

    /// On-chain game account
    struct Game has key {
        id: UID,
        /// the contract version, used for upgrade
        version: String,
        /// game name displayed on chain
        title: String,
        /// addr to the game core logic program on Arweave
        bundle_addr: address,
        /// game owner creates this game object
        owner: address,
        /// addr to the account that holds all players' deposits
        // stake_account: address,
        /// mint id of the token used for the game
        // token_mint: address,
        /// addr of the frist server joined the game,
        transactor_addr: Option<address>,
        /// a serial number, increased by 1 after each PlayerJoin or ServerJoin
        access_version: u64,
        /// a serial number, increased by 1 after each settlement
        settle_version: u64,
        /// game size
        max_players: u64,
        /// game players
        players: Table<address, PlayerJoin>,
        // players: PlayerTable,
        /// game servers (max: 10)
        servers: Table<address, ServerJoin>,
        // servers: ServerTable,
        // TODO: data_len and data, use sui::bcs

        /// game votes
        votes: vector<Vote>,
        /// the time when the game gets unlocked
        unlock_time: Option<u64>,
        /// entry type: 0: Cash, 1: Ticket, 2: Gating
        entry_type: u8,
        /// the recipient account
        recipient_addr: address,
        /// checkpoint data
        checkpoint: vector<u8>,
        /// the value of access version when checkpoint is set
        checkpoint_access_version: u64,
    }

    // === Constants ===
    const ServerVoteTransactorDropoff: u8 = 0;
    const ClientVoteTransactorDropoff: u8 = 1;
    const EGameHasLeftPlayers: u64 = 2;
    const EGameOwnerMismatch: u64 = 3;

    // === Accessors ===
    public fun player_num(self: &Game): u64 {
        table::length(&self.players)
    }

    public fun servers(self: &Game): &Table<address, ServerJoin> {
        &self.servers
    }

    public fun servers_mut(self: &mut Game): &mut Table<address, ServerJoin> {
        &mut self.servers
    }

    public fun access_version(self: &Game): u64 {
        self.access_version
    }

    public fun settle_version(self: &Game): u64 {
        self.settle_version
    }

    // === Public ABIs ===
    public fun create(
        title: String,
        bundle_addr: address,
        owner: address,
        recipient_addr: address,
        max_players: u64,
        ctx: &mut TxContext
    ) {
        let game = new(title, bundle_addr, owner, recipient_addr, max_players, ctx);
        transfer::transfer(game, tx_context::sender(ctx));
    }

    public fun close(game: Game, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == game.owner, EGameOwnerMismatch);
        assert!(table::is_empty(&game.players), EGameHasLeftPlayers);

        let Game {
            id,
            title: _,
            version: _,
            bundle_addr: _,
            owner: _,
            transactor_addr: _,
            access_version: _,
            settle_version: _,
            max_players: _,
            players: players,
            servers: servers,
            votes: _,
            unlock_time: _,
            entry_type: _,
            recipient_addr: _,
            checkpoint: _,
            checkpoint_access_version: _,
        } = game;

        table::drop(players);
        table::drop(servers);
        object::delete(id);
    }

    /// Add a new server to game's servers
    public fun server_join(
        game: &mut Game,
        addr: address,
        endpoint: Url,
        access_version: u64,
        verify_key: String
    ) {
        let server_join = ServerJoin {addr, endpoint, access_version, verify_key};
        table::add(&mut game.servers, addr, server_join);
    }

    public fun publish() {

    }

    // === Private functions ===
    fun new(
        title: String,
        bundle_addr: address,
        owner: address,
        recipient_addr: address,
        max_players: u64,
        ctx: &mut TxContext
    ): Game {
        Game {
            id: object::new(ctx),
            title,
            version: string::utf8(b"0.2.2"),
            bundle_addr,
            owner,
            transactor_addr: option::none(),
            access_version: 0,
            settle_version: 0,
            max_players,
            players: table::new(ctx),
            servers: table::new(ctx),
            votes: vector::empty<Vote>(),
            unlock_time: option::none(),
            entry_type: 0,
            recipient_addr,
            checkpoint: vector::empty<u8>(),
            checkpoint_access_version: 0,
        }
    }
}
