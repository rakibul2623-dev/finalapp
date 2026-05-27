import 'dart:async';

class PackagesService {
  /// Simulated fetch from local storage/sample until a backend is connected.
  /// Filters: season (hajj/umrah/ramadan/all), year (e.g., 2026/2027/all),
  /// sort: recommended | price_low | price_high
  Future<List<Map<String, dynamic>>> fetchPackages({
    String season = 'all',
    String year = 'all',
    String sort = 'recommended',
  }) async {
    // Small delay to show loading state
    await Future.delayed(const Duration(milliseconds: 350));

    final nowYear = DateTime.now().year;
    final sample = <Map<String, dynamic>>[
      {
        'id': 'pkg_basic_2026',
        'name': 'Essential Hajj 2026',
        'price': 3499.00,
        'duration_days': 10,
        'hotel_rating': 3,
        'group_size': 25,
        'locations': 'Makkah · Madinah',
        'departure_date': '2026-06-01',
        'return_date': '2026-06-11',
        'rating': 4.5,
        'review_count': 128,
        'tier': 'essential',
        'is_popular': false,
        'installment_available': true,
        'installment_months': 6,
        'installment_amount': 599.83,
        'image_url': 'https://images.unsplash.com/photo-1565557623262-c3a5d2e0b800?q=80&w=1600&auto=format&fit=crop',
      },
      {
        'id': 'pkg_premium_2026',
        'name': 'Premium Hajj 2026',
        'price': 5999.00,
        'duration_days': 14,
        'hotel_rating': 5,
        'group_size': 15,
        'locations': 'Makkah · Madinah · Jeddah',
        'departure_date': '2026-06-05',
        'return_date': '2026-06-19',
        'rating': 4.9,
        'review_count': 242,
        'tier': 'premium',
        'is_popular': true,
        'installment_available': true,
        'installment_months': 12,
        'installment_amount': 529.17,
        'image_url': 'https://images.unsplash.com/photo-1548013146-72479768bada?q=80&w=1600&auto=format&fit=crop',
      },
      {
        'id': 'pkg_umrah_ramadan',
        'name': 'Ramadan Umrah 2027',
        'price': 2199.00,
        'duration_days': 7,
        'hotel_rating': 4,
        'group_size': 20,
        'locations': 'Makkah · Madinah',
        'departure_date': '2027-03-15',
        'return_date': '2027-03-22',
        'rating': 4.7,
        'review_count': 86,
        'tier': 'popular',
        'is_popular': true,
        'installment_available': false,
        'image_url': 'https://images.unsplash.com/photo-1606046604972-77cc76aee944?q=80&w=1600&auto=format&fit=crop',
      },
      {
        'id': 'pkg_flex_${nowYear}',
        'name': 'Flexible Hajj Prep',
        'price': 1299.00,
        'duration_days': 3,
        'hotel_rating': 0,
        'group_size': 0,
        'locations': 'Online · Anywhere',
        'departure_date': '${nowYear}-01-01',
        'return_date': '${nowYear}-12-31',
        'rating': 4.2,
        'review_count': 54,
        'tier': 'essential',
        'is_popular': false,
        'installment_available': false,
        'image_url': 'https://images.unsplash.com/photo-1515378791036-0648a3ef77b2?q=80&w=1600&auto=format&fit=crop',
      },
    ];

    Iterable<Map<String, dynamic>> data = sample;

    if (season != 'all') {
      if (season == 'hajj') {
        data = data.where((p) => (p['name']?.toString().toLowerCase() ?? '').contains('hajj'));
      } else if (season == 'umrah' || season == 'ramadan') {
        data = data.where((p) => (p['name']?.toString().toLowerCase() ?? '').contains('umrah'));
      }
    }

    if (year != 'all') {
      data = data.where((p) => (p['departure_date']?.toString() ?? '').startsWith(year));
    }

    final list = data.toList();
    switch (sort) {
      case 'price_low':
        list.sort((a, b) => ((a['price'] as num).compareTo((b['price'] as num))));
        break;
      case 'price_high':
        list.sort((a, b) => ((b['price'] as num).compareTo((a['price'] as num))));
        break;
      default:
        // recommended: popular first, then rating desc
        list.sort((a, b) {
          final ap = (a['is_popular'] == true) ? 0 : 1;
          final bp = (b['is_popular'] == true) ? 0 : 1;
          if (ap != bp) return ap - bp;
          final ar = (a['rating'] as num?)?.toDouble() ?? 0;
          final br = (b['rating'] as num?)?.toDouble() ?? 0;
          return br.compareTo(ar);
        });
    }

    return list;
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchFeaturesByPackage(List<Map<String, dynamic>> pkgs) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final Map<String, List<Map<String, dynamic>>> res = {};
    for (final p in pkgs) {
      final id = p['id']?.toString() ?? '';
      res[id] = [
        {'feature': 'Return Flights'},
        {'feature': 'Visa Assistance'},
        {'feature': 'Guided Ziyarat'},
        {'feature': 'Airport Transfers'},
      ];
    }
    return res;
  }
}
