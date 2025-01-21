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
const EGameIsNotEmpty: u64 = 412;
const EGameOwnerMismatch: u64 = 413;
const EInvalidCashDeposit: u64 = 414;
const EInvalidTicketAmount: u64 = 415;
const EPositionOutOfRange: u64 = 416;
const EDuplicatePlayerJoin: u64 = 417;
const EGameIsFull: u64 = 418;
const EInvalideVoteType: u64 = 419;
const EGameBonusNotClaimed: u64 = 420;
const EDuplicateDepositRejection: u64 = 4201;
const EGameHasNoTransactor: u64 = 4202;
const EInvalidRejectionTxSender: u64 = 4203;
const ERejectDepositNotFound: u64 = 4204;
const EPlayerNotInGame: u64 = 4205;
const EInvalidSettleVersion: u64 = 4206;

// === Structs ===
/// Only game owner can delete a game
public struct GameAdminCap has key {
    id: UID,
}

public enum EntryLock has copy, drop, store {
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

public enum DepositStatus has copy, drop, store {
    /// Default
    Pending,
    Rejected,
    Refunded,
    Accepted,
}

public struct PlayerJoin has copy, drop, store {
    addr: address,
    position: u16,
    access_version: u64,
    verify_key: String,
}

public struct ServerJoin has copy, drop, store {
    addr: address,
    endpoint: String,
    access_version: u64,
    verify_key: String,
}

public struct PlayerDeposit has copy, drop, store {
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

// Like `Prize` but only contains the information for qeurying purposes
public struct Bonus has copy, drop, store {
    // prize object id
    id: ID,
    // bonus identifier
    identifier: String,
    // 0xpackageid::Game::GameNFT or 0x2::coin::Coin<0xxxx::coin_type::CoinStruct>
    token_addr: String,
    // coin value or 0 (nft)
    amount: u64,
}

// The object that holds the actual bonus (A coin or NFT), used in settlement
public struct Prize<T: key + store> has key {
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
    /// address of the owner of the server that frist joined this game,
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
    bonuses: vector<Bonus>
}

public struct GameNFT has key, store {
    id: UID,
    /// name for the game NFT
    name: String,
    symbol: String,             // a short string representation of token info used in game
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
        bonuses: vector::empty<Bonus>()
    };

    // share the game so everyone can access it
    transfer::share_object(game);
}

public fun create_coin_bonus<T: key + store>(
    identifier: String,
    token_addr: String,
    amount: u64,
    coin: T,
    ctx: &mut TxContext
): Bonus {
    let prize: Prize<T> = Prize {
        id: object::new(ctx),
        identifier,
        token_addr,
        amount,
        object: coin
    };

    let prize_id = prize.id.uid_to_inner();
    transfer::share_object(prize);
    Bonus {
        id: prize_id,
        identifier,
        token_addr,
        amount
    }
}

public fun create_object_bonus<T: key + store>(
    identifier: String,
    obj: T,
    ctx: &mut TxContext
): Bonus {
    let prize: Prize<T> = Prize {
        id: object::new(ctx),
        identifier,
        token_addr: string::utf8(b"object_bonus"),
        amount: 0,
        object: obj
    };
    let prize_id = prize.id.uid_to_inner();
    transfer::share_object(prize);
    Bonus {
        id: prize_id,
        identifier,
        token_addr: string::utf8(b"object_bonus"),
        amount: 0
    }
}

public fun attach_bonus<T>(
    game: &mut Game<T>,
    bonus: Bonus,
    _ctx: &mut TxContext
) {
    game.bonuses.push_back(bonus);
}

public fun close_game<T>(game: Game<T>, ctx: &mut TxContext) {
    assert!(ctx.sender() == game.owner, EGameOwnerMismatch);
    assert!(game.players.is_empty(), EGameIsNotEmpty);
    assert!(game.bonuses.is_empty(), EGameBonusNotClaimed);

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
    symbol: String,
    bundle_url: String,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    let nft = GameNFT {
        id: object::new(ctx),
        name,
        symbol,
        bundle_url,
        cover_url: string::utf8(b"https://ar-io.net/RxxOQizlpeUfLJzDmNYSCrBRtIWibkAUC-VhO2coFbE")
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

    // if this is the first-joined server, make it transactor
    if (game.servers.length() == 1 && game.transactor_addr.is_none()) {
        game.transactor_addr.swap_or_fill(server.owner());
    };
}


/// Reject Player's Deposit
public fun reject_deposits<T>(
    game: &mut Game<T>,
    rejects: vector<u64>,
    ctx: &mut TxContext
) {
    assert!(game.transactor_addr.is_some(), EGameHasNoTransactor);
    assert!(ctx.sender() == *game.transactor_addr.borrow(), EInvalidRejectionTxSender);

    let n = rejects.length();
    let m = game.deposits.length();
    let mut i = 0;
    while (i < n) {
        let mut j = 0;
        let mut found = false;
        let reject = rejects.borrow(i);
        while (j < m ) {
            let deposit = game.deposits.borrow_mut(j);
            if (deposit.access_version != reject) {
                j = j + 1;
                continue
            } else {
                found = true;
                assert!(
                    deposit.status == DepositStatus::Pending,
                    EDuplicateDepositRejection
                );
                deposit.status = DepositStatus::Rejected;
                let receiver = deposit.addr;
                let payback: Coin<T> = coin::from_balance(
                    game.balance.split(deposit.amount),
                    ctx
                );
                transfer::public_transfer(payback, receiver);
                deposit.status = DepositStatus::Refunded;
                break
            }
        };
        if (!found) abort ERejectDepositNotFound;
        i = i + 1;
    };

    // Remove the rejected players as well so they can join again later
    game.eject_players(rejects);
}

/// Player joins a game
public fun join_game<T>(
    game: &mut Game<T>,
    position: u16,
    join_amount: u64,
    verify_key: String,
    player_coin: Coin<T>,
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
        }
    );

