class UserBalance {
  final String userId;
  final String currency;
  final double available;
  final double reserved;
  final double total;

  UserBalance({
    required this.userId,
    required this.currency,
    required this.available,
    required this.reserved,
    required this.total,
  });

  factory UserBalance.fromJson(Map<String, dynamic> json) {
    return UserBalance(
      userId: json['user_id'] ?? '',
      currency: json['currency'] ?? 'ZAR',
      available: (json['available'] as num?)?.toDouble() ?? 0.0,
      reserved: (json['reserved'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
    );
  }

  UserBalance copyWith({
    String? userId,
    String? currency,
    double? available,
    double? reserved,
    double? total,
  }) {
    return UserBalance(
      userId: userId ?? this.userId,
      currency: currency ?? this.currency,
      available: available ?? this.available,
      reserved: reserved ?? this.reserved,
      total: total ?? this.total,
    );
  }
}

class UserStats {
  final int activePools;
  final int completedPools;
  final int wins;
  final int losses;
  final String winRate;
  final double totalWon;

  UserStats({
    required this.activePools,
    required this.completedPools,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.totalWon,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      activePools: json['active_pools'] ?? 0,
      completedPools: json['completed_pools'] ?? 0,
      wins: json['wins'] ?? 0,
      losses: json['losses'] ?? 0,
      winRate: json['win_rate'] ?? '0.0%',
      totalWon: (json['total_won'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AppUser {
  final String id;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String phone;
  final String email;
  final bool verified;
  final String subscriptionTier;
  final bool firstPoolCreated;
  final UserBalance balance;
  final UserStats? stats;

  AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.phone,
    required this.email,
    required this.verified,
    required this.subscriptionTier,
    required this.firstPoolCreated,
    required this.balance,
    this.stats,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? json['username'] ?? '',
      avatarUrl: json['avatar_url'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      verified: (json['verified'] == 1 || json['verified'] == true),
      subscriptionTier: json['subscription_tier'] ?? 'Standard',
      firstPoolCreated: (json['first_pool_created'] == 1 || json['first_pool_created'] == true),
      balance: json['balance'] != null
          ? UserBalance.fromJson(json['balance'])
          : UserBalance(userId: json['id'] ?? '', currency: 'ZAR', available: 0, reserved: 0, total: 0),
      stats: json['stats'] != null ? UserStats.fromJson(json['stats']) : null,
    );
  }

  static AppUser mockUser() {
    return AppUser(
      id: 'usr_deric_001',
      username: 'deric',
      displayName: 'Deric',
      avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      phone: '+27 82 000 0001',
      email: 'deric@splitbet.co.za',
      verified: true,
      subscriptionTier: 'Standard',
      firstPoolCreated: true,
      balance: UserBalance(
        userId: 'usr_deric_001',
        currency: 'ZAR',
        available: 1500.0,
        reserved: 0.0,
        total: 1500.0,
      ),
      stats: UserStats(
        activePools: 1,
        completedPools: 5,
        wins: 4,
        losses: 1,
        winRate: '80%',
        totalWon: 3200.0,
      ),
    );
  }

  static AppUser createDemoUser({required String username, required String displayName, String? avatarUrl}) {
    final uid = 'usr_${DateTime.now().millisecondsSinceEpoch}';
    return AppUser(
      id: uid,
      username: username.toLowerCase().trim(),
      displayName: displayName.trim(),
      avatarUrl: (avatarUrl != null && avatarUrl.trim().isNotEmpty)
          ? avatarUrl.trim()
          : 'https://api.dicebear.com/7.x/bottts/png?seed=$username',
      phone: '+27 82 000 0000',
      email: '${username.toLowerCase().trim()}@splitbet.co.za',
      verified: true,
      subscriptionTier: 'Standard',
      firstPoolCreated: false,
      balance: UserBalance(
        userId: uid,
        currency: 'ZAR',
        available: 1500.0,
        reserved: 0.0,
        total: 1500.0,
      ),
      stats: UserStats(
        activePools: 0,
        completedPools: 0,
        wins: 0,
        losses: 0,
        winRate: '0%',
        totalWon: 0.0,
      ),
    );
  }

  AppUser copyWith({
    String? id,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? phone,
    String? email,
    bool? verified,
    String? subscriptionTier,
    bool? firstPoolCreated,
    UserBalance? balance,
    UserStats? stats,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      verified: verified ?? this.verified,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      firstPoolCreated: firstPoolCreated ?? this.firstPoolCreated,
      balance: balance ?? this.balance,
      stats: stats ?? this.stats,
    );
  }
}

