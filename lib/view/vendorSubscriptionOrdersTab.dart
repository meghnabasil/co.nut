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

  static const String noOrdersText = "No Orders yet";
  static const String fetchingOrderError = "Error fetching orders: ";

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
          'nextDeliveryDate': data['nextDeliveryDate'] != null
              ? (data['nextDeliveryDate'] as Timestamp).toDate()
              : null,
        };
      }).toList();

      setState(() {
        _subscriptionOrders = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$fetchingOrderError$e')),
      );
    }
  }

  Future<void> _updateDeliveryStatus(String orderId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('subscriptionOrders')
          .doc(orderId)
          .update({'deliveryStatus': newStatus});
      _fetchSubscriptionOrders();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status: $e')),
      );
    }
  }

  Future<void> _updateNextDeliveryDate(String orderId, DateTime newDate) async {
    try {
      await FirebaseFirestore.instance
          .collection('subscriptionOrders')
          .doc(orderId)
          .update({'nextDeliveryDate': Timestamp.fromDate(newDate)});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Next delivery date updated')),
      );
      _fetchSubscriptionOrders();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating date: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subscriptionOrders.isEmpty
          ? const Center(child: Text(noOrdersText))
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
    String selectedStatus = order['deliveryStatus'] ?? 'Pending';
    DateTime? nextDeliveryDate = order['nextDeliveryDate'];

    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order['productName'] ?? 'Product',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            _buildOrderDetailRow("Customer", order['deliveryDetails']?['name'] ?? 'N/A'),
            _buildOrderDetailRow("Phone", order['deliveryDetails']?['phone'] ?? 'N/A'),
            _buildOrderDetailRow("Plan", _formatDuration(order['planDuration'])),
            _buildOrderDetailRow("Price", "₹${(order['price'] ?? 0).toString()}"),
            _buildOrderDetailRow("Quantity", order['quantity']?.toString() ?? 'N/A'),
            _buildOrderDetailRow("Frequency", order['deliveryFrequency'] ?? 'N/A'),
            _buildOrderDetailRow("Start Date", _formatDate(order['startDate'])),
            _buildOrderDetailRow("Payment Status", order['paymentStatus'] ?? 'N/A'),

            const Divider(height: 24),

            // Delivery Address
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Delivery Address", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order['deliveryDetails']?['address'] ?? ''),
                  Text("${order['deliveryDetails']?['city'] ?? ''}, ${order['deliveryDetails']?['state'] ?? ''}"),
                  Text("Pincode: ${order['deliveryDetails']?['pincode'] ?? ''}"),
                  if (order['deliveryDetails']?['instructions'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        "Instructions: ${order['deliveryDetails']['instructions']}",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                ],
              ),
            ),

            const Divider(height: 24),

            const Text("Delivery Management", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            _buildOrderDetailRow("Current Status", selectedStatus),
            _buildOrderDetailRow(
              "Next Delivery Date",
              nextDeliveryDate != null ? _formatDate(nextDeliveryDate) : "Not set",
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                const Text("Update Status: "),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: selectedStatus,
                  items: ['Pending', 'Delivered']
                      .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _updateDeliveryStatus(order['id'], value);
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 8),

            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: const Text("Set Next Delivery Date"),
              onPressed: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: nextDeliveryDate ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  await _updateNextDeliveryDate(order['id'], picked);
                }
              },
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
            width: 130,
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
