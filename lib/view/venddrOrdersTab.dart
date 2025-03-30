import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class VendorOrdersTab extends StatefulWidget {
  final String vendorID;

  const VendorOrdersTab({required this.vendorID});

  @override
  State<VendorOrdersTab> createState() => _VendorOrdersTabState();
}

class _VendorOrdersTabState extends State<VendorOrdersTab> {
  List<Map<String, dynamic>> _vendorOrders = [];
  bool _isLoading = true;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final int _limit = 10;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchVendorOrders();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        _hasMore &&
        !_isLoading) {
      _fetchVendorOrders(loadMore: true);
    }
  }

  Future<void> _fetchVendorOrders({bool loadMore = false}) async {
    if (!mounted) return;

    try {
      if (!loadMore) {
        setState(() {
          _isLoading = true;
          _vendorOrders = [];
        });
      }

      Query query = FirebaseFirestore.instance
          .collection('orders')
          .where('vendorId', arrayContains: widget.vendorID)
          .orderBy('createdAt', descending: true)
          .limit(_limit);

      if (loadMore && _lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();

      if (!mounted) return;
      if (snapshot.docs.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoading = false;
        });
        return;
      }

      _lastDocument = snapshot.docs.last;

      final List<Map<String, dynamic>> validOrders = [];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final products = data['products'] as List<dynamic>? ?? [];
        final List<Map<String, dynamic>> vendorProducts = [];

        for (final product in products) {
          try {
            final productId = product['productId']?.toString();
            if (productId == null) continue;

            final productDoc = await FirebaseFirestore.instance
                .collection('products')
                .doc(productId)
                .get();

            if (productDoc.exists &&
                productDoc['vendorId']?.toString() == widget.vendorID) {
              vendorProducts.add({
                ...product,
                'imageUrl': productDoc['images']?.isNotEmpty == true
                    ? productDoc['images'][0]
                    : null,
              });
            }
          } catch (e) {
            debugPrint('Error processing product: $e');
          }
        }

        if (vendorProducts.isNotEmpty) {
          final vendorAmount = vendorProducts.fold<double>(0, (sum, product) {
            return sum +
                ((product['price'] as num?)?.toDouble() ?? 0) *
                    ((product['quantity'] as num?)?.toInt() ?? 1);
          });

          validOrders.add({
            'id': doc.id,
            ...data,
            'products': vendorProducts,
            'amount': vendorAmount,
            'createdAt': (data['createdAt'] as Timestamp).toDate(),
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _vendorOrders.addAll(validOrders);
        _isLoading = false;
        _hasMore = validOrders.length == _limit;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading orders: ${e.toString()}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading && _vendorOrders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _vendorOrders.isEmpty
              ? const Center(child: Text("No orders containing your products"))
              : RefreshIndicator(
                  onRefresh: () async {
                    await _fetchVendorOrders();
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _vendorOrders.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _vendorOrders.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return _buildOrderCard(_vendorOrders[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Order #${order['orderId']?.substring(0, 8) ?? order['id'].substring(0, 8)}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(
                  label: Text(
                    order['status']?.toString().toUpperCase() ?? 'UNKNOWN',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: _getStatusColor(order['status']),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildOrderDetailRow(
                "Amount", "₹${order['amount']?.toStringAsFixed(2) ?? '0.00'}"),
            _buildOrderDetailRow("Date", _formatDate(order['createdAt'])),
            _buildOrderDetailRow(
                "Payment", order['paymentId'] != null ? "Paid" : "Pending"),

            // Add shipping address section here
            const SizedBox(height: 12),
            const Divider(),
            const Text("Shipping Address:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _buildAddressText(order['shippingAddress']),

            const SizedBox(height: 12),
            const Divider(),
            const Text("Your Products:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...(order['products'] as List<dynamic>).map(_buildProductItem),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressText(dynamic addressData) {
    if (addressData == null || addressData is! Map<String, dynamic>) {
      return const Text("No shipping address provided");
    }

    final address = addressData as Map<String, dynamic>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (address['name'] != null) Text("Name: ${address['name']}"),
        if (address['phone'] != null) Text("Phone: ${address['phone']}"),
        if (address['street'] != null) Text("Street: ${address['street']}"),
        if (address['city'] != null) Text("City: ${address['city']}"),
        if (address['state'] != null) Text("State: ${address['state']}"),
        if (address['postalCode'] != null)
          Text("Postal Code: ${address['postalCode']}"),
        if (address['country'] != null) Text("Country: ${address['country']}"),
      ],
    );
  }

  Widget _buildProductItem(dynamic product) {
    final productMap = product as Map<String, dynamic>;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: productMap['imageUrl'] != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      productMap['imageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.shopping_bag),
                    ),
                  )
                : const Icon(Icons.shopping_bag),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productMap['name'] ?? 'Product',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text("₹${productMap['price']?.toStringAsFixed(2) ?? '0.00'}"),
                Text(
                  "Qty: ${productMap['quantity']?.toString() ?? '1'}",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              "$label:",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.blue;
      case 'processing':
        return Colors.orange;
      case 'shipped':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return "${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }
}
