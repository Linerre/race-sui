#[allow(unused_function)]
module race_sui::game;
use std::string::{Self, String};
use sui::event;
use race_sui::server::Server;

// === Constants ===
const MAX_SERVER_NUM: u64 = 10;
const EServerNumberExceedsLimit: u64 = 410;
const EDuplicateServerJoin: u64 = 411;
const EGameIsNotEmpty: u64 = 412;
const EGameOwnerMismatch: u64 = 413;
const EInvalidCashDeposit: u64 = 414;
const EInvalidTicketAmount: u64 = 415;
const EPositionOutOfRange: u64 = 416;
const EDuplicatePlayerJoin: u64 = 417;
const EGameIsFull: u64 = 418;
const EInvalideVoteType: u64 = 419;

// === Structs ===
/// Only game owner can delete a game
public struct GameAdminCap has key {
    id: UID,
}

public enum EntryLock has drop, store {
    /// default
    Open,
    JoinOnly,
    DepositOnly,
    Closed,
}

public enum VoteType has drop, store {
    ServerVoteTransactorDropOff,
    ClientVoteTransactorDropOff
}

/// Game' 3 EntryTypes
public enum EntryType has copy, drop, store {
    /// A player can join the game by sending assets to game account directly
    Cash { min_deposit: u64, max_deposit: u64 },
    /// A player can join the game by pay a ticket
    Ticket { amount: u64 },
    /// A player can join the game by showing a gate NFT
    Gating { collection: String },
    Disabled,
}


public enum DepositStatus has drop, store {
    /// Default
    Pending,
    Rejected,
    Refunded,
    Accepted,
}

public struct PlayerJoin has drop, store {
    addr: address,
    position: u16,
    access_version: u64,
    verify_key: String,
}

public struct ServerJoin has drop, store {
    addr: address,
    endpoint: String,
    access_version: u64,
    verify_key: String,
}

public struct PlayerDeposit has drop, store {
    addr: address,
    amount: u64,
    access_version: u64,
    settle_version: u64,
    status: DepositStatus
}

#[allow(unused_field)]
public struct Vote has drop, store {
    voter: address,
    votee: address,
    vote_type: VoteType,
}

/// On-chain game account
public struct Game has key {
    id: UID,
    /// the contract version, used for upgrade
    version: String,
    /// game name displayed on chain
    title: String,
    // TODO: may simplify this to a string arweave tx id
    /// AccountAddress to the game (WASM) as an NFT
    bundle_addr: address,
    /// token type used in this game, e.g. "0x02::sui::SUI"
    coin_type: String,
    /// SuiAddress to the game owner that creates this game object
    owner: address,
    /// the recipient account address (AccountAddress in SDK)
    recipient_addr: address,
    /// AccountAddress of the frist server joined the game,
    transactor_addr: Option<address>,
    /// a serial number, increased by 1 after each PlayerJoin or ServerJoin
    access_version: u64,
    /// a serial number, increased by 1 after each settlement
    settle_version: u64,
    /// game size
    max_players: u16,
    /// game players
    players: vector<PlayerJoin>,
    /// players' deposits
    deposits: vector<PlayerDeposit>,
    /// game servers (max: 10)
    servers: vector<ServerJoin>,
    /// data length
    data_len: u32,
    /// serialized game-specific data such as sb/bb
    data: vector<u8>,
    /// game votes
    votes: vector<Vote>,
    /// the time when the game gets unlocked
    unlock_time: Option<u64>,
    /// entry type: Cash, Ticket, Gating
    entry_type: EntryType,
    /// checkpoint data
    checkpoint: vector<u8>,
    /// lock types for entry
    entry_lock: EntryLock,
}

public struct GameNFT has key, store {
    id: UID,
    /// name for the game NFT
    name: String,
    bundle_url: String,         // arweave url to the game WASM
    cover_url: String           // arweave url to the cover image
}

public struct GameMinted has copy, drop {
    game_id: ID,
    creator: address,
    name: String,
}

// === Private-mutative functions ===
public fun create_cash_entry(min_deposit: u64, max_deposit: u64): EntryType {
    EntryType::Cash { min_deposit, max_deposit }
}

public fun create_ticket_entry(amount: u64): EntryType {
    EntryType::Ticket { amount }
}

public fun create_gating_entry(collection: String): EntryType {
    EntryType::Gating { collection }
}

public fun create_disabled_entry(): EntryType {
    EntryType::Disabled
}

public fun create_vote_type(variant: u8): VoteType {
    match (variant) {
        0 => VoteType::ServerVoteTransactorDropOff,
        1 => VoteType::ClientVoteTransactorDropOff,
        _ => abort EInvalideVoteType
    }
}

public fun create_game(
    title: String,
    bundle_addr: address,
    owner: address,
    recipient_addr: address,
    coin_type: String,
    max_players: u16,
    data_len: u32,
    data: vector<u8>,
    entry_type: EntryType,
    ctx: &mut TxContext
): ID {
    let game = Game {
        id: object::new(ctx),
        title,
        version: string::utf8(b"0.1.0"),
        bundle_addr,
        owner,
        recipient_addr,
        transactor_addr: option::none(),
        coin_type,
        access_version: 0,
        settle_version: 0,
        max_players,
        players: vector::empty<PlayerJoin>(),
        deposits: vector::empty<PlayerDeposit>(),
        servers: vector::empty<ServerJoin>(),
        votes: vector::empty<Vote>(),
        unlock_time: option::none(),
        entry_type,
        data_len,
        data,
        checkpoint: vector::empty<u8>(),
        entry_lock: EntryLock::Open,
    };

    // record game id for return
    let game_id = object::uid_to_inner(&game.id);

    // share the game so everyone can access it
    transfer::share_object(game);

    game_id
}

