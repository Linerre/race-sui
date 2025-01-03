#[allow(unused_function)]
module race_sui::game;
use std::string::{Self, String};
use sui::event;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use race_sui::server::Server;

// === Constants ===
const MAX_SERVER_NUM: u64 = 10;
const EServerNumberExceedsLimit: u64 = 410;
const EDuplicateServerJoin: u64 = 411;
const EGameStillHasPlayers: u64 = 412;
const EGameOwnerMismatch: u64 = 413;
const EInvalidCashDeposit: u64 = 414;
const EInvalidTicketAmount: u64 = 415;
const EPositionOutOfRange: u64 = 416;
const EDuplicatePlayerJoin: u64 = 417;
const EGameIsFull: u64 = 418;
const EInvalideVoteType: u64 = 419;
#[allow(unused_const)]
const EInsuffcientCoinBalance: u64 = 420;

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

public struct Bonus<T: key + store> has key {
    id: UID,
    identifier: String,
    token_addr: String,
    amount: u64,                // if 0, object is an nft
    object: T                   // Coin<T> or an nft object
}

// The parameter 'T' is only used as an argument to phantom parameters
/// On-chain game account
public struct Game<phantom T> has key {
    id: UID,
    /// the contract version, used for upgrade
    version: String,
    /// game name displayed on chain
    title: String,
    // TODO: may simplify this to a string arweave tx id
    /// AccountAddress to the game (WASM) as an NFT
    bundle_addr: address,
    /// coin type used in this game, e.g. "0x02::sui::SUI"
    token_addr: String,
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
    /// total deposits (stake) from players and used for settles and transfers
    balance: Balance<T>,
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
    /// game bonuses, each is an on-chain object
    bonuses: vector<ID>
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

public fun create_game<T>(
    title: String,
    bundle_addr: address,
    owner: address,
    recipient_addr: address,
    token_addr: String,
    max_players: u16,
    data_len: u32,
    data: vector<u8>,
    entry_type: EntryType,
    ctx: &mut TxContext
) {
    let game = Game<T> {
        id: object::new(ctx),
        title,
        version: string::utf8(b"0.1.0"),
        bundle_addr,
        owner,
        recipient_addr,
        transactor_addr: option::none(),
        token_addr,
        access_version: 0,
        settle_version: 0,
        max_players,
        players: vector::empty<PlayerJoin>(),
        deposits: vector::empty<PlayerDeposit>(),
        servers: vector::empty<ServerJoin>(),
        votes: vector::empty<Vote>(),
        unlock_time: option::none(),
        entry_type,
        balance: balance::zero<T>(),
        data_len,
        data,
        checkpoint: vector::empty<u8>(),
        entry_lock: EntryLock::Open,
        bonuses: vector::empty<ID>()
    };

    // share the game so everyone can access it
    transfer::share_object(game);
}

#[allow(lint(self_transfer))]
public fun create_coin_bonus<T: key + store>(
    identifier: String,
    token_addr: String,
    amount: u64,
    coin: T,
    ctx: &mut TxContext
): ID {
    let sender = ctx.sender();
    let bonus: Bonus<T> = Bonus {
        id: object::new(ctx),
        identifier,
        token_addr,
        amount,
        object: coin
    };
    let bonus_id = bonus.id.uid_to_inner();
    transfer::transfer(bonus, sender);
    bonus_id
}

#[allow(lint(self_transfer))]
public fun create_object_bonus<T: key + store>(
    identifier: String,
    obj: T,
    ctx: &mut TxContext
): ID {
    let bonus: Bonus<T> = Bonus {
        id: object::new(ctx),
        identifier,
        token_addr: string::utf8(b"object_bonus"),
        amount: 0,
        object: obj
    };
    let bonus_id = bonus.id.uid_to_inner();
    transfer::transfer(bonus, ctx.sender());
    bonus_id
}

public fun attach_bonus<T>(
    game: &mut Game<T>,
    bonus_id: ID,
    _ctx: &mut TxContext
) {
    game.bonuses.push_back(bonus_id);
}

public fun close_game<T>(game: Game<T>, ctx: &mut TxContext) {
    assert!(ctx.sender() == game.owner, EGameOwnerMismatch);
    assert!(vector::is_empty(&game.players), EGameStillHasPlayers);

    let Game {id, balance, bonuses, .. } = game;
    // will abort with ENonZero if the balance is not zero
    balance::destroy_zero(balance);
    vector::destroy_empty(bonuses);

    object::delete(id);
}

/// Publish (mint) the game as NFT
#[allow(lint(self_transfer))]
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
/// 2. It is the nth joined where n is in the range of [1,9] (inclusive)
public fun serve_game<T>(
    game: &mut Game<T>,
    server: &Server,
    verify_key: String,
    _ctx: &mut TxContext
) {
    let server_num = vector::length(&game.servers);
    assert!(server_num <= MAX_SERVER_NUM, EServerNumberExceedsLimit);

    // check duplicate server join
    let server_addr = server.addr();
    let mut i = 0;
    while (i < server_num) {
        let curr_server: &ServerJoin = vector::borrow(&game.servers, i);
        if (curr_server.addr == server.owner()) abort EDuplicateServerJoin;
        i = i + 1;
    };

    // bump game access_version
    game.access_version = game.access_version + 1;

    vector::push_back(
        &mut game.servers,
        ServerJoin {
            addr: server_addr,
            endpoint: server.endpoint(),
            access_version: game.access_version,
            verify_key,
        }
    );
}

/// Player joins a game
#[allow(lint(self_transfer))]
public fun join_game<T>(
    game: &mut Game<T>,
    position: u16,
    _access_version: u64,
    join_amount: u64,
    verify_key: String,
    mut player_coin: Coin<T>,
    ctx: &mut TxContext
) {
    let player_num = game.player_num();
    let max_players = game.max_players();
    let sender = ctx.sender();

    assert!(player_num < max_players, EGameIsFull);
    assert!(position < max_players, EPositionOutOfRange);

    // check for duplicate player join
    let mut i = 0;
    let mut pos_taken = vector::empty<u16>();
    while (i < player_num as u64) {
        let curr_player: &PlayerJoin = vector::borrow(&game.players, i);
        if (curr_player.addr == sender) abort EDuplicatePlayerJoin;
        vector::push_back(&mut pos_taken, curr_player.position);
        i = i + 1;
    };

    // check if the given position already taken
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

    // update game balance and return the remaining coin to player
    let payment: Coin<T> = coin::split(&mut player_coin, join_amount, ctx);
    let player_balance: Balance<T> = coin::into_balance(payment);
    balance::join(&mut game.balance, player_balance);
    // FIXME: cannot transfer the remaining coin, use SplitCoin isntead
    transfer::public_transfer(player_coin, sender);

    // record this deposit in game deposits
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

// === Public within package ===
// These setters and getters are necessary as Sui Move makes all fields of any
// objects defined in this module private to this module only

/// Split amount out of game's balance.
public(package) fun split_balance<T>(self: &mut Game<T>, amount: u64): Balance<T> {
    balance::split(&mut self.balance, amount)
}

public(package) fun eject_player<T>(self: &mut Game<T>, index: u64) {
    let _ = vector::remove(&mut self.players, index);
}

public(package) fun validate_player_at_idx<T>(
    self: &Game<T>,
    index: u64,
    player_id: u64
): bool {
    let player = vector::borrow(&self.players, index);
    player.access_version == player_id
}

public(package) fun validate_player<T>(self: &Game<T>, player_id: u64): bool {
    let mut i = 0;
    let n = self.player_num() as u64;
    let mut found = false;
    while(i < n) {
        let player = self.players.borrow(i);
        if (player.access_version == player_id) {
            found = true;
            break
        };
        i = i + 1;
    };
    found
}

// if game has no transactor, this returns false
public(package) fun validat_sender<T>(self: &Game<T>, sender: &address): bool {
    self.transactor_addr.contains(sender)
}

public(package) fun has_bonus<T>(self: &Game<T>, bonus_id: &ID): bool {
    self.bonuses.contains(bonus_id)
}

public(package) fun validate_identifer<T: key + store>(
    self: &Bonus<T>,
    identifier: String
): bool {
    self.identifier == identifier
}

public(package) fun is_coin_bonus<T: key + store>(self: &Bonus<T>): bool {
    self.amount != 0
}

public(package) fun is_obj_bonus<T: key + store>(self: &Bonus<T>): bool {
    self.amount == 0
}

public(package) fun unpack_coin_bonus<T: key + store>(
    bonus: Bonus<Coin<T>>
): (UID, u64, Coin<T>) {
    let Bonus { id, amount, object, .. } = bonus;
    (id, amount, object)
}

public(package) fun unpack_obj_bonus<T: key + store>(
    bonus: Bonus<T>
): (UID, u64, T) {
    let Bonus { id, amount, object, .. } = bonus;
    (id, amount, object)
}


// === Public-view functions ===
public fun bonus_id<T: key + store>(self: &Bonus<T>): ID {
    self.id.uid_to_inner()
}

public fun title<T>(self: &Game<T>): String {
    self.title
}

public fun bundle_addr<T>(self: &Game<T>): address {
    self.bundle_addr
}

public fun game_id<T>(self: &Game<T>): ID {
    object::uid_to_inner(&self.id)
}

public fun player_num<T>(self: &Game<T>): u16 {
    vector::length(&self.players) as u16
}

public fun max_players<T>(self: &Game<T>): u16 {
    self.max_players
}

public(package) fun players<T>(self: &Game<T>): &vector<PlayerJoin> {
    &self.players
}

public(package) fun players_mut<T>(self: &mut Game<T>): &mut vector<PlayerJoin> {
    &mut self.players
}

// get a specific player's address
public(package) fun player_addr<T>(self: &Game<T>, index: u64): address {
    let player = vector::borrow(&self.players, index);
    player.addr
}

public fun servers<T>(self: &Game<T>): &vector<ServerJoin> {
    &self.servers
}

public fun servers_mut<T>(self: &mut Game<T>): &mut vector<ServerJoin> {
    &mut self.servers
}

public fun access_version<T>(self: &Game<T>): u64 {
    self.access_version
}

public fun settle_version<T>(self: &Game<T>): u64 {
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