    // update game balance and return the remaining coin to player
    let player_balance: Balance<T> = player_coin.into_balance();
    game.balance.join(player_balance);

    // record this deposit in game deposits
    game.deposits.push_back(
        PlayerDeposit {
            addr: sender,
            amount: join_amount,
            access_version: game.access_version,
            settle_version: game.settle_version,
            status: DepositStatus::Accepted
        }
    );
}

// Allow players to rebuy
public fun deposit<T>(
    game: &mut Game<T>,
    buyin: Coin<T>,
    settle_version: u64,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    assert!(game.settle_version == settle_version, EInvalidSettleVersion);
    assert!(game.validate_player_addr(sender), EPlayerNotInGame);

    match (&game.entry_type) {
        EntryType::Cash {
            min_deposit, max_deposit
        } => { // deposit amount must be in the range of [min, max]
            let amount = buyin.value();
            if (amount < *min_deposit || amount > *max_deposit)
                abort EInvalidCashDeposit;
        },
        EntryType::Ticket { amount } => {
            assert!(buyin.value() == *amount, EInvalidTicketAmount);
        },
        _ => ()                 // unimplemented
    };

    let buyin_amount = buyin.value();
    game.balance.join(buyin.into_balance());

    // bump access version
    game.access_version = game.access_version + 1;

    // record this buyin_amount in game deposits
    game.deposits.push_back(
        PlayerDeposit {
            addr: sender,
            amount: buyin_amount,
            access_version: game.access_version,
            settle_version: settle_version,
            status: DepositStatus::Pending
        }
    );
}

public fun create_entry_lock(variant: u8): Option<EntryLock> {
    match (variant) {
        0 => option::some(EntryLock::Open),
        1 => option::some(EntryLock::JoinOnly),
        2 => option::some(EntryLock::DepositOnly),
        3 => option::some(EntryLock::Closed),
        _ => option::none<EntryLock>()
    }
}

// === Public within package ===
// These setters and getters are necessary as Sui Move makes all fields of any
// objects defined in this module private to this module only

/// Split amount out of game's balance.
public(package) fun split_balance<T>(self: &mut Game<T>, amount: u64): Balance<T> {
    balance::split(&mut self.balance, amount)
}