public fun close_game(game: Game, ctx: &mut TxContext) {
    assert!(ctx.sender() == game.owner, EGameOwnerMismatch);
    assert!(vector::is_empty(&game.players), EGameIsNotEmpty);

    let Game {
        id,
        title: _,
        version: _,
        bundle_addr: _,
        owner: _,
        transactor_addr: _,
        recipient_addr: _,
        coin_type: _,
        access_version: _,
        settle_version: _,
        max_players: _,
        players: _,
        deposits: _,
        servers: _,
        data_len: _,
        data: _,
        votes: _,
        unlock_time: _,
        entry_type: _,
        checkpoint: _,
        entry_lock: _,
    } = game;

    object::delete(id);
}

/// Publish (mint) the game as NFT
public fun publish(
    name: String,
    bundle_url: String,
    cover_url: String,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    let nft = GameNFT {
        id: object::new(ctx),
        name,
        bundle_url,
        cover_url
    };

    event::emit(GameMinted {
        game_id: object::id(&nft),
        creator: sender,
        name: name
    });

    transfer::public_transfer(nft, sender);
}

/// Server joins a game
///
/// When a server joins an on-chain game, it can be either of the following cases:
/// 1. It is the first (indexed as 0) joined and thus it becomes the transactor
/// 2. It is the nth joined where n is in the range of [1,10] (inclusive)
public fun serve_game(
    game: &mut Game,
    server: &Server,
    verify_key: String,
    _ctx: &mut TxContext
) {
    let server_num = vector::length(&game.servers);
    assert!(server_num < MAX_SERVER_NUM, EServerNumberExceedsLimit);

    // check duplicate server join
    let server_addr = server.addr();
    let mut i = 0;
    while (i < server_num) {
        let curr_server: &ServerJoin = vector::borrow(&game.servers, i);
        if (curr_server.addr == server.owner()) abort EDuplicateServerJoin;
        i = i + 1;
    };

    let access_version = game.access_version + 1;

    vector::push_back(
        &mut game.servers,
        ServerJoin {
            addr: server_addr,
            endpoint: server.endpoint(),
            access_version,
            verify_key,
        }
    );
}

/// Player joins a game
public fun join_game(
    game: &mut Game,
    position: u16,
    _access_version: u64,
    join_amount: u64,
    verify_key: String,
    ctx: &TxContext
) {
    let player_num = game.player_num();
    let max_players = game.max_players();
    let sender = ctx.sender();

    assert!(player_num < max_players, EGameIsFull);
    assert!(position < max_players, EPositionOutOfRange);

    // the given position may have been already taken so we need to check availability
    let mut i = 0;
    // record all the positions currently already taken
    let mut pos_taken = vector::empty<u16>();
    while (i < player_num as u64) {
        let curr_player: &PlayerJoin = vector::borrow(&game.players, i);
        if (curr_player.addr == sender) {
            abort EDuplicatePlayerJoin
        };
        vector::push_back(&mut pos_taken, curr_player.position);
        i = i + 1;
    };

    // assume the given position not taken and try to verify this assumption
    let mut all_pos_taken = false;
    let mut avail_pos = position;
    if (vector::contains(&pos_taken, &position)) {
        // given position taken, try to find another one
        let mut j = 0;
        let mut found = false;
        while (j < max_players) {
            if (!vector::contains(&pos_taken, &j)) {
                // assign the position if found one
                avail_pos = j;
                found = true;
                break
            };
            j = j + 1;
        };
        all_pos_taken = !found;
    };
    // all positions taken so cannot join
    if (all_pos_taken) abort EPositionOutOfRange;

    // check entry type
    match (&game.entry_type) {
        EntryType::Cash { min_deposit, max_deposit } => {
            assert!(
                join_amount >= *min_deposit && join_amount <= *max_deposit,
                EInvalidCashDeposit
            );
        },
        EntryType::Ticket { amount } => {
            assert!(join_amount == *amount, EInvalidTicketAmount);
        },
        // the following two has not been implemented
        EntryType::Gating { collection: _ } => (),
        EntryType::Disabled => (),
    };

    // bump access version
    game.access_version = game.access_version + 1;

    // player joins
    vector::push_back(
        &mut game.players,
        PlayerJoin {
            addr: sender,
            position: avail_pos,
            access_version: game.access_version,
            verify_key,
        });

    vector::push_back(
        &mut game.deposits,
        PlayerDeposit {
            addr: sender,
            amount: join_amount,
            access_version: game.access_version,
            settle_version: game.settle_version,
            status: DepositStatus::Accepted
        }
    );
}


// === Public-view functions ===
public fun title(self: &Game): String {
    self.title
}

public fun bundle_addr(self: &Game): address {
    self.bundle_addr
}

public fun game_id(self: &Game): ID {
    object::uid_to_inner(&self.id)
}

public fun player_num(self: &Game): u16 {
    vector::length(&self.players) as u16
}

public fun max_players(self: &Game): u16 {
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

public fun bundle_url(nft: &GameNFT): String {
    nft.bundle_url
}

public fun cover_url(nft: &GameNFT): String {
    nft.cover_url
}

public fun name(nft: &GameNFT): String {
    nft.name
}
