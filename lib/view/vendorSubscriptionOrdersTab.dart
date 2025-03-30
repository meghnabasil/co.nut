import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class VendorSubscriptionOrderTabs extends StatefulWidget {
  final String vendorID;
  const VendorSubscriptionOrderTabs({required this.vendorID});

  @override
  State<VendorSubscriptionOrderTabs> createState() => _VendorSubscriptionOrderTabsState();
}

class _VendorSubscriptionOrderTabsState extends State<VendorSubscriptionOrderTabs> {
  List<Map<String, dynamic>> _subscriptionOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSubscriptionOrders();
  }

  Future<void> _fetchSubscriptionOrders() async {
    try {
      setState(() => _isLoading = true);

      final snapshot = await FirebaseFirestore.instance
          .collection('subscriptionOrders')
          .where('vendorId', isEqualTo: widget.vendorID)
          .get();

      final orders = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
          'startDate': (data['startDate'] as Timestamp).toDate(),
        };
      }).toList();

      setState(() {
        _subscriptionOrders = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching orders: $e')),
      );
    }
  }

  void _updateOrderStatus(String orderId, String newStatus) async {
    try {
      setState(() => _isLoading = true);

      await FirebaseFirestore.instance
          .collection('subscriptionOrders')
          .doc(orderId)
          .update({'subscriptionStatus': newStatus});

      // Update local state
      setState(() {
        final index = _subscriptionOrders.indexWhere((order) => order['id'] == orderId);
        if (index != -1) {
          _subscriptionOrders[index]['subscriptionStatus'] = newStatus;
        }
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order status updated successfully')),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating order: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subscriptionOrders.isEmpty
          ? const Center(child: Text("No Orders yet"))
          : ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _subscriptionOrders.length,
        itemBuilder: (context, index) {
          final order = _subscriptionOrders[index];
          return _buildOrderCard(order);
        },
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
                  order['productName'] ?? 'Product',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(
                  label: Text(
                    (order['subscriptionStatus'] ?? '').toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: _getStatusColor(order['subscriptionStatus']),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildOrderDetailRow("Order ID", order['id']),
            _buildOrderDetailRow("Customer", order['deliveryDetails']['name'] ?? 'N/A'),
            _buildOrderDetailRow("Phone", order['deliveryDetails']['phone'] ?? 'N/A'),
            _buildOrderDetailRow("Plan", _formatDuration(order['planDuration'])),
            _buildOrderDetailRow("Price", "₹${order['price']?.toStringAsFixed(2) ?? '0.00'}"),
            _buildOrderDetailRow("Quantity", order['quantity'] ?? 'N/A'),
            _buildOrderDetailRow("Frequency", order['deliveryFrequency'] ?? 'N/A'),
            _buildOrderDetailRow("Start Date", _formatDate(order['startDate'])),
            _buildOrderDetailRow("Payment Status", order['paymentStatus'] ?? 'N/A'),

            const SizedBox(height: 12),
            const Divider(),

            // Delivery Address
            const Text(
              "Delivery Address:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text("${order['deliveryDetails']['address'] ?? ''}"),
            Text("${order['deliveryDetails']['city'] ?? ''}, ${order['deliveryDetails']['state'] ?? ''}"),
            Text("Pincode: ${order['deliveryDetails']['pincode'] ?? ''}"),
            if (order['deliveryDetails']['instructions'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  "Instructions: ${order['deliveryDetails']['instructions']}",
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),

            const SizedBox(height: 12),
            if (order['subscriptionStatus'] == 'active')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _updateOrderStatus(order['id'], 'paused'),
                      child: const Text('Pause Subscription'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _updateOrderStatus(order['id'], 'cancelled'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      child: const Text('Cancel Subscription'),
                    ),
                  ),
                ],
              ),
            if (order['subscriptionStatus'] == 'paused')
              OutlinedButton(
                onPressed: () => _updateOrderStatus(order['id'], 'active'),
                child: const Text('Resume Subscription'),
              ),
          ],
        ),
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
      case 'active':
        return Colors.green;
      case 'paused':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      case 'completed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return "${date.day}/${date.month}/${date.year}";
  }

  String _formatDuration(String? duration) {
    if (duration == null) return 'N/A';
    switch (duration) {
      case 'oneMonth':
        return '1 Month';
      case 'threeMonths':
        return '3 Months';
      case 'sixMonths':
        return '6 Months';
      case 'oneYear':
        return '1 Year';
      default:
        return duration;
    }
  }
}