// Remove the players marked `eject` in settlement
public(package) fun eject_players<T>(self: &mut Game<T>, ejects: vector<u64>) {
    let mut i = 0;
    let mut to_retain = vector::empty<PlayerJoin>();
    let n = self.players.length();
    while (i < n) {
        if (!ejects.contains(&i)) {
            let player = self.players.borrow(i);
            to_retain.push_back(*player);
        };
        i = i + 1;
    };
    self.players = to_retain;
}

public(package) fun update_settle_verson<T>(self: &mut Game<T>, new_settle_version: u64) {
    self.settle_version = new_settle_version;
}

public(package) fun update_checkpoint_data<T>(
    self: &mut Game<T>,
    new_checkpoint_data: vector<u8>)
{
    self.checkpoint = new_checkpoint_data;
}

public(package) fun update_entry_lock<T>(
    self: &mut Game<T>,
    new_entry_lock: EntryLock
) {
    self.entry_lock = new_entry_lock;
}

public(package) fun clear_players<T>(
    self: &mut Game<T>,
) {
    self.players = vector::empty<PlayerJoin>();
}

public(package) fun clear_deposits<T>(
    self: &mut Game<T>,
) {
    self.deposits = vector::empty<PlayerDeposit>();
}

public(package) fun validate_player_at_idx<T>(
    self: &Game<T>,
    index: u64,
    player_id: u64
): bool {
    let player = vector::borrow(&self.players, index);
    player.access_version == player_id
}

public(package) fun validate_player_id<T>(self: &Game<T>, player_id: u64): bool {
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

public(package) fun validate_player_addr<T>(self: &Game<T>, addr: address): bool {
    let mut i = 0;
    let n = self.player_num() as u64;
    let mut found = false;
    while(i < n) {
        let player = self.players.borrow(i);
        if (player.addr == addr) {
            found = true;
            break
        };
        i = i + 1;
    };
    found
}

// if game has no transactor, this returns false
public(package) fun validate_sender<T>(self: &Game<T>, sender: &address): bool {
    self.transactor_addr.contains(sender)
}

public(package) fun validate_server<T>(self: &Game<T>, server_owner: address): bool {
    let mut i = 0;
    let n = self.servers.length();
    let mut found = false;
    while (i < n) {
        let sj = self.servers.borrow(i);
        if (sj.addr == server_owner) {
            found = true;
            break
        };
        i = i + 1;
    };
    found
}

public(package) fun validate_identifer<T: key + store>(
    self: &Prize<T>,
    identifier: String
): bool {
    self.identifier == identifier
}

public(package) fun has_bonus<T>(self: &Game<T>, bonus_id: &ID): bool {
    let mut i = 0;
    let n = self.bonuses.length();
    let mut found = false;
    while (i < n) {
        let b = self.bonuses.borrow(i);
        if (b.id == bonus_id) {
            found = true;
            break
        };
        i = i + 1;
    };
    found
}

public(package) fun unpack_bonus<T: key + store>(
    bonus: Prize<T>
): (UID, u64, T) {
    let Prize { id, amount, object, .. } = bonus;
    (id, amount, object)
}

public(package) fun is_pending(self: &PlayerDeposit): bool {
    match (self.status) {
        DepositStatus::Pending => true,
        _ => false
    }
}

public(package) fun retain_pending_deposits<T>(
    self: &mut Game<T>,
) {
    let mut i = 0;
    let n = self.deposits.length();
    let mut to_retain = vector::empty<PlayerDeposit>();
    while (i < n) {
        let deposit = self.deposits.borrow(i);
        if (deposit.is_pending()) {
            to_retain.push_back(*deposit);
        };
        i = i + 1;
    };
    self.deposits = to_retain;
}

public(package) fun update_deposits<T>(
    self: &mut Game<T>,
    accept_deposits: vector<u64>
) {
    let mut i = 0;
    let n = self.deposits.length();
    while (i < n) {
        let game_deposit = self.deposits.borrow_mut(i);
        let deposit = accept_deposits.borrow(i);
        if (*deposit == game_deposit.access_version) {
            game_deposit.status = DepositStatus::Accepted;
        };
        i = i + 1;
    }
}

// === Public-view functions ===
public fun bonus_id<T: key + store>(self: &Prize<T>): ID {
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
