class PoolParticipant {
  final String userId;
  final double deposit;
  final String joinedAt;
  final bool isWinner;
  final double payout;
  final String username;
  final String displayName;
  final String avatarUrl;

  PoolParticipant({
    required this.userId,
    required this.deposit,
    required this.joinedAt,
    required this.isWinner,
    required this.payout,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
  });

  factory PoolParticipant.fromJson(Map<String, dynamic> json) {
    return PoolParticipant(
      userId: json['user_id'] ?? '',
      deposit: (json['deposit'] as num?)?.toDouble() ?? 0.0,
      joinedAt: json['joined_at'] ?? '',
      isWinner: (json['is_winner'] == 1 || json['is_winner'] == true),
      payout: (json['payout'] as num?)?.toDouble() ?? 0.0,
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? json['username'] ?? '',
      avatarUrl: json['avatar_url'] ?? '',
    );
  }
}

class PoolCreator {
  final String id;
  final String username;
  final String displayName;
  final String avatarUrl;

  PoolCreator({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
  });

  factory PoolCreator.fromJson(Map<String, dynamic> json) {
    return PoolCreator(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? json['username'] ?? '',
      avatarUrl: json['avatar_url'] ?? '',
    );
  }
}

class Pool {
  final String id;
  final String creatorId;
  final double depositAmount;
  final int maxPlayers;
  final int currentPlayers;
  final double grossPool;
  final double platformFeePercent;
  final double platformFeeAmount;
  final double netPayout;
  final String status;
  final String description;
  final String? winnerId;
  final PoolCreator? winner;
  final String createdAt;
  final String? settledAt;
  final PoolCreator? creator;
  final List<PoolParticipant> participants;
  final String oddsToWin;
  final int slotsRemaining;
  final bool isFull;
  final String shareUrl;
  final String whatsappShareText;

  Pool({
    required this.id,
    required this.creatorId,
    required this.depositAmount,
    required this.maxPlayers,
    required this.currentPlayers,
    required this.grossPool,
    required this.platformFeePercent,
    required this.platformFeeAmount,
    required this.netPayout,
    required this.status,
    required this.description,
    this.winnerId,
    this.winner,
    required this.createdAt,
    this.settledAt,
    this.creator,
    required this.participants,
    required this.oddsToWin,
    required this.slotsRemaining,
    required this.isFull,
    required this.shareUrl,
    required this.whatsappShareText,
  });

  factory Pool.fromJson(Map<String, dynamic> json) {
    var rawParticipants = json['participants'] as List? ?? [];
    List<PoolParticipant> participantsList = rawParticipants
        .map((p) => PoolParticipant.fromJson(p as Map<String, dynamic>))
        .toList();

    return Pool(
      id: json['id'] ?? '',
      creatorId: json['creator_id'] ?? '',
      depositAmount: (json['deposit_amount'] as num?)?.toDouble() ?? 0.0,
      maxPlayers: json['max_players'] ?? 2,
      currentPlayers: json['current_players'] ?? 1,
      grossPool: (json['gross_pool'] as num?)?.toDouble() ?? 0.0,
      platformFeePercent: (json['platform_fee_percent'] as num?)?.toDouble() ?? 7.0,
      platformFeeAmount: (json['platform_fee_amount'] as num?)?.toDouble() ?? 0.0,
      netPayout: (json['net_payout'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'OPEN',
      description: json['description'] ?? '',
      winnerId: json['winner_id'],
      winner: json['winner'] != null ? PoolCreator.fromJson(json['winner']) : null,
      createdAt: json['created_at'] ?? '',
      settledAt: json['settled_at'],
      creator: json['creator'] != null ? PoolCreator.fromJson(json['creator']) : null,
      participants: participantsList,
      oddsToWin: json['odds_to_win'] ?? '',
      slotsRemaining: json['slots_remaining'] ?? 0,
      isFull: json['is_full'] ?? false,
      shareUrl: json['share_url'] ?? '',
      whatsappShareText: json['whatsapp_share_text'] ?? '',
    );
  }

  static List<Pool> mockPools() {
    final dericCreator = PoolCreator(
      id: 'usr_deric_001',
      username: 'deric',
      displayName: 'Deric',
      avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
    );
    final leratoCreator = PoolCreator(
      id: 'usr_lerato_002',
      username: 'lerato',
      displayName: 'Lerato K.',
      avatarUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150',
    );

    return [
      Pool(
        id: 'pool_demo_1v1',
        creatorId: 'usr_deric_001',
        depositAmount: 50.0,
        maxPlayers: 2,
        currentPlayers: 1,
        grossPool: 50.0,
        platformFeePercent: 7.0,
        platformFeeAmount: 7.0,
        netPayout: 93.0,
        status: 'OPEN',
        description: '⚡ Premier League Derby Showdown! 1v1 quick clash',
        createdAt: DateTime.now().toIso8601String(),
        creator: dericCreator,
        participants: [
          PoolParticipant(
            userId: 'usr_deric_001',
            deposit: 50.0,
            joinedAt: DateTime.now().toIso8601String(),
            isWinner: false,
            payout: 0.0,
            username: 'deric',
            displayName: 'Deric',
            avatarUrl: dericCreator.avatarUrl,
          ),
        ],
        oddsToWin: '50.00%',
        slotsRemaining: 1,
        isFull: false,
        shareUrl: 'https://splitbet.co.za/pools/pool_demo_1v1',
        whatsappShareText: 'Join my 1v1 SplitBet pool (R50)! Odds: 50%.',
      ),
      Pool(
        id: 'pool_demo_4p',
        creatorId: 'usr_lerato_002',
        depositAmount: 100.0,
        maxPlayers: 4,
        currentPlayers: 2,
        grossPool: 200.0,
        platformFeePercent: 7.0,
        platformFeeAmount: 28.0,
        netPayout: 372.0,
        status: 'OPEN',
        description: '🎯 Friday Night 4-Way Winner Takes All (R100)',
        createdAt: DateTime.now().toIso8601String(),
        creator: leratoCreator,
        participants: [
          PoolParticipant(
            userId: 'usr_lerato_002',
            deposit: 100.0,
            joinedAt: DateTime.now().toIso8601String(),
            isWinner: false,
            payout: 0.0,
            username: 'lerato',
            displayName: 'Lerato K.',
            avatarUrl: leratoCreator.avatarUrl,
          ),
          PoolParticipant(
            userId: 'usr_sipho_003',
            deposit: 100.0,
            joinedAt: DateTime.now().toIso8601String(),
            isWinner: false,
            payout: 0.0,
            username: 'sipho',
            displayName: 'Sipho M.',
            avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
          ),
        ],
        oddsToWin: '25.00%',
        slotsRemaining: 2,
        isFull: false,
        shareUrl: 'https://splitbet.co.za/pools/pool_demo_4p',
        whatsappShareText: 'Join Lerato\'s 4-way SplitBet pot (R100 entry)!',
      ),
    ];
  }
}

