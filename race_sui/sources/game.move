#[allow(duplicate_alias)]
module race_sui::game {
    use std::vector;
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use sui::bag::{Self, Bag};
    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url::Url;
    use race_sui::server::{Self, Server};


    // === Constants ===
    const MAX_SERVER_NUM: u64 = 10;
    const EServerNumberExceedsLimit: u64 = 405;
    const EDuplicateServerJoin: u64 = 406;
    const EGameHasLeftPlayers: u64 = 408;
    const EGameOwnerMismatch: u64 = 409;
    const EPositionAlreadyTaken: u64 = 410;
    const EInvalidDeposit: u64 = 411;
    const EInvalidPosition: u64 = 412;
    const EDuplicatePlayerJoin: u64 = 413;
    const EGameIsFull: u64 = 414;

    // === Structs ===
    public struct PlayerJoin has drop, store {
        addr: address,
        position: u64,
        access_version: u64,
        verify_key: String,
    }

    public struct ServerJoin has drop, store {
        addr: address,
        endpoint: Url,
        access_version: u64,
        verify_key: String,
    }

    public struct Vote has drop, store {
        voter: address,
        votee: address,
        vote_type: u8,
    }

    // EntryType (replace with `enum` once sui Move supports it)
    // 0
    public struct Cash has drop, store{
        min_deposit: u64,
        max_deposit: u64,
    }

    // 1
    public struct Ticket has drop, store {
        slot_id: u64,
        amount: u64,
    }

    // 2
    public struct Gating has drop, store {
        collection: String,
    }

    /// On-chain game account
    public struct Game has key {
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
        players: vector<PlayerJoin>,
        /// game servers (max: 10)
        servers: vector<ServerJoin>,
        // TODO: data_len and data, use sui::bcs
        /// game votes
        votes: vector<Vote>,
        /// the time when the game gets unlocked
        unlock_time: Option<u64>,
        /// entry type: 0: Cash, 1: Ticket, 2: Gating
        entry_type: Bag,
        /// the recipient account
        recipient_addr: address,
        /// checkpoint data
        checkpoint: vector<u8>,
        /// the value of access version when checkpoint is set
        checkpoint_access_version: u64,
    }

    public struct GameMinted has copy, drop {
        game_id: ID,
        minted_by: address,
    }

    // === Accessors ===
    public fun player_num(self: &Game): u64 {
        vector::length(&self.players)
    }

    public fun max_players(self: &Game): u64 {
        self.max_players
    }

    public fun players(self: &Game): &vector<PlayerJoin> {
        &self.players
    }

    public fun players_mut(self: &mut Game): &mut vector<PlayerJoin> {
        &mut self.players
    }

    public fun servers(self: &Game): &vector<ServerJoin> {
        &self.servers
    }

    public fun servers_mut(self: &mut Game): &mut vector<ServerJoin> {
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
        min_deposit: u64,
        max_deposit: u64,
        ctx: &mut TxContext
    ) {
        let game = new(
            title,
            bundle_addr,
            owner,
            recipient_addr,
            max_players,
            min_deposit,
            max_deposit, ctx
        );

        transfer::transfer(game, tx_context::sender(ctx));
    }

    public fun close(game: Game, ctx: &mut TxContext) {
        assert!(&tx_context::sender(ctx) == &game.owner, EGameOwnerMismatch);
        assert!(vector::is_empty(&game.players), EGameHasLeftPlayers);

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
            players: _,
            servers: _,
            votes: _,
            unlock_time: _,
            mut entry_type,
            recipient_addr: _,
            checkpoint: _,
            checkpoint_access_version: _,
        } = game;

        let cash: Cash = bag::remove(&mut entry_type, 0);
        _ = cash;
        bag::destroy_empty(entry_type);
        object::delete(id);
    }

    // TODO: Only allow game owner to mint the game?
    /// Publish (mint) the game as NFT
    public fun publish(game_addr: address, ctx: &mut TxContext) {
        let game_id = object::id_from_address(game_addr);

        event::emit(GameMinted {
            game_id,
            minted_by: tx_context::sender(ctx),
        });
    }

    /// Server joins a game
    ///
    /// When a server joins an on-chain game, it can be either of the following cases:
    ///
    /// 1. It is the first (indexed as 0) joined and thus it becomes the transactor
    /// 2. It is the nth joined where n is in the range of [1,10] (inclusive)
    public fun serve(game: &mut Game, server: &Server, verify_key: String, _ctx: &mut TxContext) {
        let server_num = vector::length(&game.servers);
        assert!(server_num < MAX_SERVER_NUM, EServerNumberExceedsLimit);

        let server_addr = object::uid_to_address(server::uid(server));
        let mut i = 0;
        while (i < server_num) {
            let curr_server: &ServerJoin = vector::borrow(&game.servers, i);
            if (&curr_server.addr == server::owner(server)) abort EDuplicateServerJoin;
            i = i + 1;
        };

        let access_version = game.access_version + 1;

        vector::push_back(
            &mut game.servers,
            ServerJoin {
                addr: server_addr,
                endpoint: server::endpoint(server),
                access_version,
                verify_key,
            }
        );

    }

    /// Player joins a game
    public fun join(
        game: &mut Game,
        player_addr: address,
        position: u64,
        _balance: u64,
        amount: u64,
        verify_key: String
    ) {
        let player_num = player_num(game);
        let max_players = max_players(game);

        assert!(player_num < max_players, EGameIsFull);
        assert!(position < max_players, EInvalidPosition);

        let mut i = 0;
        // position passed may have been taken and we need to check availability
        let mut pos_taken = vector::empty<u64>();
        while (i < player_num) {
            let curr_player: &PlayerJoin = vector::borrow(&game.players, i);
            if (&curr_player.addr == &player_addr) {
                abort EDuplicatePlayerJoin
            };
            vector::push_back(&mut pos_taken, i);
            i = i + 1;

        };

        let mut all_pos_taken = false;
        let mut avail_pos = position;
        if (vector::contains(&pos_taken, &position)) {
            let mut j = 0;
            while (j < max_players) {
                if (!vector::contains(&pos_taken, &j)) {
                    avail_pos = j;
                    break
                };
                j = j + 1;
            };
            all_pos_taken = true;
        };

        if (all_pos_taken) abort EInvalidPosition;

        let access_version = game.access_version + 1;
        let player_join =  PlayerJoin {
            addr: player_addr,
            position: avail_pos,
            access_version,
            verify_key,
        };

        if (bag::contains(&game.entry_type, 0)) {
            // Check player's deposit
            let cash_type: &Cash = bag::borrow(&game.entry_type, 0);
            if (amount < cash_type.min_deposit || amount > cash_type.max_deposit) {
                abort EInvalidDeposit
            }
        };
        // TODO: add branches for other entry types

        // TODO: transfer player's deposit to the game object
        vector::push_back(&mut game.players, player_join);

    }

    // === Private functions ===
    fun new(
        title: String,
        bundle_addr: address,
        owner: address,
        recipient_addr: address,
        max_players: u64,
        min_deposit: u64,
        max_deposit: u64,
        ctx: &mut TxContext
    ): Game {
        let mut entry_type = bag::new(ctx);
        bag::add(&mut entry_type, 0, Cash { min_deposit, max_deposit });

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
            players: vector::empty<PlayerJoin>(),
            servers: vector::empty<ServerJoin>(),
            votes: vector::empty<Vote>(),
            unlock_time: option::none(),
            entry_type,
            recipient_addr,
            checkpoint: vector::empty<u8>(),
            checkpoint_access_version: 0,
        }
    }
}
