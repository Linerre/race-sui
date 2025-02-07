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
const EInvalidBuyinAmount: u64 = 4207;
const EGameStateNotReady: u64 = 4208;
const EBalanceChangeUnderflow: u64 = 4209;
const EInvalidBalanceChange: u64 = 4210;
const EInvalidBalanceChangeType: u64 = 4211;

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

// The change shows the `Diff` between a player's balance recorded in the
// previous checkpoint and the balance for this settlement. For example:
// At the beginning, player A has a total balance of 100 and in the first
// setttlement lost 50, the balance changes: 100 -> 50; diff: 0 -> Add(50)
// Add/Sub has nothing to do with the player's balance gain or loss, it shows
// only the difference of current balance and the previous one
public enum BalanceChange has copy, drop, store {
    Add(u64),
    Sub(u64),
}

// TODO: need a phantom T?
public struct PlayerBalance has copy, drop, store {
    // identical to access_version
    player_id: u64,
    // current balance of this player
    balance: u64,
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
    /// total deposits from players, on-chain only and used in settlement
    stake: Balance<T>,
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
    bonuses: vector<Bonus>,
    /// players' balances for the current settle version, stored on-and-off chain
    player_balances: vector<PlayerBalance>,
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
        stake: balance::zero<T>(),
        player_balances: vector::empty<PlayerBalance>(),
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

    let Game {id, stake, bonuses, .. } = game;
    // will abort with ENonZero if the stake is not zero
    balance::destroy_zero(stake);
    vector::destroy_empty(bonuses);

    object::delete(id);
}

/// Publish (mint) the game as NFT
#[allow(lint(self_transfer))]
public fun publish(
    name: String,
    symbol: String,
    bundle_url: String,
    cover_url: String,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    let nft = GameNFT {
        id: object::new(ctx),
        name,
        symbol,
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
    let server_owner = server.owner();
    let mut i = 0;
    while (i < server_num) {
        let curr_server: &ServerJoin = vector::borrow(&game.servers, i);
        if (curr_server.addr == server_owner) abort EDuplicateServerJoin;
        i = i + 1;
    };

    // bump game access_version
    game.access_version = game.access_version + 1;

    vector::push_back(
        &mut game.servers,
        ServerJoin {
            addr: server_owner,
            endpoint: server.endpoint(),
            access_version: game.access_version,
            verify_key,
        }
    );

    // if this is the first-joined server, make it transactor
    if (game.servers.length() == 1 && game.transactor_addr.is_none()) {
        game.transactor_addr.swap_or_fill(server_owner);
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
            if (deposit.access_version == reject) {
                assert!(
                    deposit.status == DepositStatus::Pending,
                    EDuplicateDepositRejection
                );
                deposit.status = DepositStatus::Rejected;
                let receiver = deposit.addr;
                let payback: Coin<T> = coin::from_balance(
                    game.stake.split(deposit.amount),
                    ctx
                );
                transfer::public_transfer(payback, receiver);
                deposit.status = DepositStatus::Refunded;
                found = true;
                break
            };
            // else continue
            j = j + 1;
        };
        if (!found) abort ERejectDepositNotFound;
        i = i + 1;
    };

    // Remove the rejected players as well so they can join again later
    game.eject_players(rejects);
}

