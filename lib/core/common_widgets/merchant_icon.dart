import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/categories.dart';

/// Shows a merchant brand logo if matched, otherwise the category icon.
/// Uses Clearbit PNG logos with emoji fallback. No SVG.
class MerchantIcon extends StatelessWidget {
  final String? brand;
  final String? notes;
  final String category;
  final double size;

  const MerchantIcon({
    super.key,
    this.brand,
    this.notes,
    required this.category,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final matched = brand != null
        ? merchantBrands.where((b) => b.name == brand).firstOrNull
        : matchMerchant(notes);

    final cat = getCategoryByName(category);
    final displayColor = matched?.color ?? cat.color;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: displayColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      clipBehavior: Clip.antiAlias,
      child: matched != null
          ? _buildBrandIcon(matched)
          : Icon(cat.icon, color: cat.color, size: size * 0.5),
    );
  }

  Widget _buildBrandIcon(MerchantBrand brand) {
    final domain = _domainFor(brand.name);
    if (domain != null) {
      return Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: CachedNetworkImage(
          imageUrl: 'https://logo.clearbit.com/$domain?size=128',
          fit: BoxFit.contain,
          placeholder: (context, url) => _emoji(brand),
          errorWidget: (context, url, error) => _emoji(brand),
        ),
      );
    }
    return _emoji(brand);
  }

  Widget _emoji(MerchantBrand brand) {
    return Center(child: Text(brand.emoji, style: TextStyle(fontSize: size * 0.45)));
  }

  static String? _domainFor(String name) {
    const map = {
      'Swiggy': 'swiggy.com', 'Zomato': 'zomato.com', 'Blinkit': 'blinkit.com',
      'Zepto': 'zeptonow.com', 'Amazon': 'amazon.in', 'Flipkart': 'flipkart.com',
      'Myntra': 'myntra.com', 'Nykaa': 'nykaa.com', 'Uber': 'uber.com',
      'Ola': 'olacabs.com', 'Netflix': 'netflix.com', 'Spotify': 'spotify.com',
      'Starbucks': 'starbucks.in', "McDonald's": 'mcdonaldsindia.com',
      'PhonePe': 'phonepe.com', 'Paytm': 'paytm.com', 'CRED': 'cred.club',
      'Google Pay': 'pay.google.com', 'BigBasket': 'bigbasket.com',
      'Hotstar': 'hotstar.com', 'YouTube': 'youtube.com', 'Dunzo': 'dunzo.com',
      'Rapido': 'rapido.bike', 'Meesho': 'meesho.com', 'Ajio': 'ajio.com',
      'KFC': 'kfc.co.in', 'Dominos': 'dominos.co.in', 'IRCTC': 'irctc.co.in',
      'Prime Video': 'primevideo.com',
    };
    return map[name];
  }
}
