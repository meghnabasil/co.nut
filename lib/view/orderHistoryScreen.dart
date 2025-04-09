import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

class CombinedOrderHistoryScreen extends StatefulWidget {
  final String userId;

  const CombinedOrderHistoryScreen({super.key, required this.userId});

  @override
  State<CombinedOrderHistoryScreen> createState() => _CombinedOrderHistoryScreenState();
}

class _CombinedOrderHistoryScreenState extends State<CombinedOrderHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thanks for Ordering – Here is Your List!',style: TextStyle(fontSize: 15),),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _combinedOrdersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "No orders found",
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              var order = snapshot.data![index];
              return order['type'] == 'export'
                  ? _buildExportOrderCard(order)
                  : order['type'] == 'subscription'
                  ? _buildSubscriptionCard(order)
                  : _buildRegularOrderCard(order);
            },
          );
        },
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _combinedOrdersStream() {
    final exportStream = FirebaseFirestore.instance
        .collection('exportingOrders')
        .where('userId', isEqualTo: widget.userId)
        .snapshots();

    final subscriptionStream = FirebaseFirestore.instance
        .collection('subscriptionOrders')
        .where('userId', isEqualTo: widget.userId)
        .snapshots();

    final regularOrdersStream = FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: widget.userId)
        .snapshots();

    return Rx.combineLatest3(
      exportStream,
      subscriptionStream,
      regularOrdersStream,
          (QuerySnapshot exportSnapshot, QuerySnapshot subscriptionSnapshot, QuerySnapshot regularOrdersSnapshot) {
        // Convert to a Future that resolves with the combined list
        return _processOrders(
          exportSnapshot.docs,
          subscriptionSnapshot.docs,
          regularOrdersSnapshot.docs,
        );
      },
    ).asyncMap((future) => future); // Convert Future to Stream
  }

  Future<List<Map<String, dynamic>>> _processOrders(
      List<QueryDocumentSnapshot> exportDocs,
      List<QueryDocumentSnapshot> subscriptionDocs,
      List<QueryDocumentSnapshot> regularDocs,
      ) async {
    List<Map<String, dynamic>> allOrders = [];

    // Process export orders
    for (var doc in exportDocs) {
      var data = doc.data() as Map<String, dynamic>;
      var productData = await _fetchProductDetails(data['productId']);
      allOrders.add({
        'id': doc.id,
        'type': 'export',
        ...data,
        'productDetails': productData,
      });
    }

    // Process subscription orders
    for (var doc in subscriptionDocs) {
      var data = doc.data() as Map<String, dynamic>;
      var productData = await _fetchProductDetails(data['productId']);
      allOrders.add({
        'id': doc.id,
        'type': 'subscription',
        ...data,
        'productDetails': productData,
      });
    }

    // Process regular orders
    for (var doc in regularDocs) {
      var data = doc.data() as Map<String, dynamic>;
      List<Map<String, dynamic>> productsWithDetails = [];

      if (data['products'] != null) {
        for (var product in data['products']) {
          var productData = await _fetchProductDetails(product['productId']);
          productsWithDetails.add({
            ...product,
            'productDetails': productData,
          });
        }
      }

      allOrders.add({
        'id': doc.id,
        'type': 'regular',
        ...data,
        'products': productsWithDetails,
      });
    }

    // Sort by date (newest first)
    allOrders.sort((a, b) {
      Timestamp aDate = a['orderDate'] ?? a['startDate'] ?? a['createdAt'] ?? Timestamp.now();
      Timestamp bDate = b['orderDate'] ?? b['startDate'] ?? b['createdAt'] ?? Timestamp.now();
      return bDate.compareTo(aDate);
    });

    return allOrders;
  }

  Future<Map<String, dynamic>> _fetchProductDetails(String? productId) async {
    if (productId == null) return {};

    try {
      DocumentSnapshot productSnapshot = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();

      if (productSnapshot.exists) {
        return {
          'name': productSnapshot['name'],
          'price': productSnapshot['price'],
          'imageUrl': (productSnapshot['images'] is List && productSnapshot['images'].isNotEmpty)
              ? productSnapshot['images'][0]
              : null,
          'description': productSnapshot['description'],
        };
      }
      return {};
    } catch (e) {
      print("Error fetching product details: $e");
      return {};
    }
  }

  Widget _buildRegularOrderCard(Map<String, dynamic> order) {
    List<dynamic> products = order['products'] ?? [];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_bag, color: Colors.purple),
                const SizedBox(width: 8),
                Text(
                  "REGULAR ORDER",
                  style: TextStyle(
                    color: Colors.purple[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    (order['status'] ?? 'Processing').toString().toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  backgroundColor: _getStatusColor(order['status']),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Order #${order['id']?.substring(0, 8) ?? ''}",
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildOrderDetailRow("Amount", "₹${order['amount']?.toStringAsFixed(2) ?? '0.00'}"),
            _buildOrderDetailRow("Date", _formatDate(order['createdAt'])),
            if (order['paymentId'] != null)
              _buildOrderDetailRow("Payment ID", order['paymentId'] ?? 'N/A'),

            // Product List Section
            const SizedBox(height: 12),
            const Divider(),
            const Text(
              "Products:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...products.map((product) {
              final productDetails = product['productDetails'] ?? {};
              final quantity = product['quantity'] ?? '';
              final status = product['status'] ?? 'Unknown';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProductItem(productDetails, quantity: quantity),
                  const SizedBox(height: 4),
                  Text(
                    "Status: $status",
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const Divider(),
                ],
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOrderCard(Map<String, dynamic> order) {
    Map<String, dynamic> productDetails = order['productDetails'] ?? {};

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flight_takeoff, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  "EXPORT ORDER",
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    (order['status'] ?? 'Processing').toString().toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  backgroundColor: _getStatusColor(order['status']),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Product Info
            if (productDetails.isNotEmpty)
              _buildProductItem(productDetails),
            const SizedBox(height: 8),
            _buildOrderDetailRow("Order ID", order['id'] ?? 'N/A'),
            _buildOrderDetailRow("Amount", "₹${order['amount']?.toStringAsFixed(2) ?? '0.00'}"),
            _buildOrderDetailRow("Destination", order['selectedDestination'] ?? 'N/A'),
            _buildOrderDetailRow("Date", _formatDate(order['timestamp'] ?? order['orderDate'])),
            const SizedBox(height: 8),
            if (order['trackingNumber'] != null)
              _buildOrderDetailRow("Tracking", order['trackingNumber']),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard(Map<String, dynamic> subscription) {
    Map<String, dynamic> productDetails = subscription['productDetails'] ?? {};

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.autorenew, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  "SUBSCRIPTION",
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    (subscription['status'] ?? 'Active').toString().toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  backgroundColor: _getStatusColor(subscription['status']),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Product Info
            if (productDetails.isNotEmpty)
              _buildProductItem(productDetails),
            const SizedBox(height: 8),
            _buildOrderDetailRow("Subscription ID", subscription['id'] ?? 'N/A'),
            _buildOrderDetailRow("Plan", _formatDuration(subscription['planDuration'])),
            _buildOrderDetailRow("Price", "₹${subscription['price']?.toStringAsFixed(2) ?? '0.00'}"),
            _buildOrderDetailRow("Frequency", subscription['deliveryFrequency'] ?? 'N/A'),
            _buildOrderDetailRow("Start Date", _formatDate(subscription['startDate'])),
            if (subscription['endDate'] != null)
              _buildOrderDetailRow("End Date", _formatDate(subscription['endDate'])),
          ],
        ),
      ),
    );
  }

  Widget _buildProductItem(Map<String, dynamic> product, {int quantity = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Product Image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: product['imageUrl'] != null
                ? Image.network(
              product['imageUrl'].toString(),
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 60,
                height: 60,
                color: Colors.grey[200],
                child: const Icon(Icons.image_not_supported),
              ),
            )
                : Container(
              width: 60,
              height: 60,
              color: Colors.grey[200],
              child: const Icon(Icons.shopping_bag),
            ),
          ),
          const SizedBox(width: 12),
          // Product Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name']?.toString() ?? 'Product',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (product['description'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      product['description'].toString(),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  "₹${product['price']?.toStringAsFixed(2) ?? '0.00'}",
                  style: TextStyle(color: Colors.grey[700]),
                ),
                if (quantity > 1)
                  Text(
                    "Qty: $quantity",
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
      case 'completed':
      case 'active':
      case 'paid':
        return Colors.green;
      case 'processing':
      case 'pending':
        return Colors.orange;
      case 'cancelled':
      case 'failed':
        return Colors.red;
      case 'shipped':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    if (timestamp is Timestamp) {
      return "${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}";
    }
    return timestamp.toString();
  }

  String _formatDuration(String? duration) {
    if (duration == null) return 'N/A';
    switch (duration) {
      case 'sixMonths':
        return '6 Months';
      case 'threeMonths':
        return '3 Months';
      case 'oneMonth':
        return '1 Month';
      case 'oneYear':
        return '1 Year';
      default:
        return duration;
    }
  }
}