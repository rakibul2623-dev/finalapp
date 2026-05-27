class CartItem {
  final String productId;
  final String name;
  final double price;
  final int quantity;
  final String imageUrl;
  final String color;
  final String size;
  final double variantAdjustment;

  CartItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.imageUrl,
    required this.color,
    required this.size,
    required this.variantAdjustment,
  });

  CartItem copyWith({
    String? productId,
    String? name,
    double? price,
    int? quantity,
    String? imageUrl,
    String? color,
    String? size,
    double? variantAdjustment,
  }) {
    return CartItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      imageUrl: imageUrl ?? this.imageUrl,
      color: color ?? this.color,
      size: size ?? this.size,
      variantAdjustment: variantAdjustment ?? this.variantAdjustment,
    );
  }
}
