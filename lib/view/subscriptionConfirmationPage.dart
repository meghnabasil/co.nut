import 'package:dup/view/subscriptionSuccessPage.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

class SubscriptionConfirmationPage extends StatefulWidget {
  final String productId;
  final String subscriptionDuration;

  const SubscriptionConfirmationPage({
    super.key,
    required this.productId,
    required this.subscriptionDuration,
  });

  @override
  State<SubscriptionConfirmationPage> createState() => _SubscriptionConfirmationPageState();
}

class _SubscriptionConfirmationPageState extends State<SubscriptionConfirmationPage> {
  final _formKey = GlobalKey<FormState>();
  late Razorpay _razorpay;
  bool _isLoading = true;
  bool _isProcessingPayment = false;

  // Product and subscription data
  Map<String, dynamic>? _productData;
  Map<String, dynamic>? _subscriptionPlan;
  String? _vendorId;

  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _pincodeController = TextEditingController();
  final TextEditingController _deliveryInstructionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    // Fetch product and subscription details
    _fetchProductDetails();
  }

  @override
  void dispose() {
    _razorpay.clear();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _deliveryInstructionsController.dispose();
    super.dispose();
  }

  Future<void> _fetchProductDetails() async {
    try {
      // Get product document
      final productDoc = await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .get();

      if (!productDoc.exists) {
        throw Exception('Product not found');
      }

      _productData = productDoc.data()!;
      _vendorId = _productData?['vendorId'];

      // Get subscription details from subcollection
      final subscriptionQuery = await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .collection('subscriptionData')
          .get();

      if (subscriptionQuery.docs.isEmpty) {
        throw Exception('No subscription plans found');
      }

      // Find the selected plan
      for (var doc in subscriptionQuery.docs) {
        final data = doc.data();
        if (data.containsKey(widget.subscriptionDuration)) {
          _subscriptionPlan = {
            'duration': widget.subscriptionDuration,
            'price': data[widget.subscriptionDuration]['price'],
            'quantity': data[widget.subscriptionDuration]['quantity'],
            'deliveryFrequency': data[widget.subscriptionDuration]['deliveryFrequency'],
          };
          break;
        }
      }

      if (_subscriptionPlan == null) {
        throw Exception('Selected plan not found');
      }

      // Pre-fill user data if available
      await _prefillUserData();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading product: $e')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _prefillUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _addressController.text = data['address'] ?? '';
          _cityController.text = data['city'] ?? '';
        });
      }
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    _saveSubscriptionToFirebase(response.paymentId!);
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    setState(() => _isProcessingPayment = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Payment failed: ${response.message}')),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    setState(() => _isProcessingPayment = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External wallet: ${response.walletName}')),
    );
  }

  Future<void> _saveSubscriptionToFirebase(String paymentId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      final subscriptionData = {
        'userId': user.uid,
        'productId': widget.productId,
        'productName': _productData?['name'],
        'vendorId': _vendorId,
        'planDuration': _subscriptionPlan?['duration'],
        'price': _subscriptionPlan?['price'],
        'quantity': _subscriptionPlan?['quantity'],
        'deliveryFrequency': _subscriptionPlan?['deliveryFrequency'],
        'paymentId': paymentId,
        'paymentStatus': 'completed',
        'subscriptionStatus': 'active',
        'startDate': FieldValue.serverTimestamp(),
        'deliveryDetails': {
          'name': _nameController.text,
          'phone': _phoneController.text,
          'address': _addressController.text,
          'city': _cityController.text,
          'state': _stateController.text,
          'pincode': _pincodeController.text,
          'instructions': _deliveryInstructionsController.text,
        },
      };

      await FirebaseFirestore.instance
          .collection('subscriptionOrders')
          .add(subscriptionData);

      setState(() => _isProcessingPayment = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SubscriptionSuccessPage(
            subscriptionData: subscriptionData,
          ),
        ),
      );
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving subscription: $e')),
      );
    }
  }

  void _openPaymentGateway() {
    if (!_formKey.currentState!.validate()) return;
    if (_subscriptionPlan == null) return;

    setState(() => _isProcessingPayment = true);

    final options = {
      'key': 'rzp_test_zrejXWOWxRf29k',
      'amount': (_subscriptionPlan!['price'] * 100).toInt(),
      'name': _productData?['name'] ?? 'Subscription',
      'description': '${_subscriptionPlan!['duration']} Subscription',
      'prefill': {
        'contact': _phoneController.text,
        'email': FirebaseAuth.instance.currentUser?.email ?? '',
      },
      'method': {
        'upi': true,
        'card': true,
        'netbanking': true,
        'wallet': true,
      },
      'theme': {'color': '#3399cc'},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

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
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_productData == null || _subscriptionPlan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(child: Text('Product data not available')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Confirmation'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subscription Summary
              Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subscription Plan',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _productData?['name'] ?? 'Product',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_formatDuration(_subscriptionPlan!['duration'])} Plan',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('Price: ₹${_subscriptionPlan!['price']}'),
                      Text('Quantity: ${_subscriptionPlan!['quantity']}'),
                      if (_subscriptionPlan!['deliveryFrequency'] != null)
                        Text(
                            'Delivery: ${_subscriptionPlan!['deliveryFrequency']}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Delivery Details Form
              Text(
                'Delivery Information',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) =>
                value?.isEmpty ?? true ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Please enter your phone number';
                  }
                  if (value!.length != 10) {
                    return 'Enter a valid 10-digit number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(Icons.home),
                ),
                maxLines: 2,
                validator: (value) =>
                value?.isEmpty ?? true ? 'Please enter your address' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        prefixIcon: Icon(Icons.location_city),
                      ),
                      validator: (value) =>
                      value?.isEmpty ?? true ? 'Please enter your city' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'State',
                        prefixIcon: Icon(Icons.map),
                      ),
                      validator: (value) =>
                      value?.isEmpty ?? true ? 'Please enter your state' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pincodeController,
                decoration: const InputDecoration(
                  labelText: 'Pincode',
                  prefixIcon: Icon(Icons.pin_drop),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Please enter your pincode';
                  }
                  if (value!.length != 6) {
                    return 'Enter a valid 6-digit pincode';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _deliveryInstructionsController,
                decoration: const InputDecoration(
                  labelText: 'Delivery Instructions (Optional)',
                  prefixIcon: Icon(Icons.note),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 32),

              // Payment Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isProcessingPayment ? null : _openPaymentGateway,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isProcessingPayment
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                    'Pay ₹${_subscriptionPlan!['price']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

