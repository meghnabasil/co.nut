import 'package:flutter/material.dart';

class SubscriptionSuccessPage extends StatelessWidget {
  final Map<String, dynamic> subscriptionData;

  const SubscriptionSuccessPage({super.key, required this.subscriptionData});

  String _formatDuration(String duration) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Confirmed'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 80),
              const SizedBox(height: 24),
              Text(
                'Subscription Confirmed!',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Your ${_formatDuration(subscriptionData['planDuration'])} subscription for ${subscriptionData['productName']} is now active.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order Details',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Payment ID: ${subscriptionData['paymentId']}'),
                      Text('Amount: ₹${subscriptionData['price']}'),
                      Text('Delivery: ${subscriptionData['deliveryFrequency']}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  child: const Text('Back to Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}