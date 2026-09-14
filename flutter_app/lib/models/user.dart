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
}
