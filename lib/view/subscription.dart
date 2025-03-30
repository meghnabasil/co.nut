import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dup/view/productlist.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Subscription extends StatefulWidget {
  @override
  _SubscriptionState createState() => _SubscriptionState();
}

class _SubscriptionState extends State<Subscription> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, List<Map<String, dynamic>>> _productsByPlan = {
    'oneYear': [],
    'sixMonths': [],
  };
  bool _isLoading = true;
  bool _showLoadingIndicator = true;

  @override
  void initState() {
    super.initState();
    _startLoadingSequence();
  }

  void _startLoadingSequence() async {
    // Start both the delay and data fetching simultaneously
    final fetchFuture = _fetchSubscriptionProducts();
    final delayFuture = Future.delayed(Duration(seconds: 3));

    await Future.wait([fetchFuture, delayFuture]);

    if (mounted) {
      setState(() {
        _showLoadingIndicator = false;
      });
    }
  }

  Future<void> _fetchSubscriptionProducts() async {
    try {
      setState(() => _isLoading = true);

      final productsSnapshot = await _firestore
          .collection('products')
          .where('isSubscription', isEqualTo: true)
          .get();

      _productsByPlan = {
        'oneYear': [],
        'sixMonths': [],
      };

      for (final productDoc in productsSnapshot.docs) {
        final subscriptionSnapshot = await productDoc.reference
            .collection('subscriptionData')
            .get();

        if (subscriptionSnapshot.docs.isNotEmpty) {
          final subscriptionData = subscriptionSnapshot.docs.first.data();
          final productData = productDoc.data() as Map<String, dynamic>;

          if (subscriptionData['oneYear'] != null) {
            final oneYearPlan = subscriptionData['oneYear'] as Map<String, dynamic>;
            _productsByPlan['oneYear']!.add({
              'id': productDoc.id,
              ...productData,
              'planType': 'oneYear',
              'planDetails': oneYearPlan,
              'createdAt': subscriptionData['createdAt'],
            });
          }

          if (subscriptionData['sixMonths'] != null) {
            final sixMonthsPlan = subscriptionData['sixMonths'] as Map<String, dynamic>;
            _productsByPlan['sixMonths']!.add({
              'id': productDoc.id,
              ...productData,
              'planType': 'sixMonths',
              'planDetails': sixMonthsPlan,
              'createdAt': subscriptionData['createdAt'],
            });
          }
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print("Error fetching subscription products: $e");
      _showSnackBar("Failed to load subscription products");
      setState(() {
        _isLoading = false;
        _showLoadingIndicator = false;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  void _showProductsDialog(String plan) {
    final products = _productsByPlan[plan] ?? [];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("${plan == 'oneYear' ? '1-Year' : '6-Month'} Subscription"),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: products.isEmpty
                ? Center(child: Text("No products available"))
                : ListView.builder(
              shrinkWrap: true,
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                final planDetails = product['planDetails'] as Map<String, dynamic>;

                return Card(
                  margin: EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.all(12),
                    leading: product['imageUrl'] != null
                        ? Image.network(product['imageUrl'], width: 50, height: 50)
                        : Icon(Icons.shopping_basket, color: Color(0xFF033015)),
                    title: Text(product['name'] ?? 'Unnamed Product',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Price: \$${planDetails['price']?.toStringAsFixed(2) ?? '0.00'}'),
                        Text('Delivery: ${planDetails['deliveryFrequency'] ?? 'Not specified'}'),
                        Text('Quantity: ${planDetails['quantity'] ?? '0'}'),
                        if (product['createdAt'] != null)
                          Text('Created: ${DateFormat('MMM d, y').format((product['createdAt'] as Timestamp).toDate())}',
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProductDetail(productId: product['id']),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close", style: TextStyle(color: Color(0xFF033015))),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF033015)),
          SizedBox(height: 20),
          Text(
            "Loading Subscription Plans...",
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFF033015),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF033015),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text("Subscription Plans", style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: _showLoadingIndicator
          ? _buildLoadingScreen()
          : _isLoading
          ? Center(child: CircularProgressIndicator(color: Color(0xFF033015)))
          : Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SubscriptionCard(
              title: "1-Year Subscription",
              description: "Best value with monthly deliveries",
              productCount: _productsByPlan['oneYear']?.length ?? 0,
              color: Color(0xFF033015),
              onTap: () => _showProductsDialog('oneYear'),
            ),
            SizedBox(height: 20),
            SubscriptionCard(
              title: "6-Month Subscription",
              description: "Flexible mid-term option",
              productCount: _productsByPlan['sixMonths']?.length ?? 0,
              color: Colors.grey[900]!,
              onTap: () => _showProductsDialog('sixMonths'),
            ),
          ],
        ),
      ),
    );
  }
}

class SubscriptionCard extends StatelessWidget {
  final String title;
  final String description;
  final int productCount;
  final Color color;
  final VoidCallback onTap;

  const SubscriptionCard({
    required this.title,
    required this.description,
    required this.productCount,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: color,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                  Chip(
                    label: Text('$productCount ${productCount == 1 ? 'item' : 'items'}',
                        style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.black.withOpacity(0.3),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(description,
                  style: TextStyle(fontSize: 16, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