// Player joins a game. On the front end, player coins must be merged when
// there is no single coin with sufficient balance for buyin
public fun join_game<T>(
    game: &mut Game<T>,
    position: u16,
    join_amount: u64,
    // buyin_amount: u64,
    verify_key: String,
    mut player_coins: vector<Coin<T>>,
    ctx: &mut TxContext
) {
    // assert!(join_amount == buyin_amount, EInvalidBuyinAmount);
    if (game.transactor_addr.is_none() || game.checkpoint.length() <= 0)
    abort EGameStateNotReady;

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

    // check join amount
    let mut buyin = 0;
    let coin_num = player_coins.length();
    i = 0;
    while (i < coin_num) {
        let pcoin: &Coin<T> = player_coins.borrow(i);
        buyin = buyin + pcoin.value();
        i = i + 1;
    };
    assert!(buyin == join_amount, EInvalidBuyinAmount);

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

    // update game balance by adding the player's buyin coin into game balance
    while (!player_coins.is_empty()) {
        let pcoin: Coin<T> = player_coins.pop_back();
        game.stake.join(pcoin.into_balance());
    };
    vector::destroy_empty(player_coins);

    // record this deposit in game deposits
    game.deposits.push_back(
        PlayerDeposit {
            addr: sender,
            amount: join_amount,
            access_version: game.access_version,
            settle_version: game.settle_version,
            status: DepositStatus::Pending
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
    game.stake.join(buyin.into_balance());

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
public(package) fun new_balance_change(change_type: u8, amount: u64): BalanceChange {
    match (change_type) {
        1 => BalanceChange::Add(amount),
        2 => BalanceChange::Sub(amount),
        _ => abort EInvalidBalanceChangeType
    }
}


/// Split amount out of game's stake.
public(package) fun split_stake<T>(self: &mut Game<T>, amount: u64): Balance<T> {
    balance::split(&mut self.stake, amount)
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

public(package) fun update_settle_version<T>(self: &mut Game<T>, new_settle_version: u64) {
    self.settle_version = new_settle_version;
}

public(package) fun update_checkpoint_data<T>(
    self: &mut Game<T>,
    new_checkpoint_data: vector<u8>
) {
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

// Update the balances of a given player recorded in `player_balances`
public(package) fun change_player_balance<T>(
    self: &mut Game<T>,
    player_id: u64,
    change: BalanceChange
) {
    let mut i = 0;
    let n = self.player_balances.length();
    let mut found = false;
    // if there is a record, update it
    while(i < n) {
        let pb = self.player_balances.borrow_mut(i);
        if (pb.player_id == player_id) {
            match (change) {
                BalanceChange::Add(amt) => pb.balance = pb.balance + amt,
                BalanceChange::Sub(amt) => {
                    assert!(pb.balance >= amt, EBalanceChangeUnderflow);
                    pb.balance = pb.balance - amt;
                }
            };
            found = true;
            break
        };
        i = i + 1;
    };

    // if there is none, add the new record only when it is an `Add` diff
    if(!found) {
        match (change) {
            BalanceChange::Add(amt) => self.player_balances.push_back(
                    PlayerBalance {
                        player_id,
                        balance: amt
                    }),
            BalanceChange::Sub(_amt) => abort EInvalidBalanceChange
        }
    };
}

public(package) fun validate_stake<T>(self: &Game<T>): bool {
    let mut i = 0u64;
    let mut sum_pending = 0u64;
    let mut sum_rejected = 0u64;
    let mut sum_balances = 0u64;

    let n = self.deposits.length();
    while(i < n) {
        let deposit = self.deposits.borrow(i);
        match (deposit.status) {
            DepositStatus::Rejected => sum_rejected = sum_rejected + deposit.amount,
            DepositStatus::Pending => sum_pending = sum_pending + deposit.amount,
            _ => ()
        };
        i = i + 1;
    };

    i = 0;
    let m = self.player_balances.length();
    while(i < m) {
        let pb = self.player_balances.borrow(i);
        sum_balances = sum_balances + pb.balance;
        i = i + 1;
    };
    // expect true
    self.stake.value() == sum_balances + sum_pending + sum_rejected
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

public(package) fun is_rejected(self: &PlayerDeposit): bool {
    match (self.status) {
        DepositStatus::Rejected => true,
        _ => false
    }
}

public(package) fun retain_pending_deposits<T>(self: &mut Game<T>) {
    let mut i = 0;
    let n = self.deposits.length();
    let mut to_retain = vector::empty<PlayerDeposit>();
    while (i < n) {
        let deposit = self.deposits.borrow(i);
        if (deposit.is_pending() || deposit.is_rejected()) {
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
    let n = accept_deposits.length();
    let m = self.deposits.length();
    while (i < n) {
        let accept = accept_deposits.borrow(i);
        // search for this accepted version in game deposits
        let mut j = 0;
        while(j < m) {
            let game_deposit = self.deposits.borrow_mut(j);
            if (accept == game_deposit.access_version) {
                game_deposit.status = DepositStatus::Accepted;
                break
            };
            // else continue
            j = j + 1;
        };
        i = i + 1;
    }
}

// Remove any that has a zero balance
public(package) fun update_player_balances<T>(self: &mut Game<T>) {
    let mut to_retain = vector::empty<PlayerBalance>();
    let mut i = 0;

    let n = self.player_balances.length();
    while(i < n) {
        let bl = self.player_balances.borrow(i);
        if (bl.balance > 0) {
            to_retain.push_back(*bl);
        };
        i = i + 1;
    };

    self.player_balances = to_retain;
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

public fun stake<T>(self: &Game<T>): u64 {
    self.stake.value()
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


// ==== Test only ===
#[test_only]
public(package) fun make_fake_game<T>(ctx: &mut TxContext): Game<T> {
    let test_coin = coin::mint_for_testing<T>(2000_000_000, ctx);
    Game<T> {
    id: object::new(ctx),
    version: string::utf8(b"0.1.0"),
    title: string::utf8(b"Test SUI"),
    bundle_addr: @0xb38c37e13d9b1ca471583f0f46e0483afdcd15fcc0ab84a34ccef2d009a9fd57,
    token_addr: string::utf8(b"0x2::sui::SUI"),
    owner: @0x7a1f6dc139d351b41066ea726d9b53670b6d827a0745d504dc93e61a581f7192,
    recipient_addr: @0x4df6428542d32575158855b8186e6049a6cef9ff3934988247665dbc400ec5c0,
    transactor_addr: option::some(@0x7a1f6dc139d351b41066ea726d9b53670b6d827a0745d504dc93e61a581f7192),
    access_version: 3,
    settle_version: 1,
    max_players: 6,
    players: vector[
        PlayerJoin {
            addr: @0xd59f7460183d4fee9a4fccc1c80643ed42ed5f52c32cca3a99a9f59b575236a8,
            position: 0,
            access_version: 2,
            verify_key: string::utf8(b"MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEPB+qehcObinvMUxfhRbUqzfZdA+JfuSzajnUCmkJSPh7okaBU+FCP2Goj9X27Y6Cz8YVPm2luGjZ5WGG42EHeg==")
        },
        PlayerJoin {
            addr: @0x5b6eb18e764749862726832bf35e37d597975d234ef341fb39770a736879bc7b,
            position: 1,
            access_version: 3,
            verify_key: string::utf8(b"MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEm9ZYlsKI8Kht1BwRW1Y+4EEJPhOhIVuYMehw3xhUQfstIyCh5PDhptt/w8H8A1SOoXqHdKi251kspCZt3PhzfQ==")
        }
    ],
    servers: vector[
        ServerJoin {
            addr: @0x7a1f6dc139d351b41066ea726d9b53670b6d827a0745d504dc93e61a581f7192,
            endpoint: string::utf8(b"wss://tx-sui-devnet.racepoker.app"),
            access_version: 1,
            verify_key: string::utf8(b"MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEFpM0hCi+niuXfnVLY2BOnWzdm+YLFt5YkJRPp/TIJU21v49mim/eo01iK3Mfi1Be8TSwyL6vZLjGlYluZ1w3bw==")
        }],
       deposits: vector[
           PlayerDeposit {
               addr: @0xd59f7460183d4fee9a4fccc1c80643ed42ed5f52c32cca3a99a9f59b575236a8,
               amount: 1000000000,
               access_version: 2,
               settle_version: 1,
               status: DepositStatus::Accepted
           },
           PlayerDeposit {
               addr: @0x5b6eb18e764749862726832bf35e37d597975d234ef341fb39770a736879bc7b,
               amount: 1000000000,
               access_version: 3,
               settle_version: 1,
               status: DepositStatus::Accepted
           }
    ],
    stake: test_coin.into_balance(),
    data_len: 36,
    data: vector[],
    votes: vector[],
    unlock_time: option::none(),
    entry_type: EntryType::Cash { min_deposit: 1000000000, max_deposit: 2000000000 },
    checkpoint: vector[],
    entry_lock: EntryLock::Open,
    bonuses: vector[],
    player_balances: vector[]
    }
}

#[test_only]
public(package) fun share_game<T>(game: Game<T>) {
    transfer::share_object(game);
}

#[test_only]
fun make_fake_game2<T>(ctx: &mut TxContext): Game<T> {
    let test_coin = coin::mint_for_testing<T>(2000_000_000, ctx);
    Game<T> {
        id: object::new(ctx),
        version: string::utf8(b"0.1.0"),
        title: string::utf8(b"Test SUI"),
        bundle_addr: @0xb38c37e13d9b1ca471583f0f46e0483afdcd15fcc0ab84a34ccef2d009a9fd57,
        token_addr: string::utf8(b"0x2::sui::SUI"),
        owner: @0x7a1f6dc139d351b41066ea726d9b53670b6d827a0745d504dc93e61a581f7192,
        recipient_addr: @0x4df6428542d32575158855b8186e6049a6cef9ff3934988247665dbc400ec5c0,
        transactor_addr: option::some(@0x7a1f6dc139d351b41066ea726d9b53670b6d827a0745d504dc93e61a581f7192),
        access_version: 4,
        settle_version: 2,
        max_players: 6,
        players: vector[
            PlayerJoin {
                addr: @0xd59f7460183d4fee9a4fccc1c80643ed42ed5f52c32cca3a99a9f59b575236a8,
                position: 0,
                access_version: 3,
                verify_key: string::utf8(b"MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEPB+qehcObinvMUxfhRbUqzfZdA+JfuSzajnUCmkJSPh7okaBU+FCP2Goj9X27Y6Cz8YVPm2luGjZ5WGG42EHeg==")
            },
            PlayerJoin {
                addr: @0x5b6eb18e764749862726832bf35e37d597975d234ef341fb39770a736879bc7b,
                position: 1,
                access_version: 4,
                verify_key: string::utf8(b"MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEm9ZYlsKI8Kht1BwRW1Y+4EEJPhOhIVuYMehw3xhUQfstIyCh5PDhptt/w8H8A1SOoXqHdKi251kspCZt3PhzfQ==")
            }
        ],
        servers: vector[
            ServerJoin {
                    addr: @0x7a1f6dc139d351b41066ea726d9b53670b6d827a0745d504dc93e61a581f7192,
                    endpoint: string::utf8(b"wss://tx-sui-devnet.racepoker.app"),
                    access_version: 1,
                    verify_key: string::utf8(b"MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEFpM0hCi+niuXfnVLY2BOnWzdm+YLFt5YkJRPp/TIJU21v49mim/eo01iK3Mfi1Be8TSwyL6vZLjGlYluZ1w3bw==")
            }],
       deposits: vector[
           PlayerDeposit {
                    addr: @0x5b6eb18e764749862726832bf35e37d597975d234ef341fb39770a736879bc7b,
                    amount: 1000000000,
                    access_version: 3,
                    settle_version: 2,
                    status: DepositStatus::Pending
                },
           PlayerDeposit {
                    addr: @0x2a440a1c6224807c441c7cfb8aaee7ecdd6ab9ce9b263eef3d82793baf1c30b3,
                    amount: 1000000000,
                    access_version: 4,
                    settle_version: 2,
                    status: DepositStatus::Pending
                }
       ],
       stake: test_coin.into_balance(),
       data_len: 36,
       data: vector[],
       votes: vector[],
       unlock_time: option::none(),
       entry_type: EntryType::Cash { min_deposit: 1000000000, max_deposit: 2000000000 },
       checkpoint: vector[],
       entry_lock: EntryLock::Open,
       bonuses: vector[],
       player_balances: vector[
           PlayerBalance {balance: 0, player_id:3},
           PlayerBalance {balance: 100_000_000, player_id :4},
           PlayerBalance {balance: 0, player_id:5},
       ]
    }
}

#[test]
fun test_accept_deposits() {
    let mut ctx = tx_context::dummy();
    let mut game = make_fake_game2<0x2::sui::SUI>(&mut ctx);

    std::debug::print(&game.deposits);

    {
        let d1 = game.deposits.borrow(0);
        let d2 = game.deposits.borrow(1);
        assert!(d1.status == DepositStatus::Pending, 44);
        assert!(d2.status == DepositStatus::Pending, 44);
    };

    game.update_deposits(vector[3u64, 4u64, 3u64, 4u64]);
    let d1 = game.deposits.borrow(0);
    let d2 = game.deposits.borrow(1);
    assert!(d1.status == DepositStatus::Accepted, 44);
    assert!(d2.status == DepositStatus::Accepted, 44);
    std::debug::print(&game.deposits);
    share_game(game);
}

#[test]
fun test_update_balances() {
    let mut ctx = tx_context::dummy();
    let mut game = make_fake_game2<0x2::sui::SUI>(&mut ctx);
    std::debug::print(&game.player_balances);

    assert!(game.player_balances.length() == 3, 44);
    game.update_player_balances();
    assert!(game.player_balances.length() == 1, 44);

    std::debug::print(&game.player_balances);
    share_game(game);
}
