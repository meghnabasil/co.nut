import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MySubscriptionsPage extends StatefulWidget {
  const MySubscriptionsPage({Key? key}) : super(key: key);

  @override
  State<MySubscriptionsPage> createState() => _MySubscriptionsPageState();
}

class _MySubscriptionsPageState extends State<MySubscriptionsPage> {
  List<Map<String, dynamic>> _userSubscriptions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserSubscriptions();
  }

  Future<void> _fetchUserSubscriptions() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      setState(() => _isLoading = true);

      final snapshot = await FirebaseFirestore.instance
          .collection('subscriptionOrders')
          .where('userId', isEqualTo: userId)
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
        _userSubscriptions = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching subscriptions: $e')),
      );
    }
  }

  Future<void> _updateSubscriptionStatus(String orderId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('subscriptionOrders')
          .doc(orderId)
          .update({'subscriptionStatus': status});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Subscription $status')),
      );
      _fetchUserSubscriptions(); // Refresh UI
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Subscriptions", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF033015),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userSubscriptions.isEmpty
          ? const Center(child: Text("No subscription history yet"))
          : ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _userSubscriptions.length,
        itemBuilder: (context, index) {
          final order = _userSubscriptions[index];
          return _buildHistoryCard(order);
        },
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> order) {
    final status = (order['subscriptionStatus'] ?? '').toLowerCase();

    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Name + Status Chip
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

            _buildRow("Plan", _formatDuration(order['planDuration'])),
            _buildRow("Price", "₹${order['price']?.toStringAsFixed(2) ?? '0.00'}"),
            _buildRow("Quantity", order['quantity']?.toString() ?? 'N/A'),
            _buildRow("Frequency", order['deliveryFrequency'] ?? 'N/A'),
            _buildRow("Start Date", _formatDate(order['startDate'])),
            _buildRow("Payment Status", order['paymentStatus'] ?? 'N/A'),

            const SizedBox(height: 12),
            const Divider(),

            // Delivery Address
            const Text("Delivery Address", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(order['deliveryDetails']['address'] ?? ''),
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

            //  Delivery status Section
            const Text("Delivery Status", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _buildRow("Delivery Status", (order['deliveryStatus'] ?? 'Pending').toUpperCase()),
            _buildRow("Next Delivery Date", _formatDate(order['nextDeliveryDate'])),

            const SizedBox(height: 12),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (status == 'active') ...[
                  ElevatedButton.icon(
                    onPressed: () => _updateSubscriptionStatus(order['id'], 'paused'),
                    icon: const Icon(Icons.pause_circle_filled),
                    label: const Text("Pause"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  ),
                ] else if (status == 'paused' || status == 'cancelled') ...[
                  ElevatedButton.icon(
                    onPressed: () => _updateSubscriptionStatus(order['id'], 'active'),
                    icon: const Icon(Icons.refresh),
                    label: const Text("Renew"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text("$label:", style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Color _getDeliveryStatusColor(String? status) {
    if (status == null) return Colors.grey;
    switch (status.toLowerCase()) {
      case 'delivered':
        return Colors.green;
      case 'pending':
        return Colors.orange;
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
